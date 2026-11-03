#Requires -Version 5.1
<#
.SYNOPSIS
    Download the offline package Release asset and expand the browser payload.

.DESCRIPTION
    The browser payload (~621 MB) is not stored in git, it is published as a
    release asset. This script downloads that asset and extracts only the
    "payload" subtree into offline-package\payload\, so that
    install-offline.ps1 finds it where it expects it.

    Needs access to github.com. On a fully air-gapped machine, copy the
    release asset across by USB / file share and use -AssetPath instead.

.PARAMETER Repo
    owner/repo. Defaults to the "origin" remote of the current repository.

.PARAMETER Tag
    Release tag. Default: v0.6.2.7.

.PARAMETER AssetPath
    Use an already downloaded asset instead of fetching it from GitHub.

.PARAMETER Destination
    Where to place the payload. Default: .\offline-package

.EXAMPLE
    .\scripts\fetch-payload.ps1 -Repo owner/repo

.EXAMPLE
    .\scripts\fetch-payload.ps1 -AssetPath D:\transfer\ego-lite-offline.zip
#>
[CmdletBinding()]
param(
    [string] $Repo,
    [string] $Tag = 'v0.6.2.7',
    [string] $AssetPath,
    [string] $Destination,
    [switch] $Verify
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Write-Step([string]$m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok([string]$m)   { Write-Host "    [ok] $m" -ForegroundColor Green }
function Write-Note([string]$m) { Write-Host "    [--] $m" -ForegroundColor Yellow }

$pkgRoot = Split-Path -Parent $PSScriptRoot
if (-not $Destination) { $Destination = Join-Path $pkgRoot 'offline-package' }
$payloadDir = Join-Path $Destination 'payload'

if (-not $Repo -and -not $AssetPath) {
    try {
        $url = (& git remote get-url origin 2>$null | Select-Object -First 1)
        if ($url -match 'github\.com[:/](?<o>[^/]+)/(?<r>[^/\s]+?)(\.git)?$') { $Repo = "$($Matches.o)/$($Matches.r)" }
    } catch { }
}
if (-not $Repo -and -not $AssetPath) {
    throw 'Could not determine the repository. Use -Repo owner/repo or -AssetPath <file>.'
}

# ---- get the asset -----------------------------------------------------
$temp = $null
if ($AssetPath) {
    if (-not (Test-Path -LiteralPath $AssetPath)) { throw "Asset not found: $AssetPath" }
    $local = (Get-Item -LiteralPath $AssetPath).FullName
    Write-Step ('Using local asset: ' + $local)
} else {
    $ver = $Tag.TrimStart('v')
    $names = @(
        "ego-lite-$ver-win-x64-offline-package.zip",
        "ego-lite-$ver-win-x64-offline.zip"
    )
    $temp = Join-Path ([IO.Path]::GetTempPath()) ("ego-payload-" + [Guid]::NewGuid().ToString('N') + '.zip')
    $local = $temp
    $ok = $false
    foreach ($n in $names) {
        $url = "https://github.com/$Repo/releases/download/$Tag/$n"
        Write-Step "Downloading $n"
        try {
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($url, $local)
            $ok = $true
            break
        } catch {
            Write-Note ("failed: " + $_.Exception.Message)
        }
    }
    if (-not $ok) { throw "Could not download a release asset from $Repo at tag $Tag." }
    Write-Ok ('downloaded ' + [math]::Round((Get-Item $local).Length / 1MB, 1) + ' MB')
}

# ---- extract only the payload subtree ---------------------------------
Write-Step 'Extracting payload'
$zip = [IO.Compression.ZipFile]::OpenRead($local)
$count = 0
try {
    foreach ($e in $zip.Entries) {
        if ([string]::IsNullOrEmpty($e.Name)) { continue }          # directory entry
        $idx = $e.FullName.IndexOf('/payload/')
        if ($idx -lt 0) { continue }
        $rel = $e.FullName.Substring($idx + 9)                       # after "payload/"
        if ([string]::IsNullOrEmpty($rel)) { continue }
        $target = Join-Path $payloadDir ($rel -replace '/', '\')
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
        [IO.File]::Copy($e.FullName, $target, $true) 2>$null
        $es = $e.Open()
        $fs = [IO.File]::Open($target, [IO.FileMode]::Create)
        $es.CopyTo($fs)
        $fs.Close(); $es.Close()
        $count++
    }
} finally {
    $zip.Dispose()
}
Write-Ok ("extracted $count files -> $payloadDir")

if ($temp -and (Test-Path -LiteralPath $temp)) {
    try { [IO.File]::Delete($temp) } catch { }
}

# ---- sanity check ------------------------------------------------------
$browser = Join-Path $payloadDir 'app\0.6.2.7\ego-browser.exe'
if (Test-Path -LiteralPath $browser) {
    Write-Ok 'payload looks complete (ego-browser.exe found)'
} else {
    Write-Note 'ego-browser.exe not found in the extracted payload - check the archive layout.'
}

if ($Verify) {
    $sums = Join-Path $Destination 'checksums.txt'
    if (Test-Path -LiteralPath $sums) {
        Write-Step 'Verifying checksums'
        $bad = 0; $done = 0
        foreach ($line in [IO.File]::ReadAllLines($sums)) {
            if ($line -notmatch '^([0-9A-Fa-f]{64})\s+(.+)$') { continue }
            $hash = $matches[1]; $rel = $matches[2] -replace '^payload/app/', '' -replace '/', '\'
            $f = Join-Path (Join-Path $payloadDir 'app') $rel
            if (-not (Test-Path -LiteralPath $f)) { $bad++; continue }
            if ((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash -ne $hash.ToUpper()) { $bad++ }
            $done++
        }
        Write-Ok "verified $done files, problems: $bad"
    }
}

Write-Host ''
Write-Host 'Next: run offline-package\install-offline.ps1' -ForegroundColor White
Write-Host ''
