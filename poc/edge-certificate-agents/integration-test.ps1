#!/usr/bin/env pwsh
################################################################################
# ECA PoC - Comprehensive Integration Test Orchestration Script (PowerShell)
################################################################################
#
# Purpose: End-to-end automated testing and validation of the ECA PoC stack
#          This script provides a reproducible, automated way to:
#          - Initialize PKI infrastructure (step-ca root + ACME/EST intermediates)
#          - Configure OpenXPKI EST server with shared trust chain
#          - Spin up complete docker-compose stack
#          - Validate all endpoints (PKI, ACME, EST, CRL)
#          - Run integration tests
#          - Clean teardown
#
# Usage:
#   pwsh ./integration-test.ps1 [OPTIONS]
#
# Parameters:
#   -InitOnly         Only initialize volumes, don't start stack
#   -StartOnly        Only start stack (assumes volumes initialized)
#   -ValidateOnly     Only validate endpoints (assumes stack running)
#   -TestOnly         Only run tests (assumes stack running)
#   -NoCleanup        Don't tear down stack after tests
#   -SkipInit         Skip volume initialization if already done
#   -Quick            Quick mode: skip init if volumes exist
#   -Clean            Clean all volumes and restart from scratch
#
# Exit Codes:
#   0 - All tests passed
#   1 - Initialization failed
#   2 - Stack startup failed
#   3 - Validation failed
#   4 - Tests failed
#
################################################################################

#Requires -Version 7.0

[CmdletBinding()]
param(
    [switch]$InitOnly,
    [switch]$StartOnly,
    [switch]$ValidateOnly,
    [switch]$TestOnly,
    [switch]$NoCleanup,
    [switch]$SkipInit,
    [switch]$Quick,
    [switch]$Clean,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

################################################################################
# Configuration
################################################################################

$script:ScriptDir = $PSScriptRoot
$script:ProjectName = "eca-poc"
$script:LogDir = Join-Path $PSScriptRoot "logs"
$script:Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Timeout settings (seconds)
$script:PkiStartupTimeout = 60
$script:OpenxpkiStartupTimeout = 120
$script:ServiceReadyTimeout = 30
$script:EndpointTimeout = 10

# Services to validate
$script:CoreServices = @(
    "pki"
    "openxpki-db"
    "openxpki-server"
    "openxpki-client"
    "openxpki-web"
)

################################################################################
# Helper Functions
################################################################################

function Write-Section {
    param([string]$Message)

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

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

function Write-Step {
    param([string]$Message)
    Write-Host "[STEP] " -ForegroundColor Magenta -NoNewline
    Write-Host $Message
}

################################################################################
# Error Handling & Command Execution
################################################################################

function Initialize-Logging {
    if (-not (Test-Path $script:LogDir)) {
        New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
    }
    Write-Info "Log directory: $($script:LogDir)"
}

function Invoke-CommandWithLogging {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Description,
        [Parameter(Mandatory=$true)]
        [scriptblock]$Command
    )

    $logFileName = ($Description -replace '[^a-zA-Z0-9]', '_') + ".log"
    $logFile = Join-Path $script:LogDir "$($script:Timestamp)_$logFileName"

    Write-Host "⏳ " -NoNewline
    Write-Host $Description -NoNewline

    try {
        # Execute command and capture output
        $output = & $Command 2>&1
        $output | Out-File -FilePath $logFile -Encoding UTF8

        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
            throw "Command failed with exit code: $LASTEXITCODE"
        }

        Write-Host "`r✅ " -NoNewline
        Write-Host $Description
        return $true
    }
    catch {
        Write-Host "`r❌ " -NoNewline
        Write-Host $Description
        Write-Host ""
        Write-ErrorMessage "Command failed: $_"
        Write-ErrorMessage "📝 Full error log saved to:"
        Write-ErrorMessage "  $logFile"
        Write-Host ""
        Write-Host "▼▼▼ ERROR LOG (last 20 lines) ▼▼▼" -ForegroundColor Red
        if (Test-Path $logFile) {
            Get-Content $logFile -Tail 20 | ForEach-Object {
                Write-Host "  | " -ForegroundColor Red -NoNewline
                Write-Host $_
            }
        }
        Write-Host "▲▲▲ ERROR LOG ▲▲▲" -ForegroundColor Red
        Write-Host ""
        Write-ErrorMessage "📄 For full error details, see: $logFile"
        return $false
    }
}

