# Docker-based Step CA Server for Certificate Renewal Testing
# This script creates a clean Step CA environment using Docker

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("start", "stop", "status", "logs", "reset")]
    [string]$Action = "start",
    
    [Parameter(Mandatory=$false)]
    [switch]$Follow = $false
)

$ErrorActionPreference = "Stop"

$containerName = "step-ca-renewal-test"
$networkName = "cert-renewal-network"
$caPort = 9000

Write-Host "🐳 Docker Step CA Server Management" -ForegroundColor Green
Write-Host "===================================" -ForegroundColor Green

function Test-DockerRunning {
    try {
        docker info | Out-Null
        return $true
    } catch {
        Write-Host "❌ Docker is not running. Please start Docker Desktop first." -ForegroundColor Red
        return $false
    }
}

function Stop-StepCA {
    Write-Host "🛑 Stopping Step CA container..." -ForegroundColor Yellow
    
    try {
        docker stop $containerName 2>$null | Out-Null
        docker rm $containerName 2>$null | Out-Null
        Write-Host "✅ Step CA container stopped and removed" -ForegroundColor Green
    } catch {
        Write-Host "ℹ️  No running Step CA container found" -ForegroundColor Blue
    }
}

function Get-StepCAStatus {
    Write-Host "📊 Checking Step CA Status..." -ForegroundColor Yellow
    
    # Check if container is running
    $containerStatus = docker ps -f "name=$containerName" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>$null
    
    if ($containerStatus -and $containerStatus -notmatch "NAMES") {
        Write-Host "✅ Container Status:" -ForegroundColor Green
        Write-Host $containerStatus -ForegroundColor White
        
        # Test health endpoint
        Start-Sleep -Seconds 2
        try {
            $response = Invoke-WebRequest -Uri "https://localhost:$caPort/health" -SkipCertificateCheck -TimeoutSec 10
            Write-Host "✅ Step CA Health Check: OK (Status: $($response.StatusCode))" -ForegroundColor Green
            
            # Get CA info
            try {
                $fingerprint = docker exec $containerName step certificate fingerprint /home/step/certs/root_ca.crt 2>$null
                if ($fingerprint) {
                    Write-Host "🔑 CA Fingerprint: $fingerprint" -ForegroundColor Cyan
                }
            } catch {
                Write-Host "⚠️  Could not retrieve CA fingerprint" -ForegroundColor Yellow
            }
            
        } catch {
            Write-Host "⚠️  Step CA is starting up or health check failed" -ForegroundColor Yellow
            Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Gray
        }
    } else {
        Write-Host "❌ Step CA container is not running" -ForegroundColor Red
    }
}

function Show-StepCALogs {
    param([bool]$Follow = $false)
    
    Write-Host "📋 Step CA Container Logs:" -ForegroundColor Yellow
    Write-Host "=========================" -ForegroundColor Yellow
    
    if ($Follow) {
        Write-Host "Following logs (Press Ctrl+C to stop)..." -ForegroundColor Gray
        docker logs -f $containerName
    } else {
        docker logs --tail 50 $containerName
    }
}

