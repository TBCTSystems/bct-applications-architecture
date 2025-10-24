#Requires -Version 5.1

<#
.SYNOPSIS
    Start Certificate Renewal Service - PowerShell Edition
.DESCRIPTION
    Main entry point for the PowerShell-based certificate renewal service
.PARAMETER ConfigPath
    Path to the configuration YAML file
.PARAMETER Mode
    Operation mode: 'check' for single check, 'service' for continuous monitoring
.EXAMPLE
    .\Start-CertRenewalService.ps1 -ConfigPath .\test\test-config\config.yaml -Mode check
.EXAMPLE
    .\Start-CertRenewalService.ps1 -ConfigPath .\config\config.yaml -Mode service
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "test\test-config\config.yaml",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('check', 'service')]
    [string]$Mode = 'check'
)

# Set error action preference
$ErrorActionPreference = 'Stop'

# Banner
Write-Host "🚀 Certificate Renewal Service - PowerShell Edition" -ForegroundColor Cyan
Write-Host "=" * 50 -ForegroundColor Cyan

try {
    # Check if step CLI is available
    if (Get-Command step -ErrorAction SilentlyContinue) {
        Write-Host "✅ Step CLI found in PATH" -ForegroundColor Green
    } else {
        Write-Warning "Step CLI not found in PATH. Some functionality may be limited."
    }
    
    # Resolve config path - make it relative to the parent directory
    if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
        # Script is in ps-scripts, so go up one level for relative paths
        $parentDir = Split-Path $PSScriptRoot -Parent
        $ConfigPath = Join-Path $parentDir $ConfigPath
    }
    
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }
    
    Write-Host "📁 Using configuration: $ConfigPath" -ForegroundColor Green
    Write-Host ""
    
    # Load modules in correct order (dependencies first)
    . "$PSScriptRoot\CertRenewalConfig.ps1"
    . "$PSScriptRoot\CertRenewalLogger.ps1"
    . "$PSScriptRoot\CRLManager.ps1"
    . "$PSScriptRoot\StepCAClient.ps1"
    . "$PSScriptRoot\CertMonitor.ps1"
    . "$PSScriptRoot\CertRenewalService.ps1"
    
    # Create service instance
    $service = [CertificateRenewalService]::new($ConfigPath)
    
    switch ($Mode) {
        'check' {
            Write-Host "⚡ Running Single Certificate Check..." -ForegroundColor Yellow
            Write-Host ""
            $service.RunOnce()
            Write-Host ""
            Write-Host "✅ Certificate check completed" -ForegroundColor Green
        }
        
        'service' {
            Write-Host "🔄 Starting Continuous Monitoring Service..." -ForegroundColor Yellow
            Write-Host "Press Ctrl+C to stop the service" -ForegroundColor Gray
            Write-Host ""
            
            # Setup Ctrl+C handler
            [Console]::TreatControlCAsInput = $false
            $null = Register-ObjectEvent -InputObject ([Console]) -EventName CancelKeyPress -Action {
                Write-Host "`n⚠️  Stopping service..." -ForegroundColor Yellow
                $service.Stop()
            }
            
            try {
                $service.RunContinuous()
            }
            finally {
                Get-EventSubscriber | Where-Object { $_.SourceObject -is [Console] } | Unregister-Event
            }
        }
    }
    
    Write-Host ""
    Write-Host "🏁 Certificate Renewal Service operation completed" -ForegroundColor Cyan
}
catch {
    Write-Host ""
    Write-Host "❌ Error: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
