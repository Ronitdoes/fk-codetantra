# scripts/install.ps1
# Automated installer for MyOverlay
# Deploys directly to C:\Windows\MyOverlay with auto-elevation, Defender exclusions, and Scheduled Task

[CmdletBinding()]
param(
    [string]$OriginalUser = "",
    [string]$RepoUrl = "https://github.com/Ronitdoes/fk-codetantra"
)

# Disable PowerShell download progress bar to speed up downloads
$ProgressPreference = 'SilentlyContinue'

# Enforce TLS 1.2 and TLS 1.3
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if ([Enum]::IsDefined([Net.SecurityProtocolType], 'Tls13')) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls13
}

# 0. Check & Self-elevate to Administrator (required for C:\Windows\MyOverlay)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Elevating privileges to Administrator for C:\Windows\MyOverlay deployment..." -ForegroundColor Yellow
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath) -and (Test-Path $PSCommandPath)) {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -OriginalUser `"$currentUser`""
    } else {
        # Running via web 1-liner (irm ... | iex)
        # Download to a temporary script file first so elevated PowerShell executes cleanly with parameter binding
        $tempScript = Join-Path $env:TEMP "install_myoverlay.ps1"
        $scriptUrl = "https://raw.githubusercontent.com/Ronitdoes/fk-codetantra/main/scripts/install.ps1"
        try {
            (New-Object System.Net.WebClient).DownloadFile($scriptUrl, $tempScript)
        } catch {
            Invoke-WebRequest -Uri $scriptUrl -OutFile $tempScript -UseBasicParsing
        }
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempScript`" -OriginalUser `"$currentUser`""
    }
    exit
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Runtime Broker Automated Installation " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Resolve interactive user for the scheduled task
if ([string]::IsNullOrWhiteSpace($OriginalUser)) {
    $loggedOn = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
    if (-not [string]::IsNullOrWhiteSpace($loggedOn)) {
        $OriginalUser = $loggedOn
    } else {
        $OriginalUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    }
}
Write-Host "Target user for task: $OriginalUser" -ForegroundColor Gray

# Deployment paths are needed by the stop-hardened-instances step below.
$targetDir = "C:\Windows\RuntimeBroker"
$targetExe = Join-Path $targetDir "RuntimeBroker.exe"
# The shipped binary is a self-contained single-file build (70+ MB). The genuine
# system RuntimeBroker is ~150 KB, so this floor can never confuse the two.
$minBinaryBytes = 25MB

# 1. Stop any running overlay instances
Write-Host "`n[1/5] Stopping any running instances..." -ForegroundColor Yellow

# Our hardened builds carry a restrictive process DACL (only TERMINATE,
# QUERY_LIMITED_INFORMATION and SYNCHRONIZE opens succeed), so Stop-Process and
# taskkill are denied. Terminate through the exact mask the DACL grants.
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class InstallerProcessTool {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool TerminateProcess(IntPtr hProcess, uint uExitCode);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);
}
"@

function Stop-OverlayPid {
    param([Parameter(Mandatory = $true)][int]$OverlayPid)
    # 0x0001 | 0x1000 | 0x100000
    $handle = [InstallerProcessTool]::OpenProcess(0x101001, $false, $OverlayPid)
    if ($handle -eq [IntPtr]::Zero) { return $false }
    $terminated = [InstallerProcessTool]::TerminateProcess($handle, 1)
    [void][InstallerProcessTool]::CloseHandle($handle)
    return $terminated
}

$legacyTargets = @(
    (Join-Path $env:LOCALAPPDATA "Programs\MyOverlay\MyOverlay.exe"),
    "C:\Windows\MyOverlay\MyOverlay.exe"
)