function Test-Prerequisites {
    Write-Info "🔍 Checking prerequisites..."

    $failed = $false

    # Check for step CLI
    if (-not (Get-Command -Name step -ErrorAction SilentlyContinue)) {
        Write-ErrorMessage "🔐 step CLI not found!"
        Write-Host "   Install from: https://smallstep.com/docs/step-cli/installation"
        $failed = $true
    }
    else {
        Write-Info "  ✓ step CLI found"
    }

    # Check for docker
    if (-not (Get-Command -Name docker -ErrorAction SilentlyContinue)) {
        Write-ErrorMessage "🐳 Docker not found!"
        Write-Host "   Install from: https://docs.docker.com/get-docker/"
        $failed = $true
    }
    else {
        Write-Info "  ✓ Docker found"
    }

    # Check for docker compose
    try {
        docker compose version | Out-Null
        Write-Info "  ✓ Docker Compose found"
    }
    catch {
        Write-ErrorMessage "🐳 Docker Compose v2 not found!"
        Write-Host "   Ensure Docker Compose is installed and available"
        $failed = $true
    }

    if ($failed) {
        Write-ErrorMessage "❌ Prerequisite checks failed. Please install missing dependencies."
        return $false
    }

    Write-Success "✅ All prerequisites met"
    return $true
}

function Show-Usage {
    @"
ECA PoC - Comprehensive Integration Test Orchestration Script

Usage: pwsh ./integration-test.ps1 [OPTIONS]

Options:
  -InitOnly         Only initialize volumes, don't start stack
  -StartOnly        Only start stack (assumes volumes initialized)
  -ValidateOnly     Only validate endpoints (assumes stack running)
  -TestOnly         Only run tests (assumes stack running)
  -NoCleanup        Don't tear down stack after tests
  -SkipInit         Skip volume initialization if already done
  -Quick            Quick mode: skip init if volumes exist
  -Clean            Clean all volumes and restart from scratch
  -Help             Show this help message

Examples:
  pwsh ./integration-test.ps1                  # Full end-to-end test
  pwsh ./integration-test.ps1 -Quick           # Quick run (skip init if volumes exist)
  pwsh ./integration-test.ps1 -Clean           # Clean everything and start fresh
  pwsh ./integration-test.ps1 -ValidateOnly    # Only validate endpoints
  pwsh ./integration-test.ps1 -NoCleanup       # Keep stack running after tests
"@
}

################################################################################
# Volume Management
################################################################################

# Volume initialization constants
$script:VolumePki = "pki-data"
$script:VolumeOpenxpkiConfig = "openxpki-config-data"
$script:TempPkiDir = "/tmp/eca-pki-init"
$script:CaName = "ECA-PoC-CA"
$script:CaDns = "pki,localhost"
$script:CaAddress = ":9000"
$script:CaProvisioner = "admin"
$script:DefaultCaPassword = "eca-poc-default-password"
$script:OpenxpkiRealm = "democa"
$script:OpenxpkiCaName = "est-ca"

function Test-VolumesExist {
    Write-Info "Checking if PKI volumes exist..."

    $volumes = @("pki-data", "openxpki-config-data", "openxpki-db")
    $allExist = $true

    foreach ($vol in $volumes) {
        try {
            docker volume inspect $vol 2>$null | Out-Null
            Write-Info "Volume '$vol' exists"
        }
        catch {
            Write-Warn "Volume '$vol' does not exist"
            $allExist = $false
        }
    }

    if ($allExist) {
        Write-Success "All PKI volumes exist"
        return $true
    }
    else {
        Write-Warn "Some PKI volumes are missing"
        return $false
    }
}

function Remove-AllVolumes {
    Write-Section "Cleaning All Volumes"

    Write-Warn "This will delete ALL ECA PoC volumes and data!"
    $confirmation = Read-Host "Are you sure? (yes/NO)"

    if ($confirmation -ne "yes") {
        Write-Info "Aborted by user"
        return
    }

    Invoke-CommandWithLogging -Description "Stopping all services" -Command {
        docker compose down -v
    } | Out-Null

    Write-Step "Removing all volumes..."
    $volumes = @(
        "pki-data", "server-certs", "client-certs", "challenge",
        "posh-acme-state", "est-data", "est-secrets",
        "openxpki-config-data", "openxpki-db", "openxpki-socket",
        "openxpki-client-socket", "openxpki-db-socket",
        "openxpki-log", "openxpki-log-ui", "openxpki-download",
        "loki-data", "grafana-data", "fluentd-buffer", "crl-data"
    )

    foreach ($vol in $volumes) {
        try {
            docker volume inspect $vol | Out-Null
            Write-Info "Removing volume: $vol"
            docker volume rm $vol 2>&1 | Out-Null
        }
        catch {
            # Volume doesn't exist, skip
        }
    }

    Write-Success "All volumes cleaned"
}

################################################################################
# PKI Initialization (step-ca)
################################################################################

