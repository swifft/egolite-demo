#Requires -Version 5.1
<#
.SYNOPSIS
    Offline installer for ego(lite) on Windows x64. Requires no network access.

.DESCRIPTION
    The official installer (egoliteSetup-*.exe) is a Chromium "mini installer":
    it is only a bootstrapper and downloads the real browser payload from
    update.citrolabs.ai while it runs. On an air-gapped machine it therefore
    fails. This package carries the payload itself, and this script performs
    the same wiring the official installer does:

      1. Copy the application payload into the install directory.
      2. Create the junctions under %USERPROFILE%\.local\share\ego
         (active_version_dir -> <install dir>\<version>,
          ego-skills         -> <install dir>\<version>\ego-skills\ego-browser).
      3. Add <link root>\active_version_dir to the user PATH so that the
         `ego-browser` command resolves in every new terminal.
      4. Write the "Apps & features" uninstall entry and the App Paths key.
      5. Copy the version-matched ego-browser Skill into every agent skills
         directory that already exists on this machine.

    No administrator rights are required when the script is not elevated: the
    install then defaults to %LOCALAPPDATA%\Programs\... .

.PARAMETER InstallDir
    Target directory. Defaults to "C:\Program Files\Citro Labs\ego lite\Application"
    when elevated, otherwise "%LOCALAPPDATA%\Programs\Citro Labs\ego lite\Application".

.PARAMETER Version
    Version folder inside the payload. Default: 0.6.2.7

.PARAMETER SkipRegistry
    Do not write the uninstall entry / App Paths registry keys.

.PARAMETER SkipPath
    Do not touch PATH or create the PATH junction.

.PARAMETER SkipSkills
    Do not copy the Agent Skill into agent skills directories.

.PARAMETER ExtraSkillRoots
    Extra absolute paths whose "skills" folder should receive the Skill.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install-offline.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install-offline.ps1 -SkipRegistry -InstallDir D:\ego
#>
[CmdletBinding()]
param(
    [string]   $InstallDir,
    [string]   $Version = '0.6.2.7',
    [switch]   $SkipRegistry,
    [switch]   $SkipPath,
    [switch]   $SkipSkills,
    [string[]] $ExtraSkillRoots = @(),
    [switch]   $Force
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok([string]$m)   { Write-Host "    [ok] $m" -ForegroundColor Green }
function Write-Note([string]$m) { Write-Host "    [--] $m" -ForegroundColor Yellow }
function Write-Err([string]$m)  { Write-Host "    [!!] $m" -ForegroundColor Red }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Copy a directory tree with .NET APIs (fast, and it overwrites existing files).
function Copy-Tree([string]$src, [string]$dst) {
    if (-not (Test-Path -LiteralPath $src)) { throw "Source not found: $src" }
    [IO.Directory]::CreateDirectory($dst) | Out-Null
    $count = 0
    foreach ($f in [IO.Directory]::EnumerateFiles($src, '*', [IO.SearchOption]::AllDirectories)) {
        $rel = $f.Substring($src.Length).TrimStart('\')
        $t  = Join-Path $dst $rel
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($t)) | Out-Null
        [IO.File]::Copy($f, $t, $true)
        $count++
    }
    return $count
}

# Remove a junction/symlink without touching what it points at.
function Remove-Link([string]$link) {
    if (-not (Test-Path -LiteralPath $link)) { return $false }
    $item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        [IO.Directory]::Delete($link, $false)
        return $true
    }
    return $false
}

$admin    = Test-Admin
$pkgRoot  = $PSScriptRoot
$payload  = Join-Path $pkgRoot 'payload\app'