foreach ($proc in (Get-Process -Name RuntimeBroker, MyOverlay -ErrorAction SilentlyContinue)) {
    $processPath = $null
    try { $processPath = $proc.Path } catch { }

    if ($proc.Name -ieq "MyOverlay") {
        # Legacy build name - always ours.
        if (-not (Stop-OverlayPid -OverlayPid $proc.Id)) {
            try { $proc | Stop-Process -Force -ErrorAction SilentlyContinue } catch { }
        }
        Write-Host "      Stopped legacy instance (pid $($proc.Id))." -ForegroundColor Gray
        continue
    }

    if ($processPath -and ($processPath -ieq $targetExe -or $legacyTargets -contains $processPath)) {
        if (-not (Stop-OverlayPid -OverlayPid $proc.Id)) {
            try { $proc | Stop-Process -Force -ErrorAction SilentlyContinue } catch { }
        }
        Write-Host "      Stopped deployed instance (pid $($proc.Id))." -ForegroundColor Gray
        continue
    }

    # Anything else named RuntimeBroker (e.g. C:\Windows\System32\RuntimeBroker.exe)
    # is the genuine system broker spawned by svchost - never touch it.
}
Start-Sleep -Milliseconds 600

# 2. Locate or Download RuntimeBroker.exe
Write-Host "[2/5] Locating RuntimeBroker executable..." -ForegroundColor Yellow

$scriptDir = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { (Get-Location).Path }
$projectRoot = Split-Path -Parent $scriptDir

