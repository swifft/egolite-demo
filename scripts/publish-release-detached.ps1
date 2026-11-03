#Requires -Version 5.1
<#
.SYNOPSIS
    Detached (background) uploader for the ego(lite) offline package Release asset.

.DESCRIPTION
    scripts/publish-release.ps1 uploads the asset inside the current session.
    On a slow link the ~303 MB upload can easily exceed a session or agent
    command time limit, which aborts the transfer half way.

    This variant runs the transfer in a separate, detached PowerShell process
    and writes a progress log, so the upload survives the calling session.
    It reuses the credential already stored by Git Credential Manager, keeps
    the token in memory only, and never writes it to disk.

    Typical use:
      1) start it detached
      2) poll the log until it prints DONE

.PARAMETER Repo
    owner/repo.

.PARAMETER AssetPath
    The archive to upload.

.PARAMETER LogPath
    Where to write the progress log.

.PARAMETER Tag
    Release tag. Default: v0.6.2.7

.EXAMPLE
    $log = 'D:\myCode\ai\minimax\_upload.log'
    Start-Process powershell -WindowStyle Hidden -ArgumentList @(
      '-NoProfile','-ExecutionPolicy','Bypass','-File','.\scripts\publish-release-detached.ps1',
      '-Repo','swifft/egolite-demo',
      '-AssetPath','D:\myCode\ai\minimax\ego-lite-0.6.2.7-win-x64-offline-package.zip',
      '-LogPath',$log)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $AssetPath,
    [Parameter(Mandatory)] [string] $LogPath,
    [string] $Tag = 'v0.6.2.7'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

function Log([string]$m) {
    $line = ('[' + (Get-Date -Format 'HH:mm:ss') + '] ' + $m)
    [IO.File]::AppendAllText($LogPath, $line + "`r`n", [Text.Encoding]::UTF8)
}

try {
    Log 'START'

    # ---- token from the local credential manager (memory only) ----
    $credIn = Join-Path $env:TEMP ('gc_' + [Guid]::NewGuid().ToString('N') + '.txt')
    [IO.File]::WriteAllText($credIn, "protocol=https`r`nhost=github.com`r`nusername=swifft`r`n`r`n")
    $raw = cmd /c "git credential fill < `"$credIn`"" 2>&1
    $token = $null
    foreach ($l in $raw) { if ($l -match '^password=(?<v>.+)$') { $token = $matches.v } }
    try { [IO.File]::Delete($credIn) } catch { }
    if (-not $token) { throw 'no credential available for github.com' }
    Log 'token acquired (kept in memory)'

    $headers = @{
        Authorization = "Bearer $token"; Accept = 'application/vnd.github+json'
        'User-Agent' = 'ego-offline-publisher'; 'X-GitHub-Api-Version' = '2022-11-28'
    }

    # ---- release ----
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag" -Headers $headers -TimeoutSec 60
    Log ('release: ' + $rel.html_url)
    $uploadUrl = ($rel.upload_url -replace '\{.*\}$', '')

    # ---- upload ----
    $asset = Get-Item -LiteralPath $AssetPath
    $total = $asset.Length
    Log ('uploading ' + $asset.Name + ' (' + [math]::Round($total / 1MB, 1) + ' MB)')

    $client = New-Object System.Net.Http.HttpClient
    $client.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $token)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('ego-offline-publisher')
    $client.Timeout = [TimeSpan]::FromHours(3)

    $src = [IO.File]::OpenRead($asset.FullName)
    try {
        $content = New-Object System.Net.Http.StreamContent($src)
        $content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/zip')
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, "$uploadUrl`?name=$($asset.Name)")
        $req.Content = $content
        $resp = $client.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if (-not $resp.IsSuccessStatusCode) {
            $detail = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            throw ("upload failed: " + [int]$resp.StatusCode + ' ' + $resp.ReasonPhrase + ' :: ' + $detail)
        }
        Log 'request accepted, transferring body...'
        $out = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $out.Close()
    } finally {
        $src.Close()
        $client.Dispose()
    }

    # ---- verify against GitHub's own digest ----
    $rel2 = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag" -Headers $headers -TimeoutSec 60
    $a = $rel2.assets | Where-Object { $_.name -eq $asset.Name } | Select-Object -First 1
    if (-not $a) { throw 'asset not registered after upload' }
    Log ('asset: ' + $a.name + '  ' + [math]::Round($a.size / 1MB, 1) + ' MB  state=' + $a.state)
    Log ('digest: ' + $a.digest)
    Log ('local : sha256:' + (Get-FileHash -LiteralPath $asset.FullName -Algorithm SHA256).Hash.ToLower())
    Log ('SUCCESS ' + $a.browser_download_url)
    Log 'DONE'
    exit 0
} catch {
    Log ('FAILED: ' + $_.Exception.Message)
    exit 1
}