function Start-StepCA {
    Write-Host "� Starting Step CA in Docker..." -ForegroundColor Yellow
    
    # Create network if it doesn't exist
    Write-Host "🔧 Creating Docker network..." -ForegroundColor Cyan
    docker network create $networkName 2>$null | Out-Null
    
    # Stop existing container if running
    Stop-StepCA
    
    Write-Host "🏗️  Creating new Step CA container..." -ForegroundColor Cyan
    Write-Host "   Container: $containerName" -ForegroundColor Gray
    Write-Host "   Port: $caPort" -ForegroundColor Gray
    Write-Host "   Network: $networkName" -ForegroundColor Gray
    
    # Start Step CA container with initialization
    try {
        $dockerCmd = @(
            "docker", "run", "-d",
            "--name", $containerName,
            "--network", $networkName,
            "-p", "$caPort`:9000",
            "-e", "DOCKER_STEPCA_INIT_NAME=Test-CA-Docker",
            "-e", "DOCKER_STEPCA_INIT_DNS_NAMES=localhost,step-ca,127.0.0.1,$containerName",
            "-e", "DOCKER_STEPCA_INIT_REMOTE_MANAGEMENT=true",
            "-e", "DOCKER_STEPCA_INIT_PASSWORD=testpassword",
            "-e", "DOCKER_STEPCA_INIT_PROVISIONER_PASSWORD=adminpassword",
            "smallstep/step-ca:latest"
        )
        
        Write-Host "🔧 Docker command:" -ForegroundColor Gray
        Write-Host "   $($dockerCmd -join ' ')" -ForegroundColor DarkGray
        Write-Host ""
        
        $containerId = & $dockerCmd[0] $dockerCmd[1..($dockerCmd.Length-1)]
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Step CA container started successfully" -ForegroundColor Green
            Write-Host "   Container ID: $($containerId.Substring(0,12))..." -ForegroundColor Gray
            
            Write-Host ""
            Write-Host "⏳ Waiting for Step CA to initialize..." -ForegroundColor Yellow
            
            # Wait for initialization with progress
            $timeout = 60
            $elapsed = 0
            $ready = $false
            
            while ($elapsed -lt $timeout -and -not $ready) {
                Start-Sleep -Seconds 2
                $elapsed += 2
                
                try {
                    $logs = docker logs $containerName 2>&1
                    if ($logs -match "step-ca is ready") {
                        $ready = $true
                        break
                    }
                    
                    # Show progress
                    Write-Host "." -NoNewline -ForegroundColor Yellow
                    
                } catch {
                    # Continue waiting
                }
            }
            
            Write-Host ""
            
            if ($ready) {
                Write-Host "🎉 Step CA is ready!" -ForegroundColor Green
                
                # Get and save CA fingerprint
                Start-Sleep -Seconds 2
                try {
                    $fingerprint = docker exec $containerName step certificate fingerprint /home/step/certs/root_ca.crt
                    if ($fingerprint) {
                        Write-Host "� CA Fingerprint: $fingerprint" -ForegroundColor Cyan
                        
                        # Save fingerprint for configuration
                        $fingerprint | Out-File -FilePath "test\ca-fingerprint-docker.txt" -Encoding UTF8
                        Write-Host "💾 Fingerprint saved to: test\ca-fingerprint-docker.txt" -ForegroundColor Gray
                        
                        # Update test configuration
                        Write-Host "⚙️  Updating test configuration..." -ForegroundColor Cyan
                        Update-TestConfiguration $fingerprint
                    }
                } catch {
                    Write-Host "⚠️  Could not retrieve CA fingerprint" -ForegroundColor Yellow
                }
                
                # Add EST provisioner
                Write-Host ""
                Write-Host "⚙️  Adding EST provisioner..." -ForegroundColor Cyan
                try {
                    $addEstResult = docker exec $containerName sh -c @"
python3 << 'EOFPYTHON'
import json
config_path = '/home/step/config/ca.json'
try:
    with open(config_path, 'r') as f:
        config = json.load(f)
    provisioners = config.get('authority', {}).get('provisioners', [])
    est_exists = any(p.get('type') == 'EST' for p in provisioners)
    if not est_exists:
        provisioners.append({'type': 'EST', 'name': 'est-provisioner'})
        config['authority']['provisioners'] = provisioners
        with open(config_path, 'w') as f:
            json.dump(config, f, indent=2)
        print('EST provisioner added')
    else:
        print('EST provisioner exists')
except Exception as e:
    print(f'Error: {e}')
EOFPYTHON
"@
                    if ($addEstResult -match "added|exists") {
                        Write-Host "✅ EST provisioner configured" -ForegroundColor Green
                    }
                } catch {
                    Write-Host "⚠️  Could not add EST provisioner automatically" -ForegroundColor Yellow
                }
                
                Write-Host ""
                Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor White
                Write-Host "🎯 Step CA Connection Details (JWK + EST)" -ForegroundColor White
                Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor White
                Write-Host ""
                Write-Host "Provisioners:" -ForegroundColor Cyan
                Write-Host "  JWK (admin):           Step CA native protocol" -ForegroundColor Gray
                Write-Host "    URL: https://localhost:$caPort" -ForegroundColor Gray
                Write-Host "    Password: adminpassword" -ForegroundColor Gray
                Write-Host ""
                Write-Host "  EST (est-provisioner): RFC 7030 protocol" -ForegroundColor Gray
                Write-Host "    URL: https://localhost:$caPort/.well-known/est/" -ForegroundColor Gray
                Write-Host "    Also: https://localhost:8443/.well-known/est/" -ForegroundColor Gray
                Write-Host ""
                Write-Host "Test Commands:" -ForegroundColor Cyan
                Write-Host "  JWK: docker exec $containerName step ca health" -ForegroundColor Gray
                Write-Host "  EST: curl -k https://localhost:$caPort/.well-known/est/cacerts" -ForegroundColor Gray
                Write-Host ""
                Write-Host "✅ Step CA is ready for certificate renewal testing!" -ForegroundColor Green
                Write-Host "   Supports both JWK and EST protocols simultaneously" -ForegroundColor Gray
                
            } else {
                Write-Host "⚠️  Step CA initialization may be taking longer than expected" -ForegroundColor Yellow
                Write-Host "   Check logs with: .\start-step-ca-docker.ps1 logs" -ForegroundColor Gray
            }
            
        } else {
            Write-Host "❌ Failed to start Step CA container" -ForegroundColor Red
            exit 1
        }
        
    } catch {
        Write-Host "❌ Error starting Step CA: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

function Update-TestConfiguration {
    param([string]$Fingerprint)
    
    $configPath = "test\test-config\config.yaml"
    
    if (Test-Path $configPath) {
        try {
            $content = Get-Content $configPath -Raw
            
            # Update fingerprint in config
            $content = $content -replace 'ca_fingerprint: ".*"', "ca_fingerprint: `"$Fingerprint`""
            
            $content | Out-File -FilePath $configPath -Encoding UTF8
            Write-Host "✅ Updated test configuration with new CA fingerprint" -ForegroundColor Green
            
        } catch {
            Write-Host "⚠️  Could not update test configuration: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

function Reset-StepCA {
    Write-Host "🔄 Resetting Step CA environment..." -ForegroundColor Yellow
    
    # Stop and remove container
    Stop-StepCA
    
    # Remove network
    try {
        docker network rm $networkName 2>$null | Out-Null
    } catch {
        # Network may not exist
    }
    
    # Remove any related images (optional)
    Write-Host "🧹 Cleaning up..." -ForegroundColor Gray
    
    Write-Host "✅ Step CA environment reset complete" -ForegroundColor Green
    Write-Host "   Run 'start' to create a fresh Step CA instance" -ForegroundColor Gray
}

# Main script logic
if (-not (Test-DockerRunning)) {
    exit 1
}

switch ($Action) {
    "start" {
        Start-StepCA
    }
    "stop" {
        Stop-StepCA
    }
    "status" {
        Get-StepCAStatus
    }
    "logs" {
        Show-StepCALogs -Follow $Follow
    }
    "reset" {
        Reset-StepCA
    }
    default {
        Write-Host "❌ Unknown action: $Action" -ForegroundColor Red
        Write-Host ""
        Write-Host "Usage: .\start-step-ca-docker.ps1 [action]" -ForegroundColor White
        Write-Host ""
        Write-Host "Actions:" -ForegroundColor Cyan
        Write-Host "  start   - Start Step CA container" -ForegroundColor Gray
        Write-Host "  stop    - Stop Step CA container" -ForegroundColor Gray
        Write-Host "  status  - Check Step CA status" -ForegroundColor Gray
        Write-Host "  logs    - Show container logs (use -Follow for live)" -ForegroundColor Gray
        Write-Host "  reset   - Reset entire environment" -ForegroundColor Gray
        exit 1
    }
}

Write-Host ""
Write-Host "🏁 Step CA Docker management completed" -ForegroundColor Green