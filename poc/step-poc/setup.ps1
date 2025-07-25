# setup.ps1 - Windows PowerShell Setup Script for Certificate Management PoC

param(
    [switch]$Help,
    [switch]$SkipHostsFile
)

if ($Help) {
    Write-Host @"
Certificate Management PoC - Setup Script (Windows)
===================================================

This script sets up the complete Certificate Management PoC environment on Windows.

Usage:
    .\setup.ps1 [-SkipHostsFile] [-Help]

Parameters:
    -SkipHostsFile    Skip hosts file modification (if already configured)
    -Help            Show this help message

Requirements:
    - PowerShell 5.1 or later
    - Docker Desktop for Windows
    - Administrative privileges (script will prompt if needed)
    - Minimum 2GB free disk space
    - Minimum 4GB RAM

The script will:
    1. Check system requirements and Docker installation
    2. Validate Docker Desktop is running
    3. Configure hosts file entries (requires admin privileges)
    4. Create required project directories
    5. Fix Docker volume permissions
    6. Start all infrastructure services
    7. Verify service health and accessibility
    8. Provide access information and next steps

"@
    exit 0
}

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to write colored output
function Write-Status {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-Status "==================================================================" -Color Blue
    Write-Status $Title -Color Blue
    Write-Status "==================================================================" -Color Blue
    Write-Host ""
}

# Function to check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Write-Header "Certificate Management PoC - Setup Script (Windows)"

Write-Status "Step 1: Checking Prerequisites..." -Color Yellow

# Check PowerShell version
$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -lt 5) {
    Write-Status "ERROR: PowerShell 5.1 or later is required. Current version: $psVersion" -Color Red
    Write-Status "Please upgrade PowerShell from: https://github.com/PowerShell/PowerShell" -Color Yellow
    exit 1
}

Write-Status "PowerShell Version: $psVersion" -Color Green

# Check if Docker is installed
try {
    $dockerVersion = docker --version
    Write-Status "Docker found: $dockerVersion" -Color Green
} catch {
    Write-Status "ERROR: Docker is not installed or not in PATH" -Color Red
    Write-Status "Please install Docker Desktop for Windows from: https://docker.com/products/docker-desktop" -Color Yellow
    exit 1
}

# Check if Docker Compose is available
try {
    $composeVersion = docker compose version --short 2>$null
    if (-not $composeVersion) {
        $composeVersion = docker-compose version --short 2>$null
        if ($composeVersion) {
            Write-Status "WARNING: Using legacy docker-compose command. Consider upgrading." -Color Yellow
            $dockerComposeCmd = "docker-compose"
        } else {
            throw "Docker Compose not found"
        }
    } else {
        $dockerComposeCmd = "docker compose"
    }
    Write-Status "Docker Compose Version: $composeVersion" -Color Green
} catch {
    Write-Status "ERROR: Docker Compose is not available" -Color Red
    Write-Status "Please install Docker Compose from: https://docs.docker.com/compose/install/" -Color Yellow
    exit 1
}

# Check if Docker is running
try {
    docker info | Out-Null
    Write-Status "Docker is running" -Color Green
} catch {
    Write-Status "ERROR: Docker is not running" -Color Red
    Write-Status "Please start Docker Desktop and try again." -Color Yellow
    exit 1
}

Write-Status "Step 2: Checking System Requirements..." -Color Yellow

# Check available disk space (need at least 2GB)
$drive = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq (Get-Location).Drive.Name }
$availableGB = [math]::Round($drive.FreeSpace / 1GB, 2)

if ($availableGB -lt 2) {
    Write-Status "ERROR: Insufficient disk space. Required: 2GB, Available: ${availableGB}GB" -Color Red
    exit 1
}

Write-Status "Available disk space: ${availableGB}GB" -Color Green