if (-not $InstallDir) {
    if ($admin) { $InstallDir = 'C:\Program Files\Citro Labs\ego lite\Application' }
    else        { $InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\Citro Labs\ego lite\Application' }
}
$InstallDir = [IO.Path]::GetFullPath($InstallDir)
$versionDir = Join-Path $InstallDir $Version
$linkRoot   = Join-Path $env:USERPROFILE '.local\share\ego'
$versionLink = Join-Path $linkRoot 'active_version_dir'
$skillsLink  = Join-Path $linkRoot 'ego-skills'

Write-Host ''
Write-Host 'ego(lite) offline installer' -ForegroundColor White
Write-Host ("  package  : {0}" -f $pkgRoot)
Write-Host ("  version  : {0}" -f $Version)
Write-Host ("  target   : {0}" -f $InstallDir)
Write-Host ("  elevated : {0}" -f $admin)
Write-Host ''

# ---------------------------------------------------------------- preflight
if (-not (Test-Path -LiteralPath (Join-Path $payload $Version))) {
    throw "Payload is missing or incomplete: expected folder '$Version' inside '$payload'."
}
if (-not (Test-Path -LiteralPath (Join-Path $payload "$Version\ego-browser.exe"))) {
    throw "Payload is incomplete: '$payload\$Version\ego-browser.exe' not found."
}
if ((Test-Path -LiteralPath $InstallDir) -and -not $Force) {
    $existing = @(Get-ChildItem -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) {
        Write-Note "Install directory already exists and is not empty: $InstallDir"
        Write-Note "Files will be overwritten. Re-run with -Force to silence this notice."
    }
}

# ------------------------------------------------- 1. stop the running app
Get-Process -Name 'ego' -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Note "stopping running process: ego (pid $($_.Id))"
    try { $_.Kill() } catch { }
}
Start-Sleep -Milliseconds 400

# ------------------------------------------------------- 2. copy payload
Write-Step 'Copying application payload'
$copied = Copy-Tree $payload $InstallDir
Write-Ok ("{0} files -> {1}" -f $copied, $InstallDir)

