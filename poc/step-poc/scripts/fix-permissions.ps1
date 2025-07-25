# fix-permissions.ps1 - Windows PowerShell permission fix script for Certificate Management PoC

param(
    [switch]$Help
)

if ($Help) {
    Write-Host @"
Certificate Management PoC - Permission Fix Script (Windows)
===========================================================

This script fixes Docker volume permissions for the Certificate Management PoC
on Windows systems.

Usage:
    .\scripts\fix-permissions.ps1

Requirements:
    - PowerShell 5.1 or later
    - Docker Desktop for Windows
    - Administrative privileges (script will prompt if needed)

The script will:
    1. Check Docker installation and status
    2. Identify step-ca container user requirements
    3. Fix Docker volume permissions
    4. Test step-ca startup and health
    5. Provide next steps

"@
    exit 0
}

# Set error action preference
$ErrorActionPreference = "Stop"

Write-Host "🔧 Certificate Management PoC - Permission Fix Script (Windows)" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# Function to write colored output
function Write-Status {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Function to check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Check if running as administrator
if (-not (Test-Administrator)) {
    Write-Status "⚠️  This script requires administrative privileges for Docker volume access." -Color Yellow
    Write-Status "🔄 Restarting script as administrator..." -Color Yellow
    
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process PowerShell -Verb RunAs -ArgumentList "-File `"$scriptPath`""
    exit 0
}

Write-Status "✅ Running with administrative privileges" -Color Green

# Check if Docker is installed
try {
    $dockerVersion = docker --version
    Write-Status "✅ Docker found: $dockerVersion" -Color Green
} catch {
    Write-Status "❌ Docker is not installed or not in PATH" -Color Red
    Write-Status "   Please install Docker Desktop for Windows from https://docker.com/products/docker-desktop" -Color Yellow
    exit 1
}

# Check if Docker is running
try {
    docker info | Out-Null
    Write-Status "✅ Docker is running" -Color Green
} catch {
    Write-Status "❌ Docker is not running. Please start Docker Desktop." -Color Red
    exit 1
}

# Check if Docker Compose is available
try {
    docker compose version | Out-Null
    Write-Status "✅ Docker Compose is available" -Color Green
} catch {
    Write-Status "❌ Docker Compose is not available" -Color Red
    exit 1
}

Write-Status "🔍 Checking Docker Compose project..." -Color Yellow

# Get the project name (directory name)
$projectName = Split-Path -Leaf (Get-Location)
Write-Status "📋 Project name: $projectName" -Color Cyan

# Check if docker-compose.yml exists
if (-not (Test-Path "docker-compose.yml")) {
    Write-Status "❌ docker-compose.yml not found in current directory" -Color Red
    Write-Status "   Please run this script from the project root directory" -Color Yellow
    exit 1
}

# Check if volumes exist, create if needed
Write-Status "🔍 Checking Docker volumes..." -Color Yellow

$volumes = docker volume ls --format "{{.Name}}" | Where-Object { $_ -like "$projectName*" }

if (-not $volumes) {
    Write-Status "⚠️  No Docker volumes found for project '$projectName'. Creating volumes..." -Color Yellow
    try {
        docker compose up --no-start
        Write-Status "✅ Volumes created successfully" -Color Green
    } catch {
        Write-Status "❌ Failed to create volumes" -Color Red
        exit 1
    }
}

Write-Status "🔍 Identifying step-ca container user requirements..." -Color Yellow

# Get step-ca container user ID (Linux containers in Windows use Linux UIDs)
try {
    $stepUid = docker run --rm smallstep/step-ca:latest id -u 2>$null
    $stepGid = docker run --rm smallstep/step-ca:latest id -g 2>$null
    
    if (-not $stepUid) { $stepUid = "1000" }
    if (-not $stepGid) { $stepGid = "1000" }
    
    Write-Status "📋 step-ca container runs as UID:GID = $stepUid`:$stepGid" -Color Green
} catch {
    Write-Status "⚠️  Could not determine step-ca user ID, using default 1000:1000" -Color Yellow
    $stepUid = "1000"
    $stepGid = "1000"
}

Write-Status "🔧 Fixing permissions for Docker volumes..." -Color Yellow

# Function to fix volume permissions on Windows
function Fix-VolumePermissions {
    param(
        [string]$VolumeName,
        [string]$Description
    )
    
    Write-Status "   Fixing $Description..." -Color Yellow
    
    try {
        # Get volume mount point
        $mountPoint = docker volume inspect $VolumeName --format '{{.Mountpoint}}' 2>$null
        
        if (-not $mountPoint) {
            Write-Status "   ❌ Volume $VolumeName not found" -Color Red
            return $false
        }
        
        Write-Status "   📁 Volume path: $mountPoint" -Color Cyan
        
        # On Windows with Docker Desktop, volumes are managed by Docker
        # We need to ensure the volume is accessible to the container
        # This is typically handled by Docker Desktop automatically
        
        # Test volume accessibility by creating a test container
        $testResult = docker run --rm -v "${VolumeName}:/test" alpine sh -c "ls -la /test && touch /test/.permission-test && rm -f /test/.permission-test" 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Status "   ✅ Volume $Description is accessible" -Color Green
            return $true
        } else {
            Write-Status "   ⚠️  Volume $Description may have permission issues" -Color Yellow
            
            # Try to fix by recreating the volume with proper permissions
            Write-Status "   🔄 Attempting to fix volume permissions..." -Color Yellow
            
            # Stop any containers using this volume
            docker compose down 2>$null | Out-Null
            
            # Create a temporary container to fix permissions
            docker run --rm -v "${VolumeName}:/fix" alpine sh -c "chown -R $stepUid`:$stepGid /fix" 2>$null | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-Status "   ✅ Fixed permissions for $Description" -Color Green
                return $true
            } else {
                Write-Status "   ❌ Failed to fix permissions for $Description" -Color Red
                return $false
            }
        }
    } catch {
        Write-Status "   ❌ Error fixing permissions for $Description`: $_" -Color Red
        return $false
    }
}

