#Requires -Version 5.1

<#
.SYNOPSIS
    Installation script for Certificate Renewal Service (PowerShell Edition)
    
.DESCRIPTION
    Installs required PowerShell modules and validates the environment for running
    the Certificate Renewal Service.
    
.EXAMPLE
    .\Install-CertRenewalService.ps1
    
.EXAMPLE
    .\Install-CertRenewalService.ps1 -Scope AllUsers
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser'
)

Write-Host "🚀 Certificate Renewal Service - Installation" -ForegroundColor Cyan
Write-Host ("=" * 50)

# Check PowerShell version
Write-Host "`n✓ Checking PowerShell version..." -ForegroundColor Yellow
$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -lt 5) {
    Write-Host "❌ PowerShell 5.1 or later is required (current: $psVersion)" -ForegroundColor Red
    exit 1
}
Write-Host "  PowerShell version: $psVersion" -ForegroundColor Green

# Install powershell-yaml module
Write-Host "`n✓ Installing powershell-yaml module..." -ForegroundColor Yellow
try {
    if (Get-Module -ListAvailable -Name powershell-yaml) {
        Write-Host "  Module already installed" -ForegroundColor Green
    } else {
        Install-Module -Name powershell-yaml -Scope $Scope -Force -AllowClobber
        Write-Host "  ✓ Module installed successfully" -ForegroundColor Green
    }
}
catch {
    Write-Host "  ❌ Failed to install powershell-yaml: $_" -ForegroundColor Red
    Write-Host "  Try running as Administrator or use -Scope CurrentUser" -ForegroundColor Yellow
    exit 1
}

# Check for Step CLI
Write-Host "`n✓ Checking for Step CLI..." -ForegroundColor Yellow
$stepExe = $null

# Check if step is in PATH
$stepInPath = Get-Command step -ErrorAction SilentlyContinue
if ($stepInPath) {
    $stepExe = $stepInPath.Source
    Write-Host "  ✓ Found in PATH: $stepExe" -ForegroundColor Green
}
# Check local step-cli directory (relative to parent directory)
elseif (Test-Path "..\step-cli\step_0.25.2\bin\step.exe") {
    $stepExe = Resolve-Path "..\step-cli\step_0.25.2\bin\step.exe"
    Write-Host "  ✓ Found locally: $stepExe" -ForegroundColor Green
}
else {
    Write-Host "  ⚠ Step CLI not found" -ForegroundColor Yellow
    Write-Host "  Download from: https://smallstep.com/docs/step-cli/installation/" -ForegroundColor Yellow
}

# Check for Step CA
Write-Host "`n✓ Checking for Step CA..." -ForegroundColor Yellow
$dockerRunning = docker ps 2>$null | Select-String "step-ca"
if ($dockerRunning) {
    Write-Host "  ✓ Step CA Docker container is running" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Step CA Docker container not detected" -ForegroundColor Yellow
    Write-Host "  Start with: docker-compose up -d" -ForegroundColor Yellow
}

# Verify required directories exist
Write-Host "`n✓ Checking directory structure..." -ForegroundColor Yellow

# Get parent directory (project root)
$parentDir = Split-Path $PSScriptRoot -Parent
$requiredDirs = @(
    "ps-scripts",
    "test/test-config",
    "test/logs",
    "test/client-certs",
    "test/client-certs/crl"
)

foreach ($dir in $requiredDirs) {
    $fullPath = Join-Path $parentDir $dir
    if (Test-Path $fullPath) {
        Write-Host "  ✓ $dir" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ Creating $dir" -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
    }
}

# Test configuration loading
Write-Host "`n✓ Testing configuration loading..." -ForegroundColor Yellow
$configPath = Join-Path $parentDir "test\test-config\config.yaml"
if (Test-Path $configPath) {
    try {
        . "$PSScriptRoot\CertRenewalConfig.ps1"
        $config = Get-CertRenewalConfig -ConfigPath $configPath
        Write-Host "  ✓ Configuration loaded successfully" -ForegroundColor Green
        Write-Host "    - Certificates to monitor: $($config.certificates.Count)" -ForegroundColor Cyan
        Write-Host "    - Renewal threshold: $($config.renewal_threshold_percent)%" -ForegroundColor Cyan
        Write-Host "    - CRL enabled: $($config.step_ca.crl_enabled)" -ForegroundColor Cyan
    }
    catch {
        Write-Host "  ❌ Failed to load configuration: $_" -ForegroundColor Red
    }
} else {
    Write-Host "  ⚠ Test configuration not found" -ForegroundColor Yellow
}

# Summary
Write-Host "`n" + ("=" * 50)
Write-Host "✅ Installation complete!" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "  1. Ensure Step CA is running: docker-compose up -d"
Write-Host "  2. Review configuration: test\test-config\config.yaml"
Write-Host "  3. Run a test check: .\ps-scripts\Start-CertRenewalService.ps1 -ConfigPath test\test-config\config.yaml -Mode check"
Write-Host "  4. Run as service: .\ps-scripts\Start-CertRenewalService.ps1 -ConfigPath config\config.yaml -Mode service"
Write-Host ""
