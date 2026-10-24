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
Write-Host "  MyOverlay Automated Installation      " -ForegroundColor Cyan
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

# 1. Stop any running MyOverlay instances
Write-Host "`n[1/5] Stopping any running MyOverlay instances..." -ForegroundColor Yellow
Get-Process -Name MyOverlay -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600

# 2. Locate or Download MyOverlay.exe
Write-Host "[2/5] Locating MyOverlay executable..." -ForegroundColor Yellow

$scriptDir = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { (Get-Location).Path }
$projectRoot = Split-Path -Parent $scriptDir

$candidatePaths = @(
    (Join-Path $scriptDir "MyOverlay.exe"),
    (Join-Path $projectRoot "dist\MyOverlay.exe"),
    (Join-Path (Get-Location).Path "MyOverlay.exe"),
    (Join-Path (Get-Location).Path "dist\MyOverlay.exe")
)

$sourceExe = $null
foreach ($path in $candidatePaths) {
    if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path $path)) {
        $sourceExe = $path
        break
    }
}

if (-not $sourceExe) {
    # The bare MyOverlay.exe is not published as a release asset - only
    # MyOverlay-Setup.zip is. Download the zip and extract the exe from it.
    Write-Host "No local binary found. Downloading latest MyOverlay-Setup.zip from GitHub..." -ForegroundColor Cyan
    $downloadUrl = "https://github.com/Ronitdoes/fk-codetantra/releases/latest/download/MyOverlay-Setup.zip"
    $tempDir = Join-Path $env:TEMP "MyOverlayInstall"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $downloadTarget = Join-Path $tempDir "MyOverlay-Setup.zip"
    $extractedExe = Join-Path $tempDir "MyOverlay.exe"
    Remove-Item $extractedExe -Force -ErrorAction SilentlyContinue

    $downloadSuccess = $false

    # Try curl.exe first (fastest, best redirect handling on Windows 10/11)
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        Write-Host "Downloading via curl..." -ForegroundColor Gray
        & curl.exe -fL "$downloadUrl" -o "$downloadTarget" --retry 2 --silent --show-error
        if ($LASTEXITCODE -eq 0 -and (Test-Path $downloadTarget) -and (Get-Item $downloadTarget).Length -gt 1000000) {
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
            if ((Test-Path $downloadTarget) -and (Get-Item $downloadTarget).Length -gt 1000000) {
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
            if ((Test-Path $downloadTarget) -and (Get-Item $downloadTarget).Length -gt 1000000) {
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

    try {
        Write-Host "Extracting MyOverlay.exe from the Setup zip..." -ForegroundColor Gray
        Expand-Archive -Path $downloadTarget -DestinationPath $tempDir -Force
    } catch {
        Write-Warning "Expand-Archive extraction failed: $($_.Exception.Message)"
    }

    $sourceExe = $extractedExe
    if (-not (Test-Path $sourceExe) -or (Get-Item $sourceExe).Length -le 1000000) {
        Write-Error "Could not obtain a valid MyOverlay.exe executable from MyOverlay-Setup.zip."
        Start-Sleep -Seconds 5
        return
    }
    Write-Host "Downloaded and extracted successfully ($([Math]::Round((Get-Item $sourceExe).Length / 1MB, 1)) MB)" -ForegroundColor Green
}

Write-Host "      Using source binary: $sourceExe" -ForegroundColor Gray

# 3. Create target directory and copy executable & license
$targetDir = "C:\Windows\MyOverlay"
$targetExe = Join-Path $targetDir "MyOverlay.exe"
Write-Host "`n[3/5] Deploying executable to $targetDir..." -ForegroundColor Yellow

if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}
Copy-Item -Path $sourceExe -Destination $targetExe -Force

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
Write-Host "[5/5] Registering and starting Scheduled Task 'MyOverlay'..." -ForegroundColor Yellow
$taskName = "MyOverlay"

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction -Execute $targetExe -WorkingDirectory $targetDir
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $OriginalUser
$principal = New-ScheduledTaskPrincipal -UserId $OriginalUser -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "      Scheduled task created with RunLevel Highest for $OriginalUser." -ForegroundColor Green

# Start the task immediately
Start-ScheduledTask -TaskName $taskName
Write-Host "      MyOverlay process started." -ForegroundColor Green

# Clean up any legacy LocalAppData install folder to prevent duplicates
$legacyDir = Join-Path $env:LOCALAPPDATA "Programs\MyOverlay"
if (Test-Path $legacyDir) {
    Remove-Item -Path $legacyDir -Recurse -Force -ErrorAction SilentlyContinue
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