function Initialize-Pki {
    Write-Section "Step 1: Initializing PKI (step-ca)"

    # Clean up any existing temp directory
    if (Test-Path $script:TempPkiDir) {
        Write-Warn "Removing existing temporary PKI directory"
        Remove-Item -Path $script:TempPkiDir -Recurse -Force
    }

    # Create temporary directory for initialization
    New-Item -ItemType Directory -Path $script:TempPkiDir -Force | Out-Null

    # Use password from environment variable if set, otherwise use default
    $caPassword = if ($env:ECA_CA_PASSWORD) {
        $env:ECA_CA_PASSWORD
        Write-Info "Using CA password from ECA_CA_PASSWORD environment variable"
    } else {
        $script:DefaultCaPassword
        Write-Info "Using default CA password"
        Write-Warn "Set ECA_CA_PASSWORD environment variable to use a custom password"
    }

    # Initialize CA using step ca init
    Write-Info "Running 'step ca init'..."

    $env:STEPPATH = $script:TempPkiDir

    # Create password files
    Set-Content -Path "$script:TempPkiDir/password.txt" -Value $caPassword -NoNewline
    Set-Content -Path "$script:TempPkiDir/provisioner_password.txt" -Value $caPassword -NoNewline

    step ca init `
        --name="$script:CaName" `
        --dns="$script:CaDns" `
        --address="$script:CaAddress" `
        --provisioner="$script:CaProvisioner" `
        --password-file="$script:TempPkiDir/password.txt" `
        --provisioner-password-file="$script:TempPkiDir/provisioner_password.txt"

    # Clean up temporary password files
    Remove-Item -Path "$script:TempPkiDir/password.txt" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$script:TempPkiDir/provisioner_password.txt" -Force -ErrorAction SilentlyContinue

    # Create the password file that step-ca will use at runtime
    $secretsDir = "$script:TempPkiDir/secrets"
    New-Item -ItemType Directory -Path $secretsDir -Force | Out-Null
    Set-Content -Path "$secretsDir/password" -Value $caPassword -NoNewline

    Write-Info "Password saved to $secretsDir/password"

    # Fix paths in configuration files to use container paths instead of host temp paths
    Write-Info "Fixing paths in configuration files for container environment..."

    $caJsonPath = "$script:TempPkiDir/config/ca.json"
    $defaultsJsonPath = "$script:TempPkiDir/config/defaults.json"

    if (Test-Path $caJsonPath) {
        (Get-Content $caJsonPath -Raw) -replace [regex]::Escape($script:TempPkiDir), "/home/step" | Set-Content $caJsonPath -NoNewline
    }
    if (Test-Path $defaultsJsonPath) {
        (Get-Content $defaultsJsonPath -Raw) -replace [regex]::Escape($script:TempPkiDir), "/home/step" | Set-Content $defaultsJsonPath -NoNewline
    }

    Write-Success "PKI CA initialized successfully"
    return $true
}

function New-PkiVolume {
    Write-Info "Creating PKI Docker volume: $script:VolumePki"

    # Check if volume already exists
    try {
        docker volume inspect $script:VolumePki 2>$null | Out-Null
        Write-Warn "Volume '$script:VolumePki' already exists"
        Write-Info "Keeping existing volume"
        return $true
    }
    catch {
        # Volume doesn't exist, create it
    }

    # Create the volume
    docker volume create $script:VolumePki
    Write-Success "PKI volume created successfully"
    return $true
}

