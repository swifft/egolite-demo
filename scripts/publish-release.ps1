#Requires -Version 5.1
<#
.SYNOPSIS
    Publish the offline package as a GitHub Release asset.

.DESCRIPTION
    The browser payload is ~621 MB and must not be committed to git
    (GitHub rejects files over 100 MB). This script publishes it as a release
    asset instead, where a single file may be up to 2 GB.

    It can either use an existing release (created via the GitHub UI) or
    create a new tagged release first.

    The token needs the "repo" scope on a classic PAT, or Contents:Read and
    write on a fine-grained PAT. It is read from -Token or from the
    GITHUB_TOKEN environment variable and is never written to disk.

.PARAMETER Repo
    owner/repo. Defaults to the "origin" remote of the current repository.

.PARAMETER Tag
    Release tag. Default: v<version>.

.PARAMETER AssetPath
    The file to upload. Default: the workspace-level offline package archive.

.PARAMETER Notes
    Release body text. A sensible default is used when omitted.

.EXAMPLE
    $env:GITHUB_TOKEN = 'ghp_xxx'
    .\scripts\publish-release.ps1 -Repo owner/repo

.EXAMPLE
    .\scripts\publish-release.ps1 -Repo owner/repo -Tag v0.6.2.7 -AssetPath D:\pkg.zip

.NOTES
    On a slow link the ~303 MB upload can outlast a session or agent command
    time limit. Use scripts\publish-release-detached.ps1 for that case: it
    runs the transfer in a detached process with a progress log.
#>
[CmdletBinding()]
param(
    [string] $Repo,
    [string] $Tag = 'v0.6.2.7',
    [string] $AssetPath,
    [string] $Title,
    [string] $Notes,
    [string] $Token,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok([string]$m)   { Write-Host "    [ok] $m" -ForegroundColor Green }
function Write-Note([string]$m) { Write-Host "    [--] $m" -ForegroundColor Yellow }

# ---- resolve repo ------------------------------------------------------
if (-not $Repo) {
    try {
        $url = (& git remote get-url origin 2>$null | Select-Object -First 1)
        if ($url -match 'github\.com[:/](?<o>[^/]+)/(?<r>[^/\s]+?)(\.git)?$') { $Repo = "$($Matches.o)/$($Matches.r)" }
    } catch { }
}
if (-not $Repo) { throw "Repo not given and could not be derived from the 'origin' remote. Use -Repo owner/repo." }
Write-Step "Repository: $Repo"

# ---- resolve token -----------------------------------------------------
if (-not $Token) { $Token = $env:GITHUB_TOKEN }
if (-not $Token) {
    Write-Note 'No token supplied.'
    Write-Note 'Create one at https://github.com/settings/tokens (classic, scope "repo") and run:'
    Write-Note '  $env:GITHUB_TOKEN = "ghp_xxx"'
    Write-Note 'The token is used in memory only and is never written to disk.'
    throw 'GITHUB_TOKEN is required.'
}

# ---- resolve asset -----------------------------------------------------
$pkgRoot = Split-Path -Parent $PSScriptRoot
if (-not $AssetPath) {
    $candidates = @(
        (Join-Path $pkgRoot "ego-lite-$($Tag.TrimStart('v'))-win-x64-offline-package.zip"),
        (Join-Path (Split-Path -Parent $pkgRoot) "ego-lite-$($Tag.TrimStart('v'))-win-x64-offline-package.zip"),
        (Join-Path (Split-Path -Parent $pkgRoot) "ego-lite-$($Tag.TrimStart('v'))-win-x64-offline.zip")
    )
    $AssetPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $AssetPath -or -not (Test-Path -LiteralPath $AssetPath)) {
    throw "Asset not found. Build it first or pass -AssetPath <file>."
}
$asset = Get-Item -LiteralPath $AssetPath
Write-Step ('Asset: {0} ({1} MB)' -f $asset.FullName, [math]::Round($asset.Length / 1MB, 1))

if (-not $Title) { $Title = "ego(lite) $($Tag.TrimStart('v')) Windows x64 离线包" }
if (-not $Notes) {
    $Notes = @"
ego(lite) $($Tag.TrimStart('v')) Windows x64 离线部署包。

- 官方安装器是联网 mini installer，本附件携带解包后的完整负载（621.6 MB / 837 文件），安装全程不联网。
- 解压后把 ``offline-package/payload/`` 放到仓库同级的 ``offline-package/`` 下，再运行 ``install-offline.ps1``。
- ``checksums.txt`` 提供逐文件 SHA-256 校验。
- 浏览器二进制是 Citro Labs 的专有分发物，仅限已授权的内部离线环境使用，请勿公开分享。
"@
}

$headers = @{
    'Authorization' = "Bearer $Token"
    'Accept'        = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent'    = 'ego-offline-publisher'
}

# ---- create or reuse the release --------------------------------------
Write-Step 'Creating release'
$body = @{ tag_name = $Tag; name = $Title; body = $Notes; draft = $false; prerelease = $false } | ConvertTo-Json
try {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases" -Method Post -Headers $headers -Body $body -ContentType 'application/json'
    Write-Ok "created release: $($rel.html_url)"
} catch {
    $msg = $_.Exception.Message
    if ($msg -match 'already_exists' -or $msg -match 'Validation Failed') {
        Write-Note 'A release with this tag already exists, reusing it.'
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag" -Headers $headers
        Write-Ok "release: $($rel.html_url)"
    } else {
        throw
    }
}

# ---- upload the asset --------------------------------------------------
$uploadUrl = $rel.upload_url -replace '\{.*\}$', ''
$name = $asset.Name
Write-Step "Uploading $name"

if ($DryRun) {
    Write-Note 'Dry run: would upload to ' + $uploadUrl + '?name=' + $name
    Write-Note 'Release URL: ' + $rel.html_url
    return
}

Add-Type -AssemblyName System.Net.Http
$client = New-Object System.Net.Http.HttpClient
$client.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $Token)
$client.DefaultRequestHeaders.UserAgent.ParseAdd('ego-offline-publisher')
$client.Timeout = [TimeSpan]::FromHours(2)

$stream = [IO.File]::OpenRead($asset.FullName)
try {
    $content = New-Object System.Net.Http.StreamContent($stream)
    $content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/zip')
    $resp = $client.PostAsync("$uploadUrl`?name=$name", $content).GetAwaiter().GetResult()
    if (-not $resp.IsSuccessStatusCode) {
        $detail = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        throw "Upload failed: $([int]$resp.StatusCode) $($resp.ReasonPhrase) :: $detail"
    }
    $info = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
    Write-Ok ('uploaded: {0} ({1} MB)' -f $info.name, [math]::Round($info.size / 1MB, 1))
} finally {
    $stream.Close()
    $client.Dispose()
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor White
Write-Host ('  Release : ' + $rel.html_url)
Write-Host ('  Asset   : ' + $name)
Write-Host ''
