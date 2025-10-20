# Certificate Renewal Service Startup Script
# This script provides easy commands to start the certificate renewal service

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("daemon", "check", "status", "renew", "help")]
    [string]$Command,
    
    [Parameter(Mandatory=$false)]
    [string]$CertificateName = "",
    
    [Parameter(Mandatory=$false)]
    [string]$Config = "test\test-config\config.yaml",
    
    [Parameter(Mandatory=$false)]
    [switch]$Production = $false
)

$ErrorActionPreference = "Stop"

# Set up environment
Write-Host "🚀 Certificate Renewal Service" -ForegroundColor Green
Write-Host "==============================" -ForegroundColor Green

# Add Step CLI to PATH
$stepCliPath = Join-Path (Get-Location) "step-cli\step_0.25.2\bin"
if (Test-Path $stepCliPath) {
    $env:PATH += ";$stepCliPath"
    Write-Host "✅ Step CLI added to PATH" -ForegroundColor Green
} else {
    Write-Host "⚠️  Step CLI not found at $stepCliPath" -ForegroundColor Yellow
    Write-Host "   Service may not work without Step CLI" -ForegroundColor Yellow
}

# Activate virtual environment
$venvScript = ".venv\Scripts\Activate.ps1"
if (Test-Path $venvScript) {
    & $venvScript
    Write-Host "✅ Virtual environment activated" -ForegroundColor Green
} else {
    Write-Host "⚠️  Virtual environment not found" -ForegroundColor Yellow
}

# Use production config if requested
if ($Production) {
    $Config = "config\config.yaml"
    Write-Host "📋 Using production configuration: $Config" -ForegroundColor Cyan
} else {
    Write-Host "🧪 Using test configuration: $Config" -ForegroundColor Cyan
}

# Verify config exists
if (-not (Test-Path $Config)) {
    Write-Host "❌ Configuration file not found: $Config" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Execute the requested command
switch ($Command) {
    "daemon" {
        Write-Host "🔄 Starting Certificate Renewal Daemon..." -ForegroundColor Yellow
        Write-Host "   Press Ctrl+C to stop" -ForegroundColor Gray
        Write-Host ""
        
        try {
            python main.py --config $Config daemon
        } catch {
            Write-Host "❌ Daemon failed to start: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }
    
    "check" {
        Write-Host "⚡ Running Single Certificate Check..." -ForegroundColor Yellow
        Write-Host ""
        
        try {
            python main.py --config $Config check
            Write-Host ""
            Write-Host "✅ Certificate check completed" -ForegroundColor Green
        } catch {
            Write-Host "❌ Certificate check failed: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }
    
    "status" {
        Write-Host "📊 Checking Certificate Status..." -ForegroundColor Yellow
        Write-Host ""
        
        try {
            python main.py --config $Config status
        } catch {
            Write-Host "❌ Status check failed: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }
    
    "renew" {
        if (-not $CertificateName) {
            Write-Host "❌ Certificate name required for renewal" -ForegroundColor Red
            Write-Host "   Usage: .\start-renewal-service.ps1 renew -CertificateName 'cert-name'" -ForegroundColor Gray
            exit 1
        }
        
        Write-Host "🎯 Renewing Certificate: $CertificateName..." -ForegroundColor Yellow
        Write-Host ""
        
        try {
            python main.py --config $Config renew $CertificateName
            Write-Host ""
            Write-Host "✅ Certificate renewal completed" -ForegroundColor Green
        } catch {
            Write-Host "❌ Certificate renewal failed: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }
    
    "help" {
        Write-Host "Certificate Renewal Service Commands:" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "📋 Available Commands:" -ForegroundColor White
        Write-Host "  daemon    - Run continuous renewal service" -ForegroundColor Gray
        Write-Host "  check     - Run single certificate check" -ForegroundColor Gray
        Write-Host "  status    - Show certificate status" -ForegroundColor Gray
        Write-Host "  renew     - Renew specific certificate" -ForegroundColor Gray
        Write-Host "  help      - Show this help" -ForegroundColor Gray
        Write-Host ""
        Write-Host "🧪 Examples:" -ForegroundColor White
        Write-Host "  .\start-renewal-service.ps1 daemon" -ForegroundColor Gray
        Write-Host "  .\start-renewal-service.ps1 check" -ForegroundColor Gray
        Write-Host "  .\start-renewal-service.ps1 status" -ForegroundColor Gray
        Write-Host "  .\start-renewal-service.ps1 renew -CertificateName 'test-web-server'" -ForegroundColor Gray
        Write-Host ""
        Write-Host "⚙️  Options:" -ForegroundColor White
        Write-Host "  -Config       - Configuration file path" -ForegroundColor Gray
        Write-Host "  -Production   - Use production config" -ForegroundColor Gray
        Write-Host ""
        Write-Host "🔧 Advanced Usage:" -ForegroundColor White
        Write-Host "  python main.py --config $Config --help" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "🏁 Certificate Renewal Service operation completed" -ForegroundColor Green