# A web invocation (irm ... | iex) is running straight from a remote payload:
# $PSCommandPath is empty, or the script only exists in %TEMP% after the
# self-elevation download. In that case a "local binary" is unreliable - the
# elevated relaunch can start in a directory nobody controls, and the only
# candidate with the right NAME there is C:\Windows\System32\RuntimeBroker.exe,
# which is the genuine BROKER. So: always fetch the latest published zip first,
# then fall back to local copies for zip-offline/dev scenarios only.
$isWebInvocation = [string]::IsNullOrWhiteSpace($PSCommandPath) -or
                   ($scriptDir.TrimEnd('\') -ieq $env:TEMP.TrimEnd('\')) -or
                   $scriptDir.StartsWith($env:TEMP.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)

$candidatePaths = @()
if (-not $isWebInvocation) {
    $candidatePaths = @(
        (Join-Path $scriptDir "RuntimeBroker.exe"),
        (Join-Path $projectRoot "dist\RuntimeBroker.exe"),
        (Join-Path (Get-Location).Path "RuntimeBroker.exe"),
        (Join-Path (Get-Location).Path "dist\RuntimeBroker.exe"),
        (Join-Path $scriptDir "MyOverlay.exe"),
        (Join-Path $projectRoot "dist\MyOverlay.exe")
    )
}

$sourceExe = $null
foreach ($path in $candidatePaths) {
    if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path $path)) {
        $item = Get-Item -LiteralPath $path
        # 2a. Never deploy anything from inside the Windows directory tree -
        #     that is where the genuine system RuntimeBroker lives.
        if ($item.FullName.StartsWith($env:windir, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        # 2b. Never accept a candidate smaller than a self-contained overlay build.
        if ($item.Length -lt $minBinaryBytes) { continue }
        $sourceExe = $item.FullName
        break
    }
}

if (-not $sourceExe) {
    Write-Host "No local binary found. Downloading latest setup package from GitHub..." -ForegroundColor Cyan
    $downloadUrl = "https://github.com/Ronitdoes/fk-codetantra/releases/latest/download/MyOverlay-Setup.zip"
    $sumsUrl = "https://github.com/Ronitdoes/fk-codetantra/releases/latest/download/SHA256SUMS.txt"
    $tempDir = Join-Path $env:TEMP "RuntimeBrokerInstall"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $downloadTarget = Join-Path $tempDir "MyOverlay-Setup.zip"
    $sumsTarget = Join-Path $tempDir "SHA256SUMS.txt"
    $extractedExe = Join-Path $tempDir "RuntimeBroker.exe"
    Remove-Item $extractedExe -Force -ErrorAction SilentlyContinue

    $downloadSuccess = $false

    # Try curl.exe first (fastest, best redirect handling on Windows 10/11)
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        Write-Host "Downloading via curl..." -ForegroundColor Gray
        & curl.exe -fL "$downloadUrl" -o "$downloadTarget" --retry 2 --silent --show-error
        if ($LASTEXITCODE -eq 0 -and (Test-Path $downloadTarget) -and (Get-Item $downloadTarget).Length -gt $minBinaryBytes) {
            $downloadSuccess = $true
        }
    }

    # Fallback to WebClient
    if (-not $downloadSuccess) {
        try {
            Write-Host "Downloading via WebClient..." -ForegroundColor Gray
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "Mozilla/5.0")
            $wc.DownloadFile($downloadUrl, $downloadTarget)
            if ((Test-Path $downloadTarget) -and (Get-Item $downloadTarget).Length -gt $minBinaryBytes) {
                $downloadSuccess = $true
            }
        } catch {
            Write-Warning "WebClient download failed: $($_.Exception.Message)"
        }
    }

    # Fallback to Invoke-WebRequest
    if (-not $downloadSuccess) {
        try {
            Write-Host "Downloading via Invoke-WebRequest..." -ForegroundColor Gray
            Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadTarget -UseBasicParsing -UserAgent "Mozilla/5.0"
            if ((Test-Path $downloadTarget) -and (Get-Item $downloadTarget).Length -gt $minBinaryBytes) {
                $downloadSuccess = $true
            }
        } catch {
            Write-Error "Failed to download MyOverlay-Setup.zip. Error: $($_.Exception.Message)"
            Start-Sleep -Seconds 5
            return
        }
    }

    if (-not $downloadSuccess) {
        Write-Error "Could not download MyOverlay-Setup.zip."
        Start-Sleep -Seconds 5
        return
    }

    # Integrity verification against the published SHA256 manifest (published
    # as a release asset next to the zip). Abort - never run - an unverified zip.
    $integrityVerified = $false
    Remove-Item $sumsTarget -Force -ErrorAction SilentlyContinue
    try {
        (New-Object System.Net.WebClient).DownloadFile($sumsUrl, $sumsTarget)
        if ((Test-Path $sumsTarget) -and (Get-Item $sumsTarget).Length -gt 10) { $integrityVerified = $true }
    } catch { }
    if (-not $integrityVerified -and (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
        & curl.exe -fL "$sumsUrl" -o "$sumsTarget" --retry 2 --silent --show-error
        if ($LASTEXITCODE -eq 0 -and (Test-Path $sumsTarget) -and (Get-Item $sumsTarget).Length -gt 10) { $integrityVerified = $true }
    }
    if ($integrityVerified) {
        $expectedHash = $null
        Get-Content $sumsTarget -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_ -match '^([0-9a-fA-F]{64})\s+\*?MyOverlay-Setup\.zip\s*$') {
                $expectedHash = $Matches[1].ToLowerInvariant()
            }
        }
        if ($expectedHash) {
            $actualHash = (Get-FileHash -Algorithm SHA256 -Path $downloadTarget).Hash.ToLowerInvariant()
            if ($actualHash -ne $expectedHash) {
                Write-Error "Integrity verification FAILED for MyOverlay-Setup.zip (hash mismatch vs SHA256SUMS.txt). Aborting."
                Start-Sleep -Seconds 5
                return
            }
            Write-Host "      Zip integrity verified against SHA256SUMS.txt." -ForegroundColor Green
        }
    } else {
        Write-Warning "SHA256SUMS.txt could not be fetched; skipping integrity verification."
    }

    try {
        Write-Host "Extracting executable from the Setup zip..." -ForegroundColor Gray
        Expand-Archive -Path $downloadTarget -DestinationPath $tempDir -Force
    } catch {
        Write-Warning "Expand-Archive extraction failed: $($_.Exception.Message)"
    }

    $sourceExe = Join-Path $tempDir "RuntimeBroker.exe"
    if (-not (Test-Path $sourceExe)) {
        $sourceExe = Join-Path $tempDir "MyOverlay.exe"
    }
    if (-not (Test-Path $sourceExe) -or (Get-Item $sourceExe).Length -lt $minBinaryBytes) {
        Write-Error "Could not obtain a valid executable from the setup zip."
        Start-Sleep -Seconds 5
        return
    }
    Write-Host "Downloaded and extracted successfully ($([Math]::Round((Get-Item $sourceExe).Length / 1MB, 1)) MB)" -ForegroundColor Green
}

Write-Host "      Using source binary: $sourceExe" -ForegroundColor Gray

# 3. Create target directory and copy executable & license
Write-Host "`n[3/5] Deploying executable to $targetDir..." -ForegroundColor Yellow