# -------------------------------------------- 3. junctions and PATH entry
if (-not $SkipPath) {
    Write-Step 'Creating PATH junction'
    [IO.Directory]::CreateDirectory($linkRoot) | Out-Null
    Remove-Link $versionLink | Out-Null
    New-Item -ItemType Junction -Path $versionLink -Target $versionDir | Out-Null
    Write-Ok ("junction: {0} -> {1}" -f $versionLink, $versionDir)

    Remove-Link $skillsLink | Out-Null
    New-Item -ItemType Junction -Path $skillsLink -Target (Join-Path $versionDir 'ego-skills\ego-browser') | Out-Null
    Write-Ok ("junction: {0} -> ego-skills\ego-browser" -f $skillsLink)

    Write-Step 'Updating user PATH'
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($null -eq $userPath) { $userPath = '' }
    # Compare with separators normalised: an earlier install may have used forward slashes.
    $norm  = ($versionLink -replace '/', '\').TrimEnd('\')
    $parts = @($userPath -split ';' | Where-Object { $_ -ne '' })
    $kept  = @($parts | Where-Object { (($_ -replace '/', '\').TrimEnd('\')) -ine $norm })
    if ($kept.Count -ne $parts.Count) {
        [Environment]::SetEnvironmentVariable('Path', (($kept + $versionLink) -join ';'), 'User')
        Write-Ok ("user PATH entry normalised/added: {0}" -f $versionLink)
    } else {
        Write-Ok 'user PATH already contains the ego-browser directory'
    }
    if (@($env:Path -split ';') -notcontains $versionLink) { $env:Path = $env:Path + ';' + $versionLink }
}

# ------------------------------------------------------- 4. registry keys
if (-not $SkipRegistry) {
    Write-Step 'Writing registry entries'
    if ($admin) {
        $uninstallPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Citro Labs ego lite'
        $appPaths      = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\ego.exe'
        $level         = '--system-level'
    } else {
        $uninstallPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Citro Labs ego lite'
        $appPaths      = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\ego.exe'
        $level         = '--user-level'
    }

    New-Item -Path $uninstallPath -Force | Out-Null
    $setupExe = Join-Path $versionDir 'Installer\setup.exe'
    $bytes    = (Get-ChildItem -LiteralPath $InstallDir -Recurse -File -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum).Sum
    $estSize  = [int]($bytes / 1024)
    $uninstall = '"' + $setupExe + '" --uninstall --ego-lite ' + $level + ' --verbose-logging'

    Set-ItemProperty -Path $uninstallPath -Name 'DisplayName'      -Value 'ego (lite)'
    Set-ItemProperty -Path $uninstallPath -Name 'DisplayVersion'   -Value $Version
    Set-ItemProperty -Path $uninstallPath -Name 'Publisher'        -Value 'Citro Labs Pte. Limited'
    Set-ItemProperty -Path $uninstallPath -Name 'InstallLocation'  -Value $InstallDir
    Set-ItemProperty -Path $uninstallPath -Name 'DisplayIcon'      -Value ((Join-Path $InstallDir 'ego.exe') + ',0')
    Set-ItemProperty -Path $uninstallPath -Name 'UninstallString'  -Value $uninstall
    Set-ItemProperty -Path $uninstallPath -Name 'NoModify'         -Value 1 -Type DWord
    Set-ItemProperty -Path $uninstallPath -Name 'NoRepair'         -Value 1 -Type DWord
    Set-ItemProperty -Path $uninstallPath -Name 'EstimatedSize'    -Value $estSize -Type DWord
    Write-Ok ("uninstall entry: {0}" -f $uninstallPath)

    New-Item -Path $appPaths -Force | Out-Null
    Set-ItemProperty -Path $appPaths -Name '(default)' -Value (Join-Path $InstallDir 'ego.exe')
    Set-ItemProperty -Path $appPaths -Name 'Path'      -Value $InstallDir
    Write-Ok ("app paths: {0}" -f $appPaths)
}

# ------------------------------------------------- 5. Agent Skill install
if (-not $SkipSkills) {
    Write-Step 'Installing the ego-browser Skill'
    $skillSrc = Join-Path $versionDir 'ego-skills\ego-browser'
    if (-not (Test-Path -LiteralPath $skillSrc)) {
        Write-Err "Skill folder not found in payload: $skillSrc"
    } else {
        $roots = @('.agents', '.claude', '.codex', '.cursor', '.gemini', '.opencode',
                   '.config\opencode', '.minimax', '.hermes', '.openclaw', '.workbuddy',
                   '.codeium', '.windsurf', '.kiro', '.qwen', '.trae')
        $targets = @()
        foreach ($r in $roots) {
            $p = Join-Path $env:USERPROFILE $r
            if (Test-Path -LiteralPath $p) { $targets += $p }
        }
        foreach ($p in $ExtraSkillRoots) {
            if (Test-Path -LiteralPath $p) { $targets += $p }
        }
        $targets = @($targets | Sort-Object -Unique)
        if ($targets.Count -eq 0) {
            Write-Note 'no agent directory detected; the Skill is still reachable through the junction'
            Write-Note ("  {0}" -f $skillsLink)
        }
        foreach ($p in $targets) {
            $dest = Join-Path $p 'skills\ego-browser'
            if (Test-Path -LiteralPath $dest) {
                $probe = Join-Path $dest 'SKILL.md'
                if (Test-Path -LiteralPath $probe) { [IO.Directory]::Delete($dest, $true) }
            }
            Copy-Tree $skillSrc $dest | Out-Null
            Write-Ok ("skill -> {0}" -f $dest)
        }
    }
}

# ------------------------------------------------------------ 6. verify
Write-Step 'Verifying'
$egoBrowser = Join-Path $versionLink 'ego-browser.exe'
if (Test-Path -LiteralPath $egoBrowser) {
    Write-Ok 'ego-browser.exe is reachable through the PATH junction'
    try {
        # ego-browser writes its banner to stderr, so merge both streams via cmd.
        $ver = cmd /c "`"$egoBrowser`" --version 2>&1"
        foreach ($line in @($ver)) {
            if ($line -and $line.Trim()) { Write-Host ("      " + $line.Trim()) }
        }
    } catch {
        Write-Err ("could not run ego-browser --version: " + $_.Exception.Message)
    }
} else {
    Write-Err 'ego-browser.exe not found'
}

Write-Host ''
Write-Host 'Done. Next steps:' -ForegroundColor White
Write-Host '  1. Start "ego (lite)" once and finish the first-run setup.'
Write-Host '     The setup offers to import data from Chrome or another browser (optional).'
Write-Host '  2. Open a NEW terminal so the updated PATH is picked up, then run:'
Write-Host '       ego-browser skill'
Write-Host '  3. In your agent (Codex / Claude Code / ...), pick the ego-browser Skill.'
Write-Host '     Codex needs "Full access" permission to start the browser.'
Write-Host ''
