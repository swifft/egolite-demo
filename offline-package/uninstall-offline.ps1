#Requires -Version 5.1
<#
.SYNOPSIS
    Offline uninstaller for ego(lite) on Windows x64.

.DESCRIPTION
    Reverses install-offline.ps1:
      - removes the junctions under %USERPROFILE%\.local\share\ego
      - removes the ego-browser entry from the user PATH
      - removes the uninstall entry and the App Paths registry key
      - removes the ego-browser Skill from the agent skills directories
      - removes the installed program files

    User data (browser profiles, imported data, Spaces) lives in
    %LOCALAPPDATA%\ego lite and is kept unless -RemoveUserData is passed.

.PARAMETER InstallDir
    Install directory to remove. Defaults to the same rule as the installer.

.PARAMETER Version
    Version folder. Default: 0.6.2.7

.PARAMETER RemoveUserData
    Also delete %LOCALAPPDATA%\ego lite (profiles, imported browser data).

.PARAMETER KeepFiles
    Only undo PATH / registry / Skill, keep the program files.
#>
[CmdletBinding()]
param(
    [string] $InstallDir,
    [string] $Version = '0.6.2.7',
    [switch] $RemoveUserData,
    [switch] $KeepFiles
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok([string]$m)   { Write-Host "    [ok] $m" -ForegroundColor Green }
function Write-Note([string]$m) { Write-Host "    [--] $m" -ForegroundColor Yellow }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Remove-Link([string]$link) {
    if (-not (Test-Path -LiteralPath $link)) { return $false }
    $item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        [IO.Directory]::Delete($link, $false)
        return $true
    }
    return $false
}

$admin = Test-Admin
if (-not $InstallDir) {
    if ($admin) { $InstallDir = 'C:\Program Files\Citro Labs\ego lite\Application' }
    else        { $InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\Citro Labs\ego lite\Application' }
}
$InstallDir  = [IO.Path]::GetFullPath($InstallDir)
$linkRoot    = Join-Path $env:USERPROFILE '.local\share\ego'
$versionLink = Join-Path $linkRoot 'active_version_dir'
$skillsLink  = Join-Path $linkRoot 'ego-skills'

Write-Host ''
Write-Host 'ego(lite) offline uninstaller' -ForegroundColor White
Write-Host ("  target   : {0}" -f $InstallDir)
Write-Host ("  elevated : {0}" -f $admin)
Write-Host ''

Get-Process -Name 'ego' -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Note "stopping running process: ego (pid $($_.Id))"
    try { $_.Kill() } catch { }
}
Start-Sleep -Milliseconds 400

# ------------------------------------------------------------- junctions
Write-Step 'Removing junctions'
foreach ($l in @($versionLink, $skillsLink)) {
    if (Remove-Link $l) { Write-Ok "removed junction: $l" }
    else { Write-Note "not present: $l" }
}

# ----------------------------------------------------------------- PATH
Write-Step 'Updating user PATH'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($null -ne $userPath -and $userPath -ne '') {
    $norm = ($versionLink -replace '/', '\').TrimEnd('\')
    $all  = @($userPath -split ';' | Where-Object { $_ -ne '' })
    $kept = @($all | Where-Object { (($_ -replace '/', '\').TrimEnd('\')) -ine $norm })
    if ($kept.Count -ne $all.Count) {
        [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
        Write-Ok 'removed the ego-browser directory from the user PATH'
    } else {
        Write-Note 'PATH does not contain the ego-browser directory'
    }
}

# ------------------------------------------------------------- registry
Write-Step 'Removing registry entries'
foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Citro Labs ego lite',
                 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Citro Labs ego lite',
                 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\ego.exe',
                 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\ego.exe')) {
    if (Test-Path -LiteralPath $k) {
        Remove-Item -LiteralPath $k -Recurse -Force -ErrorAction SilentlyContinue
        Write-Ok "removed: $k"
    }
}

# ---------------------------------------------------------------- Skill
Write-Step 'Removing the Agent Skill'
$roots = @('.agents', '.claude', '.codex', '.cursor', '.gemini', '.opencode',
           '.config\opencode', '.minimax', '.hermes', '.openclaw', '.workbuddy',
           '.codeium', '.windsurf', '.kiro', '.qwen', '.trae')
foreach ($r in $roots) {
    $dest = Join-Path (Join-Path $env:USERPROFILE $r) 'skills\ego-browser'
    if (Test-Path -LiteralPath $dest) {
        if (Test-Path -LiteralPath (Join-Path $dest 'SKILL.md')) {
            [IO.Directory]::Delete($dest, $true)
            Write-Ok "removed: $dest"
        }
    }
}

# ----------------------------------------------------------- program files
if ($KeepFiles) {
    Write-Note 'program files kept (-KeepFiles)'
} elseif (Test-Path -LiteralPath $InstallDir) {
    Write-Step 'Removing program files'
    [IO.Directory]::Delete($InstallDir, $true)
    Write-Ok "removed: $InstallDir"
} else {
    Write-Note "not present: $InstallDir"
}

$userData = Join-Path $env:LOCALAPPDATA 'ego lite'
if ($RemoveUserData) {
    if (Test-Path -LiteralPath $userData) {
        Write-Step 'Removing user data'
        [IO.Directory]::Delete($userData, $true)
        Write-Ok "removed: $userData"
    }
} elseif (Test-Path -LiteralPath $userData) {
    Write-Note ("user data kept: {0}  (use -RemoveUserData to delete it)" -f $userData)
}

Write-Host ''
Write-Host 'Uninstall finished.' -ForegroundColor White
Write-Host ''
