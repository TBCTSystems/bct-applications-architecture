# Certificate Renewal Service - PowerShell Setup Script
# Run this script to set up the Certificate Renewal Service on Windows

param(
    [Parameter(Mandatory=$false)]
    [string]$StepCAUrl = "https://your-step-ca:9000",
    
    [Parameter(Mandatory=$false)]
    [string]$StepCAFingerprint = "",
    
    [Parameter(Mandatory=$false)]
    [string]$ProvisionerName = "admin",
    
    [Parameter(Mandatory=$false)]
    [string]$InstallPath = "C:\Program Files\CertRenewalService"
)

Write-Host "Certificate Renewal Service Setup" -ForegroundColor Green
Write-Host "===================================" -ForegroundColor Green

# Check for Administrator privileges
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator"
    exit 1
}

# Check Python installation
try {
    $pythonVersion = python --version 2>$null
    Write-Host "Found Python: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Error "Python is not installed or not in PATH. Please install Python 3.8+ first."
    exit 1
}

# Check Step CLI installation
try {
    $stepVersion = step version 2>$null
    Write-Host "Found Step CLI: $stepVersion" -ForegroundColor Green
} catch {
    Write-Warning "Step CLI not found. Downloading and installing..."
    
    # Download and install Step CLI
    $stepUrl = "https://github.com/smallstep/cli/releases/latest/download/step_windows_amd64.zip"
    $tempPath = "$env:TEMP\step.zip"
    
    Invoke-WebRequest -Uri $stepUrl -OutFile $tempPath
    Expand-Archive -Path $tempPath -DestinationPath "$env:TEMP\step" -Force
    
    # Copy to Program Files
    $stepInstallPath = "C:\Program Files\step"
    New-Item -ItemType Directory -Path $stepInstallPath -Force
    Copy-Item "$env:TEMP\step\*" $stepInstallPath -Recurse -Force
    
    # Add to PATH
    $envPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    if ($envPath -notlike "*$stepInstallPath*") {
        [Environment]::SetEnvironmentVariable("PATH", "$envPath;$stepInstallPath", "Machine")
    }
    
    Write-Host "Step CLI installed successfully" -ForegroundColor Green
    Remove-Item $tempPath -Force
    Remove-Item "$env:TEMP\step" -Recurse -Force
}

# Create installation directory
Write-Host "Creating installation directory: $InstallPath" -ForegroundColor Yellow
New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null

# Copy service files
Write-Host "Copying service files..." -ForegroundColor Yellow
Copy-Item ".\*" -Destination $InstallPath -Recurse -Force -Exclude @("logs", "certs", ".git", "__pycache__")

# Create directories
New-Item -ItemType Directory -Path "$InstallPath\logs" -Force | Out-Null
New-Item -ItemType Directory -Path "$InstallPath\certs" -Force | Out-Null

# Install Python dependencies
Write-Host "Installing Python dependencies..." -ForegroundColor Yellow
Set-Location $InstallPath
pip install -r requirements.txt

# Create configuration
Write-Host "Creating configuration files..." -ForegroundColor Yellow

# Create environment file
$envContent = @"
# Certificate Renewal Service Configuration
CERT_RENEWAL_STEP_CA__CA_URL=$StepCAUrl
CERT_RENEWAL_STEP_CA__CA_FINGERPRINT=$StepCAFingerprint
CERT_RENEWAL_STEP_CA__PROVISIONER_NAME=$ProvisionerName
CERT_RENEWAL_LOG_LEVEL=INFO
CERT_RENEWAL_CHECK_INTERVAL_MINUTES=30
"@

$envContent | Out-File -FilePath "$InstallPath\.env" -Encoding UTF8

# Create Windows service configuration
$serviceScript = @"
import sys
import os
sys.path.insert(0, r'$InstallPath')
os.chdir(r'$InstallPath')
from main import cli
if __name__ == '__main__':
    cli(['daemon'])
"@

$serviceScript | Out-File -FilePath "$InstallPath\service_main.py" -Encoding UTF8

# Create batch file for service
$batchContent = @"
@echo off
cd /d "$InstallPath"
python service_main.py
"@

$batchContent | Out-File -FilePath "$InstallPath\run_service.bat" -Encoding ASCII

Write-Host "`nSetup completed successfully!" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Update the configuration in $InstallPath\.env"
Write-Host "2. Add your certificates to $InstallPath\config\config.yaml"
Write-Host "3. Initialize the service: cd '$InstallPath' && python main.py init"
Write-Host "4. Test the service: python main.py status"
Write-Host "5. Run the service: python main.py daemon"
Write-Host "`nFor Windows Service installation, run:" -ForegroundColor Cyan
Write-Host "sc create CertRenewalService binPath= '$InstallPath\run_service.bat' start= auto"

# Create desktop shortcut
$shortcutPath = "$env:PUBLIC\Desktop\Certificate Renewal Service.lnk"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-NoExit -Command ""cd '$InstallPath'; python main.py status"""
$shortcut.WorkingDirectory = $InstallPath
$shortcut.Description = "Certificate Renewal Service Status"
$shortcut.Save()

Write-Host "Desktop shortcut created: $shortcutPath" -ForegroundColor Green