# Step CA Server Startup Script
# This script starts the Step CA server for testing

param(
    [Parameter(Mandatory=$false)]
    [switch]$Stop = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$Status = $false
)

$ErrorActionPreference = "Stop"

$stepCAPath = "test\step-ca"
$stepExe = "step-cli\step_0.25.2\bin\step.exe"
$configFile = "test\step-ca\config\ca.json"
$passwordFile = "test\step-ca\secrets\password"

Write-Host "🏛️  Step CA Server Management" -ForegroundColor Green
Write-Host "=============================" -ForegroundColor Green

if ($Status) {
    Write-Host "📊 Checking Step CA Status..." -ForegroundColor Yellow
    
    try {
        $response = Invoke-WebRequest -Uri "https://localhost:9000/health" -SkipCertificateCheck -TimeoutSec 5
        Write-Host "✅ Step CA is running and healthy" -ForegroundColor Green
        Write-Host "   Status Code: $($response.StatusCode)" -ForegroundColor Gray
        Write-Host "   URL: https://localhost:9000" -ForegroundColor Gray
    } catch {
        Write-Host "❌ Step CA is not running or not accessible" -ForegroundColor Red
        Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Gray
    }
    return
}

if ($Stop) {
    Write-Host "🛑 Stopping Step CA..." -ForegroundColor Yellow
    
    # Find and stop any running step-ca processes
    $processes = Get-Process -Name "step" -ErrorAction SilentlyContinue
    if ($processes) {
        foreach ($proc in $processes) {
            Write-Host "   Stopping process ID: $($proc.Id)" -ForegroundColor Gray
            Stop-Process -Id $proc.Id -Force
        }
        Write-Host "✅ Step CA stopped" -ForegroundColor Green
    } else {
        Write-Host "ℹ️  No Step CA processes found" -ForegroundColor Blue
    }
    return
}

# Start Step CA
Write-Host "🚀 Starting Step CA Server..." -ForegroundColor Yellow

# Verify files exist
if (-not (Test-Path $stepExe)) {
    Write-Host "❌ Step CLI not found at: $stepExe" -ForegroundColor Red
    Write-Host "   Please run setup-test-env.ps1 first" -ForegroundColor Gray
    exit 1
}

if (-not (Test-Path $configFile)) {
    Write-Host "❌ Step CA config not found at: $configFile" -ForegroundColor Red
    Write-Host "   Please run Step CA initialization first" -ForegroundColor Gray
    exit 1
}

if (-not (Test-Path $passwordFile)) {
    Write-Host "📝 Creating password file..." -ForegroundColor Yellow
    "testpassword" | Out-File -FilePath $passwordFile -Encoding ASCII -NoNewline
}

# Set environment
$env:STEPPATH = $stepCAPath

Write-Host "   Config: $configFile" -ForegroundColor Gray
Write-Host "   STEPPATH: $stepCAPath" -ForegroundColor Gray
Write-Host "   Port: 9000" -ForegroundColor Gray
Write-Host ""

try {
    # Start Step CA server
    Write-Host "🔧 Starting Step CA server..." -ForegroundColor Cyan
    Write-Host "   Press Ctrl+C to stop the server" -ForegroundColor Gray
    Write-Host ""
    
    # Use the correct step-ca command syntax
    & $stepExe ca $configFile --password-file $passwordFile
    
} catch {
    Write-Host "❌ Failed to start Step CA: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "🏁 Step CA server stopped" -ForegroundColor Green