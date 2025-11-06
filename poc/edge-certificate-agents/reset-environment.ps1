#!/usr/bin/env pwsh
################################################################################
# ECA PoC - Environment Reset Helper Script (PowerShell)
################################################################################
#
# Purpose: Intelligently detect initialization state and assist with cleanup
#          and re-initialization of the ECA PoC environment.
#
# Usage:
#   pwsh ./reset-environment.ps1 [OPTIONS]
#
# Parameters:
#   -Force         Skip confirmation prompts (use with caution)
#   -VolumesOnly   Only remove volumes, keep containers stopped
#   -Help          Show this help message
#
################################################################################

#Requires -Version 7.0

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$VolumesOnly,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

################################################################################
# Helper Functions
################################################################################

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] " -ForegroundColor Blue -NoNewline
    Write-Host $Message
}

function Write-Success {
    param([string]$Message)
    Write-Host "[✓] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "[✗] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Write-Section {
    param([string]$Message)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Usage {
    @"
ECA PoC - Environment Reset Helper Script

Usage: pwsh ./reset-environment.ps1 [OPTIONS]

Parameters:
  -Force         Skip confirmation prompts (use with caution)
  -VolumesOnly   Only remove volumes, keep containers stopped
  -Help          Show this help message

Examples:
  pwsh ./reset-environment.ps1                    # Interactive reset with prompts
  pwsh ./reset-environment.ps1 -Force             # Force reset without prompts
  pwsh ./reset-environment.ps1 -VolumesOnly       # Remove volumes only

"@
}

################################################################################
# Environment Detection
################################################################################

function Test-DockerAvailable {
    if (-not (Get-Command -Name docker -ErrorAction SilentlyContinue)) {
        Write-ErrorMessage "Docker not found. Please install Docker first."
        return $false
    }

    try {
        docker info 2>$null | Out-Null
        return $true
    }
    catch {
        Write-ErrorMessage "Docker daemon is not running. Please start Docker."
        return $false
    }
}

function Test-ContainersRunning {
    try {
        $containers = docker compose ps -q 2>$null
        if ($containers) {
            return $true
        }
    }
    catch {
        # Continue
    }
    return $false
}

function Get-ExistingVolumes {
    $volumeNames = @(
        "pki-data"
        "openxpki-config-data"
        "openxpki-db"
        "server-certs"
        "client-certs"
        "challenge"
        "posh-acme-state"
        "openxpki-socket"
        "openxpki-client-socket"
        "openxpki-db-socket"
        "openxpki-log"
        "openxpki-log-ui"
        "openxpki-download"
        "loki-data"
        "grafana-data"
        "fluentd-buffer"
        "crl-data"
    )

    $existingVolumes = @()
    foreach ($vol in $volumeNames) {
        try {
            docker volume inspect $vol 2>$null | Out-Null
            $existingVolumes += $vol
        }
        catch {
            # Volume doesn't exist
        }
    }

    return $existingVolumes
}

function Get-InitializationStatus {
    $status = "UNINITIALIZED"
    $details = ""

    # Check if volumes exist
    $volumes = Get-ExistingVolumes

    if ($volumes.Count -gt 0) {
        $status = "PARTIAL"

        # Check if critical volumes exist
        if ($volumes -contains "pki-data") {
            # Check if pki-data is properly initialized
            try {
                $result = docker run --rm -v pki-data:/check:ro alpine test -f /check/config/ca.json 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $status = "INITIALIZED"
                    $details = "PKI volume appears properly initialized"
                }
                else {
                    $status = "INCOMPLETE"
                    $details = "PKI volume exists but appears incomplete"
                }
            }
            catch {
                $status = "INCOMPLETE"
                $details = "PKI volume exists but appears incomplete"
            }
        }
        else {
            $details = "Some volumes exist but critical PKI volume is missing"
        }
    }
    else {
        $details = "No volumes found"
    }

    return @{
        Status  = $status
        Details = $details
    }
}

################################################################################
# Display Functions
################################################################################

function Show-EnvironmentStatus {
    Write-Section "Current Environment Status"

    # Docker availability
    if (Test-DockerAvailable) {
        Write-Success "Docker is available and running"
    }
    else {
        Write-ErrorMessage "Docker is not available"
        return $false
    }

    # Container status
    Write-Host ""
    Write-Info "Container Status:"
    if (Test-ContainersRunning) {
        Write-Warn "Containers are currently running"
        $containers = docker compose ps 2>$null
        if ($containers) {
            $containers | Select-Object -Skip 1 | ForEach-Object {
                Write-Host "  • $_"
            }
        }
    }
    else {
        Write-Info "No containers running"
    }

    # Volume status
    Write-Host ""
    Write-Info "Volume Status:"
    $volumes = Get-ExistingVolumes

    if ($volumes.Count -gt 0) {
        Write-Warn "Found existing volumes:"
        foreach ($vol in $volumes) {
            Write-Host "  • $vol"
        }
    }
    else {
        Write-Info "No volumes found"
    }

    # Initialization status
    Write-Host ""
    $initStatus = Get-InitializationStatus

    switch ($initStatus.Status) {
        "UNINITIALIZED" {
            Write-Info "Environment Status: $($initStatus.Status)"
            Write-Info "Details: $($initStatus.Details)"
        }
        { $_ -in @("PARTIAL", "INCOMPLETE") } {
            Write-Warn "Environment Status: $($initStatus.Status)"
            Write-Warn "Details: $($initStatus.Details)"
            Write-Warn "This may cause startup issues - re-initialization recommended"
        }
        "INITIALIZED" {
            Write-Success "Environment Status: $($initStatus.Status)"
            Write-Info "Details: $($initStatus.Details)"
        }
    }

    return $true
}

################################################################################
# Cleanup Functions
################################################################################

function Stop-AllContainers {
    Write-Info "Stopping all containers..."
    try {
        docker compose down 2>$null | Out-Null
        Write-Success "Containers stopped successfully"
        return $true
    }
    catch {
        Write-ErrorMessage "Failed to stop containers"
        return $false
    }
}

function Remove-AllVolumes {
    Write-Info "Removing volumes..."

    $volumes = Get-ExistingVolumes

    if ($volumes.Count -gt 0) {
        $removed = 0
        $failed = 0

        foreach ($vol in $volumes) {
            try {
                docker volume rm $vol 2>$null | Out-Null
                Write-Success "Removed volume: $vol"
                $removed++
            }
            catch {
                Write-ErrorMessage "Failed to remove volume: $vol"
                $failed++
            }
        }

        Write-Host ""
        Write-Info "Summary: Removed $removed volume(s), Failed $failed"

        if ($failed -gt 0) {
            return $false
        }
    }
    else {
        Write-Info "No volumes to remove"
    }

    return $true
}

function Start-Initialization {
    Write-Section "Running Initialization"

    if (Test-Path "./integration-test.ps1") {
        Write-Info "Starting environment initialization..."
        Write-Host ""

        # Set default password to avoid prompts
        if (-not $env:ECA_CA_PASSWORD) {
            $env:ECA_CA_PASSWORD = "eca-poc-default-password"
        }

        try {
            & ./integration-test.ps1 -InitOnly
            if ($LASTEXITCODE -eq 0) {
                Write-Host ""
                Write-Success "Initialization completed successfully!"
                return $true
            }
            else {
                Write-Host ""
                Write-ErrorMessage "Initialization failed"
                return $false
            }
        }
        catch {
            Write-Host ""
            Write-ErrorMessage "Initialization failed: $_"
            return $false
        }
    }
    else {
        Write-ErrorMessage "integration-test.ps1 not found in current directory"
        return $false
    }
}

################################################################################
# Main Logic
################################################################################

function Main {
    # Show help if requested
    if ($Help) {
        Show-Usage
        exit 0
    }

    Write-Section "ECA PoC - Environment Reset Helper"

    # Check Docker availability
    if (-not (Test-DockerAvailable)) {
        exit 1
    }

    # Display current status
    if (-not (Show-EnvironmentStatus)) {
        exit 1
    }

    # Determine what needs to be done
    $initStatus = Get-InitializationStatus

    Write-Host ""

    # If already initialized and no issues, confirm if user wants to reset
    if ($initStatus.Status -eq "INITIALIZED" -and -not $Force) {
        Write-Section "Reset Confirmation"
        Write-Warn "The environment appears to be properly initialized."
        Write-Host ""
        $confirmation = Read-Host "Do you want to reset and re-initialize everything? (yes/NO)"

        if ($confirmation -ne "yes") {
            Write-Info "Reset cancelled by user"
            Write-Host ""
            Write-Host "To start the stack without resetting, run: " -NoNewline
            Write-Host "docker compose up -d" -ForegroundColor Cyan
            exit 0
        }
    }

    # Confirm cleanup for partial/incomplete states
    if ($initStatus.Status -in @("PARTIAL", "INCOMPLETE")) {
        if (-not $Force) {
            Write-Section "Cleanup Recommendation"
            Write-Warn "The environment is in an inconsistent state."
            Write-Info "Re-initialization is recommended to ensure proper operation."
            Write-Host ""
            $confirmation = Read-Host "Proceed with cleanup and re-initialization? (yes/NO)"

            if ($confirmation -ne "yes") {
                Write-Info "Cleanup cancelled by user"
                exit 0
            }
        }
    }

    # Perform cleanup
    Write-Section "Cleanup Process"

    # Stop containers
    if (Test-ContainersRunning) {
        if (-not (Stop-AllContainers)) {
            Write-ErrorMessage "Failed to stop containers. Cannot proceed."
            exit 1
        }
    }
    else {
        Write-Info "No running containers to stop"
    }

    # Remove volumes
    if (-not (Remove-AllVolumes)) {
        Write-ErrorMessage "Failed to remove all volumes"
        Write-Warn "You may need to manually remove some volumes with: docker volume rm <volume-name>"
        exit 1
    }

    Write-Success "Cleanup completed successfully"

    # Run initialization unless volumes-only mode
    if (-not $VolumesOnly) {
        if (-not (Start-Initialization)) {
            Write-ErrorMessage "Failed to initialize environment"
            exit 1
        }

        Write-Section "Next Steps"
        Write-Host ""
        Write-Success "Environment has been reset and initialized!"
        Write-Host ""
        Write-Host "You can now:"
        Write-Host "  1. Start all services:        " -NoNewline
        Write-Host "docker compose up -d" -ForegroundColor Green
        Write-Host "  2. Run integration tests:     " -NoNewline
        Write-Host "./integration-test.ps1" -ForegroundColor Green
        Write-Host "  3. View service logs:         " -NoNewline
        Write-Host "docker compose logs -f" -ForegroundColor Green
        Write-Host ""
    }
    else {
        Write-Section "Volumes Removed"
        Write-Host ""
        Write-Info "Volumes have been removed. Containers are stopped."
        Write-Host ""
        Write-Host "To re-initialize, run: " -NoNewline
        Write-Host "./integration-test.ps1 -InitOnly" -ForegroundColor Cyan
        Write-Host ""
    }
}

# Run main function
try {
    Main
}
catch {
    Write-ErrorMessage "Script failed: $_"
    exit 1
}