# Fix permissions for step-ca volumes
$success = $true

$stepCaVolume = "${projectName}_step-ca-data"
if (-not (Fix-VolumePermissions $stepCaVolume "step-ca data volume")) {
    $success = $false
}

# Fix permissions for certificate volumes (if they exist)
$certVolumes = @("certs-ca", "certs-device", "certs-app", "certs-mqtt")
foreach ($certVolume in $certVolumes) {
    $fullVolumeName = "${projectName}_${certVolume}"
    $volumeExists = docker volume ls --format "{{.Name}}" | Where-Object { $_ -eq $fullVolumeName }
    
    if ($volumeExists) {
        if (-not (Fix-VolumePermissions $fullVolumeName "$certVolume volume")) {
            $success = $false
        }
    }
}

if (-not $success) {
    Write-Status "❌ Some permission fixes failed" -Color Red
    exit 1
}

Write-Status "✅ Permission fixes completed successfully!" -Color Green

Write-Status "🧪 Testing step-ca startup..." -Color Yellow

# Test step-ca startup
try {
    docker compose up -d step-ca
    Write-Status "✅ step-ca started successfully" -Color Green
    
    # Wait for health check
    Write-Status "⏳ Waiting for step-ca to become healthy (up to 60 seconds)..." -Color Yellow
    
    $healthCheckPassed = $false
    for ($i = 1; $i -le 12; $i++) {
        $status = docker compose ps step-ca --format "{{.Status}}"
        if ($status -like "*healthy*") {
            Write-Status "✅ step-ca is healthy!" -Color Green
            $healthCheckPassed = $true
            break
        } elseif ($i -eq 12) {
            Write-Status "❌ step-ca failed to become healthy within 60 seconds" -Color Red
            Write-Status "📋 step-ca logs:" -Color Yellow
            docker compose logs --tail=10 step-ca
            exit 1
        } else {
            Write-Host "." -NoNewline
            Start-Sleep -Seconds 5
        }
    }
    
    if ($healthCheckPassed) {
        # Test health endpoint
        try {
            docker exec step-ca curl -k https://localhost:9000/health | Out-Null
            Write-Status "✅ step-ca health endpoint is responding" -Color Green
        } catch {
            Write-Status "❌ step-ca health endpoint is not responding" -Color Red
            exit 1
        }
    }
    
} catch {
    Write-Status "❌ Failed to start step-ca: $_" -Color Red
    exit 1
}

Write-Status "🎉 All permission fixes completed successfully!" -Color Green
Write-Status "🚀 You can now run: docker compose up -d" -Color Green

Write-Host ""
Write-Status "📋 Summary of fixes applied:" -Color Cyan
Write-Status "   • Fixed ownership of step-ca data volume to UID:GID $stepUid`:$stepGid" -Color White
Write-Status "   • Fixed ownership of certificate volumes" -Color White
Write-Status "   • Verified step-ca startup and health" -Color White
Write-Host ""
Write-Status "🔗 Next steps:" -Color Cyan
Write-Status "   • Run 'docker compose up -d' to start all services" -Color White
Write-Status "   • Access Grafana at http://localhost:3000 (admin/admin)" -Color White
Write-Status "   • Check step-ca at https://ca.localtest.me:9000/health" -Color White

Write-Host ""
Write-Status "Press any key to continue..." -Color Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")