# Step CA Initialization Script for Testing (PowerShell)
# This script initializes a Step CA instance for testing the certificate renewal service

param(
    [Parameter(Mandatory=$false)]
    [string]$CAName = "Test-CA",
    
    [Parameter(Mandatory=$false)]
    [string]$DNS = "localhost,step-ca,127.0.0.1",
    
    [Parameter(Mandatory=$false)]
    [string]$Address = ":9000",
    
    [Parameter(Mandatory=$false)]
    [string]$Provisioner = "admin",
    
    [Parameter(Mandatory=$false)]
    [string]$CAPassword = "testpassword",
    
    [Parameter(Mandatory=$false)]
    [string]$ProvisionerPassword = "adminpassword"
)

$ErrorActionPreference = "Stop"

Write-Host "Step CA Test Environment Initialization" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

# Get script directory and set STEPPATH
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$StepPath = Join-Path $ScriptDir "step-ca"

Write-Host "Setting STEPPATH to: $StepPath" -ForegroundColor Yellow
$env:STEPPATH = $StepPath

# Create step-ca directory if it doesn't exist
New-Item -ItemType Directory -Path $StepPath -Force | Out-Null

# Remove existing CA configuration if present
$ConfigPath = Join-Path $StepPath "config"
if (Test-Path $ConfigPath) {
    Write-Host "Removing existing CA configuration..." -ForegroundColor Yellow
    Remove-Item $ConfigPath -Recurse -Force
}

Write-Host "Initializing Step CA..." -ForegroundColor Yellow

# Create temporary password files
$TempDir = [System.IO.Path]::GetTempPath()
$CAPasswordFile = Join-Path $TempDir "ca_password.txt"
$ProvisionerPasswordFile = Join-Path $TempDir "provisioner_password.txt"

$CAPassword | Out-File -FilePath $CAPasswordFile -Encoding ASCII -NoNewline
$ProvisionerPassword | Out-File -FilePath $ProvisionerPasswordFile -Encoding ASCII -NoNewline

try {
    # Initialize Step CA
    $stepCommand = @(
        "step", "ca", "init",
        "--name=$CAName",
        "--dns=$DNS", 
        "--address=$Address",
        "--provisioner=$Provisioner",
        "--password-file=$CAPasswordFile",
        "--provisioner-password-file=$ProvisionerPasswordFile",
        "--no-db"
    )
    
    Write-Host "Running: $($stepCommand -join ' ')" -ForegroundColor Cyan
    
    & $stepCommand[0] $stepCommand[1..($stepCommand.Length-1)]
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Step CA initialized successfully!" -ForegroundColor Green
        
        # Get CA fingerprint
        $RootCertPath = Join-Path $StepPath "certs\root_ca.crt"
        if (Test-Path $RootCertPath) {
            try {
                $fingerprint = & step certificate fingerprint $RootCertPath
                Write-Host "CA Fingerprint: $fingerprint" -ForegroundColor Cyan
                
                # Save fingerprint to file for easy access
                $FingerprintFile = Join-Path (Split-Path $ScriptDir) "ca-fingerprint.txt"
                $fingerprint | Out-File -FilePath $FingerprintFile -Encoding UTF8
                
                Write-Host ""
                Write-Host "Step CA Configuration:" -ForegroundColor Green
                Write-Host "  Name: $CAName" -ForegroundColor White
                Write-Host "  Address: https://localhost:9000" -ForegroundColor White
                Write-Host "  Provisioner: $Provisioner" -ForegroundColor White
                Write-Host "  Password: $ProvisionerPassword" -ForegroundColor White
                Write-Host "  Root CA: $RootCertPath" -ForegroundColor White
                Write-Host "  Fingerprint: $fingerprint" -ForegroundColor White
                Write-Host ""
                Write-Host "To start the CA server:" -ForegroundColor Yellow
                Write-Host "  step-ca `$env:STEPPATH\config\ca.json" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Or using Docker:" -ForegroundColor Yellow
                Write-Host "  cd test && docker-compose -f docker-compose.test.yml up -d step-ca-test" -ForegroundColor Cyan
                
            } catch {
                Write-Warning "Could not get CA fingerprint: $($_.Exception.Message)"
            }
        } else {
            Write-Warning "Root certificate not found at expected location: $RootCertPath"
        }
        
    } else {
        Write-Error "Failed to initialize Step CA (exit code: $LASTEXITCODE)"
    }
    
} catch {
    Write-Error "Failed to initialize Step CA: $($_.Exception.Message)"
} finally {
    # Clean up password files
    if (Test-Path $CAPasswordFile) {
        Remove-Item $CAPasswordFile -Force
    }
    if (Test-Path $ProvisionerPasswordFile) {
        Remove-Item $ProvisionerPasswordFile -Force
    }
}