function Copy-PkiToVolume {
    Write-Info "Copying initialized PKI data to Docker volume..."

    # Fix permissions for docker access (Linux/macOS)
    if ($IsLinux -or $IsMacOS) {
        chmod -R 777 $script:TempPkiDir
    }

    # Copy using /source/. pattern to avoid glob expansion issues
    # The dot notation copies all contents including hidden files
    if (-not (Invoke-CommandWithLogging -Description "Copying PKI data to volume" -Command {
        docker run --rm `
            --entrypoint sh `
            -v "$($script:VolumePki):/home/step" `
            -v "$($script:TempPkiDir):/source:ro" `
            smallstep/step-ca:latest `
            -c "cp -r /source/. /home/step/ && chown -R step:step /home/step"
    })) {
        return $false
    }

    Write-Success "PKI data copied to volume"
    return $true
}

function Start-PkiForProvisioning {
    Write-Info "Starting PKI container temporarily to configure provisioners..."

    # Start just the PKI service
    if (-not (Invoke-CommandWithLogging -Description "Starting PKI service" -Command {
        docker compose up -d pki
    })) {
        return $false
    }

    # Wait for PKI to be healthy
    Write-Info "Waiting for PKI to be ready..."
    for ($i = 1; $i -le 30; $i++) {
        try {
            $status = docker compose ps pki 2>$null
            if ($status -match "healthy") {
                Write-Success "PKI is healthy"
                return $true
            }
        }
        catch {
            # Continue waiting
        }
        Start-Sleep -Seconds 2
    }

    Write-ErrorMessage "PKI failed to become healthy"
    return $false
}

function Wait-ForEstCertificates {
    Write-Info "Waiting for EST certificates to be generated..."

    for ($i = 1; $i -le 30; $i++) {
        try {
            $result = docker run --rm -v pki-data:/pki:ro alpine test -f /pki/est-certs/est-ca.pem 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "EST certificates found"
                return $true
            }
        }
        catch {
            # Continue waiting
        }
        Write-Info "Attempt $i/30: EST certificates not ready yet..."
        Start-Sleep -Seconds 2
    }

    Write-ErrorMessage "EST certificates were not generated"
    return $false
}

################################################################################
# OpenXPKI Initialization
################################################################################

function Initialize-Openxpki {
    Write-Section "Step 2: Initializing OpenXPKI EST Server"

    # Create OpenXPKI config volume
    Write-Info "Creating OpenXPKI config volume: $script:VolumeOpenxpkiConfig"

    try {
        docker volume inspect $script:VolumeOpenxpkiConfig 2>$null | Out-Null
        Write-Warn "Volume '$script:VolumeOpenxpkiConfig' already exists - will reuse"
    }
    catch {
        docker volume create $script:VolumeOpenxpkiConfig
        Write-Success "OpenXPKI config volume created"
    }

    # Copy base OpenXPKI configuration
    if (-not (Invoke-CommandWithLogging -Description "Copying OpenXPKI base configuration" -Command {
        docker run --rm `
            -v "$($script:VolumeOpenxpkiConfig):/config" `
            -v "$(Get-Location)/est-server/openxpki-setup/openxpki-config:/source:ro" `
            alpine `
            sh -c "cp -r /source/. /config/"
    })) {
        return $false
    }

    Write-Success "OpenXPKI base configuration copied"

    # Copy EST certificates from PKI volume to OpenXPKI volume
    if (-not (Invoke-CommandWithLogging -Description "Copying EST certificates to OpenXPKI" -Command {
        docker run --rm `
            -v "$($script:VolumePki):/pki:ro" `
            -v "$($script:VolumeOpenxpkiConfig):/config" `
            alpine `
            sh -c @"
                mkdir -p /config/local/secrets && \
                cp /pki/est-certs/est-ca.pem /config/local/secrets/est-ca.crt && \
                cp /pki/est-certs/est-ca.key /config/local/secrets/est-ca.key && \
                cp /pki/certs/intermediate_ca.crt /config/local/secrets/step-intermediate.crt && \
                cp /pki/certs/root_ca.crt /config/local/secrets/root-ca.crt && \
                chmod 644 /config/local/secrets/*.crt && \
                chmod 600 /config/local/secrets/*.key
"@
    })) {
        return $false
    }

    Write-Success "EST certificates copied to OpenXPKI"

    # Setup OpenXPKI CA directories
    Write-Info "Setting up OpenXPKI CA directories..."
    docker run --rm `
        -v "$($script:VolumeOpenxpkiConfig):/config" `
        alpine `
        sh -c @"
            mkdir -p /config/local/keys/$script:OpenxpkiRealm && \
            mkdir -p /config/ca/$script:OpenxpkiRealm && \
            cp /config/local/secrets/est-ca.crt /config/ca/$script:OpenxpkiRealm/$script:OpenxpkiCaName.crt && \
            chmod 644 /config/ca/$script:OpenxpkiRealm/$script:OpenxpkiCaName.crt && \
            cp /config/local/secrets/est-ca.key /config/local/keys/$script:OpenxpkiRealm/$script:OpenxpkiCaName.pem && \
            chmod 600 /config/local/keys/$script:OpenxpkiRealm/$script:OpenxpkiCaName.pem && \
            chown -R 100:102 /config/local/keys/$script:OpenxpkiRealm && \
            cp /config/local/secrets/root-ca.crt /config/ca/$script:OpenxpkiRealm/root.crt && \
            chmod 644 /config/ca/$script:OpenxpkiRealm/root.crt
"@

    Write-Success "OpenXPKI CA directories configured"
    return $true
}

function Add-OpenxpkiWebTls {
    Write-Info "Provisioning OpenXPKI web TLS materials..."

    docker exec -i eca-pki bash -c @"
        set -euo pipefail
        mkdir -p /home/step/tmp
        STEPPATH=/home/step step ca certificate openxpki-web \
            /home/step/tmp/openxpki-web.crt \
            /home/step/tmp/openxpki-web.key \
            --provisioner $script:CaProvisioner \
            --provisioner-password-file /home/step/secrets/password \
            --ca-url https://localhost:9000 \
            --root /home/step/certs/root_ca.crt \
            --san openxpki-web \
            --san localhost \
            --force
"@

    docker run --rm `
        -v "$($script:VolumePki):/pki:ro" `
        -v "$($script:VolumeOpenxpkiConfig):/config" `
        alpine `
        sh -c @"
            set -e
            mkdir -p /config/tls/private /config/tls/endentity /config/tls/chain && \
            cat /pki/tmp/openxpki-web.crt /pki/certs/intermediate_ca.crt > /config/tls/endentity/openxpki.crt && \
            cp /pki/tmp/openxpki-web.key /config/tls/private/openxpki.pem && \
            cp /pki/certs/intermediate_ca.crt /config/tls/chain/intermediate-ca.crt && \
            cp /pki/certs/root_ca.crt /config/tls/chain/root-ca.crt && \
            chmod 600 /config/tls/private/openxpki.pem && \
            chmod 644 /config/tls/endentity/openxpki.crt /config/tls/chain/root-ca.crt /config/tls/chain/intermediate-ca.crt
"@

    docker exec eca-pki rm -f /home/step/tmp/openxpki-web.crt /home/step/tmp/openxpki-web.key 2>$null | Out-Null

    Write-Success "OpenXPKI web TLS certificate generated"
    return $true
}

function Initialize-OpenxpkiDatabase {
    Write-Info "Initializing OpenXPKI database schema..."

    # Start OpenXPKI database
    if (-not (Invoke-CommandWithLogging -Description "Starting OpenXPKI database" -Command {
        docker compose up -d openxpki-db
    })) {
        return $false
    }

    # Wait for database to be healthy
    Write-Info "Waiting for database to be ready..."
    for ($i = 1; $i -le 30; $i++) {
        try {
            $status = docker compose ps openxpki-db 2>$null
            if ($status -match "healthy") {
                Write-Success "Database is healthy"
                break
            }
        }
        catch {
            # Continue waiting
        }
        Start-Sleep -Seconds 2
    }

    # Determine whether schema already exists (check for core table)
    try {
        $result = docker exec eca-openxpki-db mariadb -N -uopenxpki -popenxpki `
            -e "SHOW TABLES LIKE 'aliases'" openxpki 2>$null
        if ($result -match "aliases") {
            Write-Info "Existing OpenXPKI schema detected – skipping import"
            return $true
        }
    }
    catch {
        # Schema doesn't exist, continue with import
    }

    # Copy schema file and import it
    Write-Info "Importing database schema..."

    # Extract schema from a temporary container
    docker run --rm `
        -v "$($script:VolumeOpenxpkiConfig):/config:ro" `
        alpine `
        cat /config/contrib/sql/schema-mariadb.sql | Out-File -FilePath "/tmp/openxpki-schema.sql" -Encoding utf8

    # Import schema
    Get-Content "/tmp/openxpki-schema.sql" | docker exec -i eca-openxpki-db mariadb -uopenxpki -popenxpki openxpki

    # Cleanup
    Remove-Item -Path "/tmp/openxpki-schema.sql" -Force -ErrorAction SilentlyContinue

    Write-Success "OpenXPKI database schema initialized"
    return $true
}

function Import-CertificatesToOpenxpki {
    Write-Info "Importing certificates into OpenXPKI database..."

    # Start OpenXPKI server
    if (-not (Invoke-CommandWithLogging -Description "Starting OpenXPKI server" -Command {
        docker compose up -d openxpki-server
    })) {
        return $false
    }

    # Wait for server to be healthy
    Write-Info "Waiting for OpenXPKI server to be ready..."
    for ($i = 1; $i -le 30; $i++) {
        try {
            $status = docker compose ps openxpki-server 2>$null
            if ($status -match "healthy") {
                Write-Success "OpenXPKI server is healthy"
                break
            }
        }
        catch {
            # Continue waiting
        }
        Start-Sleep -Seconds 2
    }

    # Import root CA (without chain validation)
    Write-Info "Importing step-ca root CA certificate..."
    docker exec eca-openxpki-server openxpkiadm certificate import `
        --file /etc/openxpki/local/secrets/root-ca.crt `
        --realm $script:OpenxpkiRealm `
        --force-no-chain

    # Import step-ca intermediate for bootstrap certificate chain
    Write-Info "Importing step-ca intermediate certificate..."
    docker exec eca-openxpki-server openxpkiadm certificate import `
        --file /etc/openxpki/local/secrets/step-intermediate.crt `
        --realm $script:OpenxpkiRealm

    # Import EST CA and create ca-signer alias
    Write-Info "Importing EST CA certificate and creating ca-signer alias..."
    docker exec -u root eca-openxpki-server sh -c "cp /etc/openxpki/local/secrets/est-ca.key /tmp/est-ca.key && chown openxpki:openxpki /tmp/est-ca.key && chmod 600 /tmp/est-ca.key"

    try {
        docker exec eca-openxpki-server openxpkiadm alias `
            --realm $script:OpenxpkiRealm `
            --token certsign `
            --file /etc/openxpki/local/secrets/est-ca.crt `
            --key /tmp/est-ca.key
    }
    catch {
        # If alias creation fails due to key permissions, copy key manually
        Write-Warn "Alias creation failed, copying key manually..."
        docker exec -u root eca-openxpki-server sh -c "cp /etc/openxpki/local/secrets/est-ca.key /etc/openxpki/local/keys/$script:OpenxpkiRealm/ca-signer-1.pem && chown openxpki:openxpki /etc/openxpki/local/keys/$script:OpenxpkiRealm/ca-signer-1.pem && chmod 600 /etc/openxpki/local/keys/$script:OpenxpkiRealm/ca-signer-1.pem"
    }

    docker exec eca-openxpki-server rm -f /tmp/est-ca.key 2>$null | Out-Null

    # Generate long-lived bootstrap certificate
    Write-Info "Generating bootstrap certificate..."
    docker exec -i eca-pki bash -c @"
        STEPPATH=/home/step step ca certificate bootstrap-client \
            /home/step/bootstrap-certs/bootstrap-client.pem \
            /home/step/bootstrap-certs/bootstrap-client.key \
            --provisioner admin \
            --provisioner-password-file /home/step/secrets/password \
            --ca-url https://localhost:9000 \
            --root /home/step/certs/root_ca.crt \
            --not-before 1m \
            --not-after 23h \
            --san bootstrap-client \
            --force
"@
    Start-Sleep -Seconds 5

    # Import bootstrap certificate (extract first cert from chain)
    Write-Info "Importing bootstrap certificate..."
    docker exec eca-openxpki-server sh -c @"
        sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p;/END CERTIFICATE/q' \
            /pki/bootstrap-certs/bootstrap-client.pem > /tmp/bootstrap-only.pem
"@
    docker exec eca-openxpki-server openxpkiadm certificate import `
        --file /tmp/bootstrap-only.pem `
        --realm $script:OpenxpkiRealm

    docker exec eca-openxpki-server rm -f /tmp/bootstrap-only.pem 2>$null | Out-Null

    Write-Success "Certificates imported into OpenXPKI database"
    return $true
}

function Initialize-Volumes {
    Write-Section "Initializing PKI Volumes"

    if ($SkipInit -and (Test-VolumesExist)) {
        Write-Info "⏭️  Skipping initialization (volumes already exist)"
        return $true
    }

    # Set non-interactive mode and default password
    if (-not $env:ECA_CA_PASSWORD) {
        $env:ECA_CA_PASSWORD = "eca-poc-default-password"
    }

    # Execute all initialization steps directly
    if (-not (Initialize-Pki)) { return $false }
    if (-not (New-PkiVolume)) { return $false }
    if (-not (Copy-PkiToVolume)) { return $false }

    # Start PKI to trigger provisioner configuration and EST cert generation
    if (-not (Start-PkiForProvisioning)) { return $false }
    if (-not (Wait-ForEstCertificates)) { return $false }

    # Now initialize OpenXPKI with the EST certificates
    if (-not (Initialize-Openxpki)) { return $false }
    if (-not (Add-OpenxpkiWebTls)) { return $false }
    if (-not (Initialize-OpenxpkiDatabase)) { return $false }
    if (-not (Import-CertificatesToOpenxpki)) { return $false }

    # Cleanup temporary files
    Write-Info "Cleaning up temporary files..."
    if (Test-Path $script:TempPkiDir) {
        Remove-Item -Path $script:TempPkiDir -Recurse -Force
    }
    Write-Success "Cleanup complete"

    Write-Success "✅ Volume initialization complete"
    return $true
}

################################################################################
# Stack Management
################################################################################

function Start-Stack {
    Write-Section "Starting Docker Compose Stack"

    Push-Location $script:ScriptDir
    try {
        if (-not (Invoke-CommandWithLogging -Description "Starting all services" -Command {
            docker compose up -d
        })) {
            return $false
        }

        Write-Info "Waiting for services to start..."
        Start-Sleep -Seconds 5

        Write-Success "Stack started"
        return $true
    }
    finally {
        Pop-Location
    }
}

function Wait-ForServiceHealthy {
    param(
        [string]$ServiceName,
        [int]$Timeout = $script:ServiceReadyTimeout
    )

    Write-Info "Waiting for $ServiceName to be healthy..."

    $interval = 2
    $elapsed = 0

    while ($elapsed -lt $Timeout) {
        try {
            $containerId = docker compose ps -q $ServiceName 2>$null
            if ([string]::IsNullOrEmpty($containerId)) {
                Start-Sleep -Seconds $interval
                $elapsed += $interval
                continue
            }

            $healthStatus = docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}running{{end}}' $containerId 2>$null
            if ($healthStatus -eq "healthy" -or $healthStatus -eq "running") {
                Write-Success "$ServiceName is $healthStatus"
                return $true
            }
        }
        catch {
            # Continue waiting
        }

        Start-Sleep -Seconds $interval
        $elapsed += $interval
    }

    Write-ErrorMessage "$ServiceName failed to become healthy within ${Timeout}s"
    return $false
}

function Wait-ForCoreServices {
    Write-Section "Waiting for Core Services"

    foreach ($service in $script:CoreServices) {
        if (-not (Wait-ForServiceHealthy -ServiceName $service)) {
            return $false
        }
    }

    Write-Success "All core services are healthy"
    return $true
}

################################################################################
# Endpoint Validation
################################################################################

function Test-Endpoint {
    param(
        [string]$Name,
        [string]$Url,
        [int]$ExpectedCode = 200
    )

    Write-Info "Validating: $Name"
    Write-Info "  URL: $Url"

    try {
        $response = Invoke-WebRequest -Uri $Url -SkipCertificateCheck -UseBasicParsing -TimeoutSec $script:EndpointTimeout -ErrorAction Stop
        if ($response.StatusCode -eq $ExpectedCode) {
            Write-Success "$Name is accessible (HTTP $($response.StatusCode))"
            return $true
        }
        else {
            Write-ErrorMessage "$Name returned unexpected HTTP code: $($response.StatusCode) (expected $ExpectedCode)"
            return $false
        }
    }
    catch {
        Write-ErrorMessage "$Name is not accessible: $_"
        return $false
    }
}

function Test-Endpoints {
    Write-Section "Validating Endpoints"

    $failed = 0

    # PKI (step-ca)
    Write-Step "Validating PKI endpoints..."
    if (-not (Test-Endpoint -Name "step-ca Health" -Url "https://localhost:4210/health")) { $failed++ }
    if (-not (Test-Endpoint -Name "step-ca ACME Directory" -Url "https://localhost:4210/acme/acme/directory")) { $failed++ }

    # CRL
    Write-Step "Validating CRL endpoint..."
    if (-not (Test-Endpoint -Name "CRL HTTP Server" -Url "http://localhost:4211/health")) { $failed++ }
    if (-not (Test-Endpoint -Name "CRL File" -Url "http://localhost:4211/crl/ca.crl")) { $failed++ }

    # OpenXPKI EST
    Write-Step "Validating EST endpoints..."
    if (-not (Test-Endpoint -Name "OpenXPKI Web UI" -Url "http://localhost:4212/")) { $failed++ }
    if (-not (Test-Endpoint -Name "EST cacerts" -Url "https://localhost:4213/.well-known/est/cacerts")) { $failed++ }

    # Target services
    Write-Step "Validating target services..."
    if (-not (Test-Endpoint -Name "Target Server" -Url "https://localhost:4214")) {
        Write-Warn "Target server may not have cert yet"
    }

    if ($failed -eq 0) {
        Write-Success "All endpoints validated successfully"
        return $true
    }
    else {
        Write-ErrorMessage "$failed endpoint(s) failed validation"
        return $false
    }
}

################################################################################
# Testing
################################################################################

function Invoke-IntegrationTests {
    Write-Section "Running Integration Tests"

    Push-Location $script:ScriptDir
    try {
        Write-Step "Running Pester integration tests..."

        # Check if Pester is installed
        if (-not (Get-Module -ListAvailable -Name Pester)) {
            Write-ErrorMessage "Pester module not found. Installing..."
            Install-Module -Name Pester -MinimumVersion 5.0 -Force -Scope CurrentUser
        }

        $config = New-PesterConfiguration
        $config.Run.Path = './tests/integration'
        $config.Run.Exit = $true
        $config.Output.Verbosity = 'Detailed'

        Invoke-Pester -Configuration $config

        if ($LASTEXITCODE -eq 0) {
            Write-Success "All integration tests passed"
            return $true
        }
        else {
            Write-ErrorMessage "Integration tests failed (exit code: $LASTEXITCODE)"
            return $false
        }
    }
    finally {
        Pop-Location
    }
}

################################################################################
# Status Display
################################################################################

function Show-StackStatus {
    Write-Section "Stack Status"

    Write-Host "Container Status:" -ForegroundColor Cyan
    docker compose ps

    Write-Host ""
    Write-Host "Quick Access URLs (Custom Port Range 4210-4230):" -ForegroundColor Cyan
    Write-Host "  step-ca:        " -ForegroundColor Green -NoNewline
    Write-Host "https://localhost:4210/health"
    Write-Host "  ACME Directory: " -ForegroundColor Green -NoNewline
    Write-Host "https://localhost:4210/acme/acme/directory"
    Write-Host "  CRL Endpoint:   " -ForegroundColor Green -NoNewline
    Write-Host "http://localhost:4211/crl/ca.crl"
    Write-Host "  EST Endpoint:   " -ForegroundColor Green -NoNewline
    Write-Host "https://localhost:4213/.well-known/est/"
    Write-Host "  OpenXPKI UI:    " -ForegroundColor Green -NoNewline
    Write-Host "http://localhost:4212/"
    Write-Host "  Target Server:  " -ForegroundColor Green -NoNewline
    Write-Host "https://localhost:4214/"
    Write-Host "  Web UI:         " -ForegroundColor Green -NoNewline
    Write-Host "http://localhost:4216/"
    Write-Host "  Grafana:        " -ForegroundColor Green -NoNewline
    Write-Host "http://localhost:4219/ (admin/eca-admin)"
    Write-Host ""
}

################################################################################
# Cleanup
################################################################################

function Stop-Stack {
    if ($NoCleanup) {
        Write-Info "Skipping cleanup (NoCleanup flag set)"
        Show-StackStatus
        return
    }

    Write-Section "Cleaning Up"

    Invoke-CommandWithLogging -Description "Stopping services" -Command {
        docker compose down
    } | Out-Null

    Write-Success "Cleanup complete"
}

################################################################################
# Main Execution Flow
################################################################################

function Main {
    # Show help if requested
    if ($Help) {
        Show-Usage
        exit 0
    }

    # Quick mode implies SkipInit
    if ($Quick) {
        $script:SkipInit = $true
    }

    # Header
    Write-Section "ECA PoC - Integration Test Orchestration"

    # Setup logging
    Initialize-Logging

    # Check prerequisites first
    if (-not (Test-Prerequisites)) {
        Write-ErrorMessage "Prerequisites not met. Aborting."
        exit 1
    }

    # Clean mode
    if ($Clean) {
        Remove-AllVolumes
        $script:SkipInit = $false
    }

    # Execution based on flags
    if ($ValidateOnly) {
        if (-not (Test-Endpoints)) {
            exit 3
        }
        exit 0
    }

    if ($TestOnly) {
        if (-not (Invoke-IntegrationTests)) {
            exit 4
        }
        exit 0
    }

    # Initialize volumes
    if ($InitOnly -or -not $StartOnly) {
        if (-not (Initialize-Volumes)) {
            exit 1
        }
    }

    if ($InitOnly) {
        Write-Success "Initialization complete (InitOnly mode)"
        exit 0
    }

    # Start stack
    if ($StartOnly -or -not $InitOnly) {
        if (-not (Start-Stack)) {
            exit 2
        }
        if (-not (Wait-ForCoreServices)) {
            exit 2
        }
    }

    if ($StartOnly) {
        Write-Success "Stack started (StartOnly mode)"
        Show-StackStatus
        exit 0
    }

    # Validate endpoints
    Start-Sleep -Seconds 5  # Give services a moment to fully stabilize
    if (-not (Test-Endpoints)) {
        Write-ErrorMessage "Endpoint validation failed"
        Stop-Stack
        exit 3
    }

    # Run tests
    if (-not (Invoke-IntegrationTests)) {
        Write-ErrorMessage "Integration tests failed"
        Stop-Stack
        exit 4
    }

    # Cleanup
    Stop-Stack

    # Success
    Write-Section "🎉 Integration Tests Complete"
    Write-Success "✅ All tests passed successfully!"

    Write-Host ""
    Write-Host "🚀 Next steps:" -ForegroundColor Green
    Write-Host "  ⚡ Run " -NoNewline
    Write-Host "./integration-test.ps1 -Quick" -ForegroundColor Cyan -NoNewline
    Write-Host " for faster subsequent runs"
    Write-Host "  🔍 Use " -NoNewline
    Write-Host "-NoCleanup" -ForegroundColor Cyan -NoNewline
    Write-Host " to keep stack running for manual testing"
    Write-Host "  📊 Use " -NoNewline
    Write-Host "docker compose logs -f" -ForegroundColor Cyan -NoNewline
    Write-Host " to monitor agent activity"
    Write-Host "  📈 Open Grafana at " -NoNewline
    Write-Host "http://localhost:4219" -ForegroundColor Green -NoNewline
    Write-Host " (admin/eca-admin)"
    Write-Host "  🌐 Open Web UI at " -NoNewline
    Write-Host "http://localhost:4216" -ForegroundColor Green
    Write-Host ""
}

# Run main function
try {
    Main
}
catch {
    Write-ErrorMessage "Script failed: $_"
    Stop-Stack
    exit 1
}
