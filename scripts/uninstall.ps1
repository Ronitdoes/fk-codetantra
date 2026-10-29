# scripts/uninstall.ps1
# Uninstaller for MyOverlay
# Supports running locally from release folder, extracted zip, or via 1-line PowerShell web command.

[CmdletBinding()]
param(
    [switch]$CleanAppData = $false,
    [string]$TargetUser = ""
)

# 0. Check & Self-elevate to Administrator (required to remove C:\Windows\MyOverlay and Scheduled Task)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Elevating privileges to Administrator to remove C:\Windows\MyOverlay..." -ForegroundColor Yellow
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath) -and (Test-Path $PSCommandPath)) {
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -TargetUser `"$currentUser`""
        if ($CleanAppData) { $argList += " -CleanAppData" }
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    } else {
        # Running via web 1-liner (irm ... | iex)
        $tempScript = Join-Path $env:TEMP "uninstall_myoverlay.ps1"
        $scriptUrl = "https://raw.githubusercontent.com/Ronitdoes/fk-codetantra/main/scripts/uninstall.ps1"
        try {
            (New-Object System.Net.WebClient).DownloadFile($scriptUrl, $tempScript)
        } catch {
            Invoke-WebRequest -Uri $scriptUrl -OutFile $tempScript -UseBasicParsing
        }
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$tempScript`" -TargetUser `"$currentUser`""
        if ($CleanAppData) { $argList += " -CleanAppData" }
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    }
    exit
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Runtime Broker Uninstallation         " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 1. Stop running processes
Write-Host "`n[1/4] Stopping processes..." -ForegroundColor Yellow
Get-Process -Name RuntimeBroker, MyOverlay -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600

# 2. Unregister Scheduled Tasks
Write-Host "[2/4] Removing Scheduled Tasks..." -ForegroundColor Yellow
try {
    Unregister-ScheduledTask -TaskName "WindowsRuntimeBroker" -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "MyOverlay" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "      Scheduled tasks removed." -ForegroundColor Green
} catch {
    # Non-critical
}

# 3. Remove Windows Defender exclusions
$targetDirs = @("C:\Windows\RuntimeBroker", "C:\Windows\MyOverlay")
Write-Host "[3/4] Removing Defender exclusions..." -ForegroundColor Yellow
foreach ($td in $targetDirs) {
    try {
        Remove-MpPreference -ExclusionPath $td -ErrorAction SilentlyContinue
    } catch { }
}

# 4. Remove installation files & shortcuts
Write-Host "[4/4] Removing installation files..." -ForegroundColor Yellow
$candidateDirs = @(
    "C:\Windows\RuntimeBroker",
    "C:\Windows\MyOverlay",
    (Join-Path $env:LOCALAPPDATA "Programs\MyOverlay")
)

foreach ($dir in $candidateDirs) {
    if (Test-Path $dir) {
        Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "      Removed $dir" -ForegroundColor Green
    }
}

$startupFolder = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupFolder "MyOverlay.lnk"
if (Test-Path $shortcutPath) {
    Remove-Item -Path $shortcutPath -Force -ErrorAction SilentlyContinue
}

if ($CleanAppData) {
    Write-Host "`nCleaning user settings and DPAPI keys..." -ForegroundColor Yellow
    $appDataDirs = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\RuntimeBroker"),
        (Join-Path $env:LOCALAPPDATA "MyOverlay")
    )
    foreach ($ad in $appDataDirs) {
        if (Test-Path $ad) {
            Remove-Item -Path $ad -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "      Removed user data at $ad" -ForegroundColor Green
        }
    }
} else {
    Write-Host "`nNote: Encrypted API keys and preferences preserved." -ForegroundColor Gray
    Write-Host "To remove settings completely, run: powershell -File scripts/uninstall.ps1 -CleanAppData" -ForegroundColor Gray
}

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "  Uninstallation Complete.                              " -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Start-Sleep -Seconds 2