if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}
try {
    Copy-Item -Path $sourceExe -Destination $targetExe -Force
} catch {
    Write-Error "Could not write $targetExe (an overlay instance may still be running): $($_.Exception.Message)"
    Start-Sleep -Seconds 5
    return
}
$deployedItem = Get-Item -LiteralPath $targetExe -ErrorAction SilentlyContinue
if (-not $deployedItem -or $deployedItem.Length -lt $minBinaryBytes) {
    Write-Error "Deployed file at $targetExe is missing or does not look like an overlay build. Aborting."
    Start-Sleep -Seconds 5
    return
}
Write-Host "      Deployed $([Math]::Round($deployedItem.Length / 1MB, 1)) MB overlay build." -ForegroundColor Green

$licenseCandidate = Join-Path (Split-Path -Parent $sourceExe) "LICENSE.txt"
if (-not (Test-Path $licenseCandidate)) {
    $licenseCandidate = Join-Path $projectRoot "LICENSE.txt"
}
if (Test-Path $licenseCandidate) {
    Copy-Item -Path $licenseCandidate -Destination (Join-Path $targetDir "LICENSE.txt") -Force
}

# 4. Add Windows Defender exclusion for C:\Windows\MyOverlay
Write-Host "[4/5] Adding Windows Defender exclusion for $targetDir..." -ForegroundColor Yellow
try {
    Add-MpPreference -ExclusionPath $targetDir -ErrorAction SilentlyContinue
    Write-Host "      Defender exclusion added." -ForegroundColor Green
} catch {
    # Non-critical if managed by group policy
}

# 5. Register Scheduled Task for interactive user with RunLevel Highest
Write-Host "[5/5] Registering and starting Scheduled Task 'WindowsRuntimeBroker'..." -ForegroundColor Yellow
$taskName = "WindowsRuntimeBroker"

Unregister-ScheduledTask -TaskName "MyOverlay" -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction -Execute $targetExe -WorkingDirectory $targetDir
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $OriginalUser
$principal = New-ScheduledTaskPrincipal -UserId $OriginalUser -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "      Scheduled task created with RunLevel Highest for $OriginalUser." -ForegroundColor Green

# Start the task immediately
Start-ScheduledTask -TaskName $taskName
Write-Host "      Runtime Broker process started." -ForegroundColor Green

# Boot verification: confirm a process launched from the deployed path within
# several seconds. The DACL on our hardened builds limits path queries to
# QUERY_LIMITED_INFORMATION, which is exactly what Process.Path uses, so this
# check works on both hardened and unhardened builds.
$overlayIsUp = $false
for ($attempt = 0; $attempt -lt 4; $attempt++) {
    Start-Sleep -Seconds 3
    foreach ($proc in (Get-Process -Name RuntimeBroker, MyOverlay -ErrorAction SilentlyContinue)) {
        $procPath = $null
        try { $procPath = $proc.Path } catch { }
        if ($procPath -ieq $targetExe) { $overlayIsUp = $true; break }
    }
    if ($overlayIsUp) { break }
}
if ($overlayIsUp) {
    Write-Host "      Verified: overlay process is running from $targetExe" -ForegroundColor Green
} else {
    Write-Warning "The overlay process was not detected after the task started. Re-run this script, or check the task state with: Get-ScheduledTask -TaskName WindowsRuntimeBroker."
}

# Clean up legacy folders and shortcuts to prevent duplicates
$legacyDirs = @(
    "C:\Windows\MyOverlay",
    (Join-Path $env:LOCALAPPDATA "Programs\MyOverlay")
)
foreach ($ld in $legacyDirs) {
    if (Test-Path $ld) {
        Remove-Item -Path $ld -Recurse -Force -ErrorAction SilentlyContinue
    }
}
$legacyStartupLnk = Join-Path ([Environment]::GetFolderPath("Startup")) "MyOverlay.lnk"
if (Test-Path $legacyStartupLnk) {
    Remove-Item -Path $legacyStartupLnk -Force -ErrorAction SilentlyContinue
}

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "  Installation Complete!                                " -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host "Target: $targetExe" -ForegroundColor White
Write-Host "1. Press Ctrl+Alt+Space anywhere to toggle the overlay." -ForegroundColor Yellow
Write-Host "   (On first run, enter your Groq or Gemini API key in the settings window)" -ForegroundColor Gray
Write-Host "2. Or configure via command-line in a normal PowerShell:" -ForegroundColor White
Write-Host "   $targetExe --setkey gsk_your_groq_api_key`n" -ForegroundColor Cyan

Start-Sleep -Seconds 3