# Check available memory
$totalMemoryGB = [math]::Round((Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
if ($totalMemoryGB -lt 4) {
    Write-Status "WARNING: Less than 4GB RAM available (${totalMemoryGB}GB). Performance may be affected." -Color Yellow
} else {
    Write-Status "Available memory: ${totalMemoryGB}GB" -Color Green
}

if (-not $SkipHostsFile) {
    Write-Status "Step 3: Configuring Hosts File..." -Color Yellow

    # Check if running as administrator for hosts file modification
    if (-not (Test-Administrator)) {
        Write-Status "Administrative privileges required for hosts file modification." -Color Yellow
        Write-Status "Restarting script as administrator..." -Color Yellow
        
        $scriptPath = $MyInvocation.MyCommand.Path
        $arguments = "-File `"$scriptPath`""
        if ($SkipHostsFile) { $arguments += " -SkipHostsFile" }
        
        Start-Process PowerShell -Verb RunAs -ArgumentList $arguments
        exit 0
    }

    $hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
    $requiredEntries = @(
        "ca.localtest.me",
        "device.localtest.me",
        "app.localtest.me",
        "mqtt.localtest.me"
    )

    # Check existing entries
    $hostsContent = Get-Content $hostsFile -ErrorAction SilentlyContinue
    $missingEntries = @()
    
    foreach ($entry in $requiredEntries) {
        if (-not ($hostsContent | Select-String -Pattern $entry -Quiet)) {
            $missingEntries += $entry
        }
    }

    if ($missingEntries.Count -gt 0) {
        Write-Status "Adding missing hosts file entries..." -Color Yellow
        
        # Create backup
        $backupFile = "${hostsFile}.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $hostsFile $backupFile
        Write-Status "Backup created: $backupFile" -Color Blue
        
        # Add entries
        Add-Content $hostsFile ""
        Add-Content $hostsFile "# Certificate Management PoC - Local Domain Resolution"
        foreach ($entry in $missingEntries) {
            Add-Content $hostsFile "127.0.0.1 $entry"
            Write-Status "Added: 127.0.0.1 $entry" -Color Green
        }
    } else {
        Write-Status "All required hosts file entries are present." -Color Green
    }

    # Verify hosts file entries
    Write-Status "Verifying domain resolution..." -Color Yellow
    foreach ($entry in $requiredEntries) {
        try {
            $result = Test-NetConnection -ComputerName $entry -Port 80 -InformationLevel Quiet -WarningAction SilentlyContinue
            if ($result) {
                Write-Status "✓ $entry resolves correctly" -Color Green
            } else {
                # Test with ping as fallback
                $pingResult = Test-Connection -ComputerName $entry -Count 1 -Quiet -ErrorAction SilentlyContinue
                if ($pingResult) {
                    Write-Status "✓ $entry resolves correctly" -Color Green
                } else {
                    Write-Status "✗ $entry does not resolve" -Color Red
                }
            }
        } catch {
            Write-Status "? $entry resolution test inconclusive" -Color Yellow
        }
    }
} else {
    Write-Status "Step 3: Skipping hosts file configuration (as requested)" -Color Yellow
}

Write-Status "Step 4: Preparing Project Environment..." -Color Yellow

# Check if we're in the correct directory
if (-not (Test-Path "docker-compose.yml")) {
    Write-Status "ERROR: docker-compose.yml not found in current directory." -Color Red
    Write-Status "Please run this script from the project root directory." -Color Yellow
    exit 1
}

# Create required directories
Write-Status "Creating required directories..." -Color Blue
$directories = @(
    "logs\step-ca",
    "logs\mosquitto", 
    "logs\loki",
    "logs\grafana",
    "logs\certbot-device",
    "logs\certbot-app",
    "logs\certbot-mqtt",
    "config\grafana\dev"
)

foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

Write-Status "Project directories created." -Color Green

Write-Status "Step 5: Fixing Docker Volume Permissions..." -Color Yellow

# Run the permission fix script
if (Test-Path "scripts\fix-permissions.ps1") {
    Write-Status "Running permission fix script..." -Color Blue
    & ".\scripts\fix-permissions.ps1"
} else {
    Write-Status "ERROR: Permission fix script not found at scripts\fix-permissions.ps1" -Color Red
    exit 1
}

Write-Status "Step 6: Starting Infrastructure Services..." -Color Yellow

# Start services
Write-Status "Starting all services with $dockerComposeCmd..." -Color Blue
if ($dockerComposeCmd -eq "docker compose") {
    docker compose up -d
} else {
    docker-compose up -d
}

Write-Status "Waiting for services to initialize (60 seconds)..." -Color Yellow
Start-Sleep -Seconds 60

Write-Status "Step 7: Verifying Service Health..." -Color Yellow

# Check service status
Write-Status "Service Status:" -Color Blue
if ($dockerComposeCmd -eq "docker compose") {
    docker compose ps
} else {
    docker-compose ps
}

# Test individual services
Write-Status "Testing service endpoints..." -Color Yellow

# Test step-ca
try {
    $result = docker exec step-ca curl -k -s https://localhost:9000/health 2>$null
    if ($result -eq '{"status":"ok"}') {
        Write-Status "✓ step-ca health endpoint responding" -Color Green
    } else {
        Write-Status "✗ step-ca health endpoint not responding correctly" -Color Red
    }
} catch {
    Write-Status "✗ step-ca health endpoint not responding" -Color Red
}

# Test Grafana
try {
    $response = Invoke-WebRequest -Uri "http://localhost:3000/api/health" -UseBasicParsing -TimeoutSec 10
    if ($response.StatusCode -eq 200) {
        Write-Status "✓ Grafana accessible" -Color Green
    } else {
        Write-Status "✗ Grafana not accessible" -Color Red
    }
} catch {
    Write-Status "✗ Grafana not accessible" -Color Red
}

# Test Loki
try {
    $result = docker exec loki wget -qO- http://localhost:3100/ready 2>$null
    if ($result -eq "ready") {
        Write-Status "✓ Loki ready" -Color Green
    } else {
        Write-Status "✗ Loki not ready" -Color Red
    }
} catch {
    Write-Status "✗ Loki not ready" -Color Red
}

Write-Header "Setup Complete!"

Write-Status "Certificate Management PoC is now running!" -Color Green
Write-Host ""
Write-Status "Access Points:" -Color Blue
Write-Status "• Grafana Dashboard: http://localhost:3000 (admin/admin)" -Color Blue
Write-Status "• step-ca Health: https://ca.localtest.me:9000/health" -Color Blue
Write-Status "• Loki API: http://localhost:3100" -Color Blue
Write-Host ""
Write-Status "Useful Commands:" -Color Blue
Write-Status "• Check service status: $dockerComposeCmd ps" -Color Blue
Write-Status "• View logs: $dockerComposeCmd logs -f <service-name>" -Color Blue
Write-Status "• Stop services: $dockerComposeCmd down" -Color Blue
Write-Status "• Complete reset: $dockerComposeCmd down -v" -Color Blue
Write-Host ""
Write-Status "Next Steps:" -Color Yellow
Write-Status "1. Open Grafana at http://localhost:3000" -Color Yellow
Write-Status "2. Explore the Loki datasource" -Color Yellow
Write-Status "3. Monitor certificate lifecycle events" -Color Yellow
Write-Status "4. Check the documentation in docs\ directory" -Color Yellow
Write-Host ""

# Check for any failed services
try {
    if ($dockerComposeCmd -eq "docker compose") {
        $failedServices = docker compose ps --filter "status=exited" --format "{{.Service}}" 2>$null
    } else {
        $failedServices = docker-compose ps --filter "status=exited" --format "{{.Service}}" 2>$null
    }
    
    if ($failedServices) {
        Write-Status "WARNING: Some services failed to start:" -Color Red
        Write-Status $failedServices -Color Red
        Write-Status "Check logs with: $dockerComposeCmd logs <service-name>" -Color Yellow
    }
} catch {
    # Ignore errors in checking failed services
}

Write-Status "Setup script completed successfully!" -Color Green

Write-Host ""
Write-Status "Press any key to continue..." -Color Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")