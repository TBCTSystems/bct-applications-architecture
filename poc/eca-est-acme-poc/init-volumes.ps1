#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Infrastructure volume initialization for the ECA PoC (PowerShell edition).

.DESCRIPTION
    Initializes all Docker volumes required by the PoC on Windows or any host
    running PowerShell 7+. Mirrors the behaviour of init-volumes.sh:
      1. Runs `step ca init` to seed the PKI volume (pki-data)
      2. Copies shared EST trust chain into the OpenXPKI config volume
      3. Bootstraps the OpenXPKI database/schema and imports certificates
      4. Generates the long-lived bootstrap certificate for EST agents

.PREREQUISITES
    - PowerShell 7+
    - step CLI installed and available on PATH
    - Docker Desktop / Docker Engine with `docker compose` v2

.USAGE
    pwsh ./init-volumes.ps1               # interactive (prompts for confirmation)
    pwsh ./init-volumes.ps1 -Force        # skip confirmation
    ECA_CA_PASSWORD=secret pwsh ./init-volumes.ps1

#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

param(
    [switch]$Force
)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

$script:PkiVolumeName = 'pki-data'
$script:OpenXpkiConfigVolumeName = 'openxpki-config-data'
$script:TempPkiDir = Join-Path ([System.IO.Path]::GetTempPath()) 'eca-pki-init'
$script:CaName = 'ECA-PoC-CA'
$script:CaDns = 'pki,localhost'
$script:CaAddress = ':9000'
$script:CaProvisioner = 'admin'
$script:DefaultCaPassword = 'eca-poc-default-password'
$script:OpenXpkiRealm = 'democa'
$script:OpenXpkiCaName = 'est-ca'
$script:ProjectRoot = Split-Path -Parent $PSCommandPath

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

function Write-Section {
    param([string]$Message)
    Write-Host ''
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host ''
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Invoke-DockerCompose {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Args
    )
    & docker compose @Args
}

function Wait-ForContainerHealthy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,
        [int]$TimeoutSeconds = 180
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $inspect = & docker inspect -f '{{.State.Health.Status}}' $ContainerName 2>$null
        if ($LASTEXITCODE -eq 0) {
            $state = $inspect.Trim()
            if ($state -eq 'healthy' -or $state -eq 'none') {
                return
            }
        }
        Start-Sleep -Seconds 4
    }

    throw "Container '$ContainerName' did not become healthy within $TimeoutSeconds seconds."
}

function Replace-PathInFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string]$PathToReplace,
        [Parameter(Mandatory = $true)]
        [string]$Replacement
    )

    if (-not (Test-Path $FilePath)) {
        return
    }

    $content = Get-Content -Raw -Path $FilePath
    if ([string]::IsNullOrEmpty($content)) {
        return
    }

    $escaped = [Regex]::Escape($PathToReplace)
    $content = [Regex]::Replace($content, $escaped, $Replacement)

    # Also replace forward-slash variant (handles mixed path separators)
    $forwardVariant = $PathToReplace -replace '\\', '/'
    if ($forwardVariant -ne $PathToReplace) {
        $escapedForward = [Regex]::Escape($forwardVariant)
        $content = [Regex]::Replace($content, $escapedForward, $Replacement)
    }

    Set-Content -Path $FilePath -Value $content -Encoding UTF8
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------

function Test-Prerequisites {
    Write-Info "Checking prerequisites..."

    if (-not (Test-CommandExists 'step')) {
        Write-ErrorMessage "step CLI not found on PATH."
        Write-Host "Download: https://smallstep.com/docs/step-cli/installation"
        return $false
    }

    if (-not (Test-CommandExists 'docker')) {
        Write-ErrorMessage "Docker CLI not found on PATH."
        return $false
    }

    try {
        & docker info | Out-Null
    }
    catch {
        Write-ErrorMessage "Docker daemon is not running. Please start Docker Desktop/Engine."
        return $false
    }

    Write-Success "All prerequisites met"
    return $true
}

# ---------------------------------------------------------------------------
# PKI initialization
# ---------------------------------------------------------------------------

function Get-CaPassword {
    if ($env:ECA_CA_PASSWORD -and $env:ECA_CA_PASSWORD.Trim().Length -gt 0) {
        Write-Info "Using CA password from ECA_CA_PASSWORD environment variable."
        return $env:ECA_CA_PASSWORD
    }

    if ([Console]::IsInputRedirected) {
        Write-Warn "Non-interactive session detected. Using default CA password ($script:DefaultCaPassword)."
        return $script:DefaultCaPassword
    }

    Write-Host ""
    Write-Host "You will be asked to set a password for the CA keys."
    Write-Host "IMPORTANT: Remember this password – you'll need it when the containers start." -ForegroundColor Yellow
    Write-Host ""

    $prompt = "Enter password for CA keys (Press Enter for default: $($script:DefaultCaPassword))"
    $securePassword = Read-Host -AsSecureString -Prompt $prompt
    if (($securePassword | Measure-Object -Property Length -Sum).Sum -eq 0) {
        return $script:DefaultCaPassword
    }

    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Initialize-Pki {
    Write-Section "Step 1: Initializing PKI (step-ca)"

    if (Test-Path $script:TempPkiDir) {
        Write-Warn "Removing existing temporary PKI directory: $($script:TempPkiDir)"
        Remove-Item -Path $script:TempPkiDir -Recurse -Force
    }

    Ensure-Directory $script:TempPkiDir

    $caPassword = Get-CaPassword

    $passwordFile = Join-Path $script:TempPkiDir 'password.txt'
    $provisionerPasswordFile = Join-Path $script:TempPkiDir 'provisioner_password.txt'

    [System.IO.File]::WriteAllText($passwordFile, $caPassword)
    [System.IO.File]::WriteAllText($provisionerPasswordFile, $caPassword)

    $previousStepPath = $env:STEPPATH
    $env:STEPPATH = $script:TempPkiDir
    try {
        $stepArgs = @(
            'ca', 'init',
            '--name', $script:CaName,
            '--dns', $script:CaDns,
            '--address', $script:CaAddress,
            '--provisioner', $script:CaProvisioner,
            '--password-file', $passwordFile,
            '--provisioner-password-file', $provisionerPasswordFile
        )

        Write-Info "Running step ca init..."
        & step @stepArgs | Out-Null
    }
    finally {
        if ($previousStepPath) {
            $env:STEPPATH = $previousStepPath
        }
        else {
            Remove-Item Env:STEPPATH -ErrorAction SilentlyContinue
        }

        Remove-Item -Path $passwordFile -ErrorAction SilentlyContinue
        Remove-Item -Path $provisionerPasswordFile -ErrorAction SilentlyContinue
    }

    Ensure-Directory (Join-Path $script:TempPkiDir 'secrets')
    [System.IO.File]::WriteAllText((Join-Path $script:TempPkiDir 'secrets/password'), $caPassword)

    # step ca init writes absolute host paths; replace them with container paths
    $caJson = Join-Path $script:TempPkiDir 'config/ca.json'
    $defaultsJson = Join-Path $script:TempPkiDir 'config/defaults.json'
    Replace-PathInFile -FilePath $caJson -PathToReplace $script:TempPkiDir -Replacement '/home/step'
    Replace-PathInFile -FilePath $defaultsJson -PathToReplace $script:TempPkiDir -Replacement '/home/step'

    Write-Success "PKI CA initialized successfully"
}

function Ensure-PkiVolume {
    Write-Info "Ensuring Docker volume '$($script:PkiVolumeName)' exists..."

    $volumeExists = (& docker volume inspect $script:PkiVolumeName 2>$null) -ne $null
    if ($volumeExists) {
        Write-Warn "Volume '$($script:PkiVolumeName)' already exists."
        if (-not $Force) {
            $response = Read-Host "Remove and recreate it? (y/N)"
            if ($response -notmatch '^[Yy]$') {
                Write-Info "Keeping existing volume."
                return
            }
        }
        & docker volume rm $script:PkiVolumeName | Out-Null
    }

    & docker volume create $script:PkiVolumeName | Out-Null
    Write-Success "Docker volume '$($script:PkiVolumeName)' created."
}

function Copy-PkiToVolume {
    Write-Info "Copying initialized PKI to Docker volume..."

    $sourcePath = Resolve-Path $script:TempPkiDir

    & docker run --rm `
        -v "$($script:PkiVolumeName):/home/step" `
        -v "$($sourcePath):/source:ro" `
        smallstep/step-ca:latest `
        sh -c "cp -r /source/* /home/step/ && chown -R step:step /home/step" | Out-Null

    Write-Success "PKI data copied to Docker volume."
}

# ---------------------------------------------------------------------------
# step-ca helpers
# ---------------------------------------------------------------------------

function Start-PkiForProvisioning {
    Write-Info "Starting step-ca container to generate provisioners..."
    Invoke-DockerCompose -Args @('up', '-d', 'pki') | Out-Null
    Wait-ForContainerHealthy -ContainerName 'eca-pki'
    Write-Success "step-ca container healthy."
}

function Wait-ForEstCertificates {
    Write-Info "Waiting for EST certificates to be generated..."

    for ($i = 1; $i -le 30; $i++) {
        try {
            & docker run --rm `
                -v "$($script:PkiVolumeName):/pki:ro" `
                alpine `
                sh -c "test -f /pki/est-certs/est-ca.pem" | Out-Null
            Write-Success "EST certificates found."
            return
        }
        catch {
            Write-Info "Attempt $i/30: EST certificates not available yet..."
            Start-Sleep -Seconds 2
        }
    }

    throw "EST certificates were not generated within the expected time."
}

# ---------------------------------------------------------------------------
# OpenXPKI initialization
# ---------------------------------------------------------------------------

function Ensure-OpenXpkiVolume {
    Write-Info "Ensuring Docker volume '$($script:OpenXpkiConfigVolumeName)' exists..."

    $volumeExists = (& docker volume inspect $script:OpenXpkiConfigVolumeName 2>$null) -ne $null
    if (-not $volumeExists) {
        & docker volume create $script:OpenXpkiConfigVolumeName | Out-Null
        Write-Success "Docker volume '$($script:OpenXpkiConfigVolumeName)' created."
    }
    else {
        Write-Warn "Volume '$($script:OpenXpkiConfigVolumeName)' already exists - reusing."
    }
}

function Copy-OpenXpkiBaseConfig {
    Write-Info "Copying OpenXPKI base configuration..."
    $sourcePath = Resolve-Path (Join-Path $script:ProjectRoot 'est-server/openxpki-setup/openxpki-config')

    & docker run --rm `
        -v "$($script:OpenXpkiConfigVolumeName):/config" `
        -v "$sourcePath:/source:ro" `
        alpine `
        sh -c "cp -r /source/* /config/" | Out-Null

    Write-Success "OpenXPKI base configuration copied."
}

function Copy-EstCertificatesToOpenXpki {
    Write-Info "Copying EST certificates into OpenXPKI configuration..."

    & docker run --rm `
        -v "$($script:PkiVolumeName):/pki:ro" `
        -v "$($script:OpenXpkiConfigVolumeName):/config" `
        alpine `
        sh -c "
            mkdir -p /config/local/secrets && \
            cp /pki/est-certs/est-ca.pem /config/local/secrets/est-ca.crt && \
            cp /pki/est-certs/est-ca.key /config/local/secrets/est-ca.key && \
            cp /pki/certs/intermediate_ca.crt /config/local/secrets/step-intermediate.crt && \
            cp /pki/certs/root_ca.crt /config/local/secrets/root-ca.crt && \
            chmod 644 /config/local/secrets/*.crt && \
            chmod 600 /config/local/secrets/*.key
        " | Out-Null

    Write-Success "EST certificates copied."

    Write-Info "Configuring OpenXPKI CA directories..."
    # UID/GID 100:102 map to openxpki:openxpki inside the server container.
    & docker run --rm `
        -v "$($script:OpenXpkiConfigVolumeName):/config" `
        alpine `
        sh -c "
            mkdir -p /config/local/keys/${script:OpenXpkiRealm} && \
            mkdir -p /config/ca/${script:OpenXpkiRealm} && \
            cp /config/local/secrets/est-ca.crt /config/ca/${script:OpenXpkiRealm}/${script:OpenXpkiCaName}.crt && \
            chmod 644 /config/ca/${script:OpenXpkiRealm}/${script:OpenXpkiCaName}.crt && \
            cp /config/local/secrets/est-ca.key /config/local/keys/${script:OpenXpkiRealm}/${script:OpenXpkiCaName}.pem && \
            chmod 600 /config/local/keys/${script:OpenXpkiRealm}/${script:OpenXpkiCaName}.pem && \
            chown -R 100:102 /config/local/keys/${script:OpenXpkiRealm} && \
            cp /config/local/secrets/root-ca.crt /config/ca/${script:OpenXpkiRealm}/root.crt && \
            chmod 644 /config/ca/${script:OpenXpkiRealm}/root.crt
        " | Out-Null

    Write-Success "OpenXPKI CA directories configured."
}

function Provision-OpenXpkiWebTls {
    Write-Info "Provisioning OpenXPKI web TLS certificate..."

    & docker exec -i eca-pki bash -c "
        set -euo pipefail
        mkdir -p /home/step/tmp
        STEPPATH=/home/step step ca certificate openxpki-web \
            /home/step/tmp/openxpki-web.crt \
            /home/step/tmp/openxpki-web.key \
            --provisioner ${script:CaProvisioner} \
            --provisioner-password-file /home/step/secrets/password \
            --ca-url https://localhost:9000 \
            --root /home/step/certs/root_ca.crt \
            --san openxpki-web \
            --san localhost \
            --force
    " | Out-Null

    & docker run --rm `
        -v "$($script:PkiVolumeName):/pki:ro" `
        -v "$($script:OpenXpkiConfigVolumeName):/config" `
        alpine `
        sh -c "
            set -e
            mkdir -p /config/tls/private /config/tls/endentity /config/tls/chain && \
            cat /pki/tmp/openxpki-web.crt /pki/certs/intermediate_ca.crt > /config/tls/endentity/openxpki.crt && \
            cp /pki/tmp/openxpki-web.key /config/tls/private/openxpki.pem && \
            cp /pki/certs/intermediate_ca.crt /config/tls/chain/intermediate-ca.crt && \
            cp /pki/certs/root_ca.crt /config/tls/chain/root-ca.crt && \
            chmod 600 /config/tls/private/openxpki.pem && \
            chmod 644 /config/tls/endentity/openxpki.crt /config/tls/chain/root-ca.crt /config/tls/chain/intermediate-ca.crt
        " | Out-Null

    & docker exec eca-pki rm -f /home/step/tmp/openxpki-web.crt /home/step/tmp/openxpki-web.key | Out-Null

    Write-Success "OpenXPKI web TLS certificate generated."
}

function Initialize-OpenXpkiDatabase {
    Write-Info "Starting OpenXPKI database..."
    Invoke-DockerCompose -Args @('up', '-d', 'openxpki-db') | Out-Null
    Wait-ForContainerHealthy -ContainerName 'eca-openxpki-db'

    $schemaExists = docker exec eca-openxpki-db mariadb -N -uopenxpki -popenxpki `
        -e "SHOW TABLES LIKE 'aliases'" openxpki

    if ($schemaExists -match 'aliases') {
        Write-Info "Existing OpenXPKI schema detected – skipping import."
        return
    }

    Write-Info "Importing OpenXPKI database schema..."
    $schemaContent = & docker run --rm `
        -v "$($script:OpenXpkiConfigVolumeName):/config:ro" `
        alpine `
        cat /config/contrib/sql/schema-mariadb.sql

    $schemaPath = Join-Path $script:TempPkiDir 'openxpki-schema.sql'
    Set-Content -Path $schemaPath -Value $schemaContent -Encoding UTF8

    Get-Content -Raw $schemaPath | docker exec -i eca-openxpki-db mariadb -uopenxpki -popenxpki openxpki
    Remove-Item -Path $schemaPath -Force

    Write-Success "OpenXPKI database schema initialized."
}

function Import-CertificatesIntoOpenXpki {
    Write-Info "Starting OpenXPKI server..."
    Invoke-DockerCompose -Args @('up', '-d', 'openxpki-server') | Out-Null
    Wait-ForContainerHealthy -ContainerName 'eca-openxpki-server'

    Write-Info "Importing root CA certificate into OpenXPKI..."
    & docker exec eca-openxpki-server openxpkiadm certificate import `
        --file /etc/openxpki/local/secrets/root-ca.crt `
        --realm $script:OpenXpkiRealm `
        --force-no-chain | Out-Null

    Write-Info "Importing step-ca intermediate certificate..."
    & docker exec eca-openxpki-server openxpkiadm certificate import `
        --file /etc/openxpki/local/secrets/step-intermediate.crt `
        --realm $script:OpenXpkiRealm | Out-Null

    Write-Info "Importing EST CA certificate into OpenXPKI..."
    try {
        & docker exec -u root eca-openxpki-server sh -c "cp /etc/openxpki/local/secrets/est-ca.key /tmp/est-ca.key && chown openxpki:openxpki /tmp/est-ca.key && chmod 600 /tmp/est-ca.key" | Out-Null
        & docker exec eca-openxpki-server openxpkiadm alias `
            --realm $script:OpenXpkiRealm `
            --token certsign `
            --file /etc/openxpki/local/secrets/est-ca.crt `
            --key /tmp/est-ca.key | Out-Null
    }
    catch {
        Write-Warn "Alias creation failed; copying key manually."
        & docker exec -u root eca-openxpki-server sh -c "cp /etc/openxpki/local/secrets/est-ca.key /etc/openxpki/local/keys/$($script:OpenXpkiRealm)/ca-signer-1.pem && chown openxpki:openxpki /etc/openxpki/local/keys/$($script:OpenXpkiRealm)/ca-signer-1.pem && chmod 600 /etc/openxpki/local/keys/$($script:OpenXpkiRealm)/ca-signer-1.pem" | Out-Null
    }
    finally {
        & docker exec eca-openxpki-server rm -f /tmp/est-ca.key | Out-Null
    }

    Write-Info "Generating bootstrap certificate for EST agents..."
    & docker exec -i eca-pki bash -c "
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
            --force" | Out-Null

    Start-Sleep -Seconds 5

    Write-Info "Importing bootstrap certificate into OpenXPKI realm..."
    & docker exec eca-openxpki-server sh -c "
        sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p;/END CERTIFICATE/q' \
            /pki/bootstrap-certs/bootstrap-client.pem > /tmp/bootstrap-only.pem" | Out-Null

    & docker exec eca-openxpki-server openxpkiadm certificate import `
        --file /tmp/bootstrap-only.pem `
        --realm $script:OpenXpkiRealm | Out-Null

    & docker exec eca-openxpki-server rm -f /tmp/bootstrap-only.pem | Out-Null

    Write-Success "Certificates imported into OpenXPKI."
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

function Cleanup-Temp {
    Write-Info "Cleaning up temporary files..."
    if (Test-Path $script:TempPkiDir) {
        Remove-Item -Path $script:TempPkiDir -Recurse -Force
    }
    Write-Success "Cleanup complete."
}

# ---------------------------------------------------------------------------
# Main workflow
# ---------------------------------------------------------------------------

function Invoke-Main {
    Write-Section "ECA PoC - Infrastructure Volume Initialization (PowerShell)"

    if (-not (Test-Prerequisites)) {
        throw "Prerequisite check failed."
    }

    Write-Host ""
    Write-Info "This script will initialize:"
    Write-Info "  1. PKI (step-ca) Certificate Authority"
    Write-Info "  2. OpenXPKI EST server with shared trust chain"
    Write-Info "  3. Required Docker volumes"
    Write-Host ""

    if (-not $Force) {
        if (-not [Console]::IsInputRedirected) {
            $answer = Read-Host "Continue? (y/N)"
            if ($answer -notmatch '^[Yy]$') {
                Write-Info "Aborted by user."
                return
            }
        }
        else {
            Write-Info "Non-interactive mode detected – continuing automatically."
        }
    }

    Initialize-Pki
    Ensure-PkiVolume
    Copy-PkiToVolume
    Start-PkiForProvisioning
    Wait-ForEstCertificates

    Ensure-OpenXpkiVolume
    Copy-OpenXpkiBaseConfig
    Copy-EstCertificatesToOpenXpki
    Provision-OpenXpkiWebTls
    Initialize-OpenXpkiDatabase
    Import-CertificatesIntoOpenXpki

    Write-Section "🎉 Infrastructure Initialization Complete!"
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Start all services:" -NoNewline
    Write-Host "  docker compose up -d" -ForegroundColor Green
    Write-Host "  2. Verify PKI health:" -NoNewline
    Write-Host "   curl -k https://localhost:9000/health" -ForegroundColor Green
    Write-Host "       (expect {`"status`":`"ok`"})"
    Write-Host "  3. Open OpenXPKI Web UI:" -NoNewline
    Write-Host " http://localhost:8080" -ForegroundColor Green
    Write-Host "       (or https://localhost:8443)"
    Write-Host "  4. Open Grafana:" -NoNewline
    Write-Host "          http://localhost:3000" -ForegroundColor Green
    Write-Host "       (admin/eca-admin)"
    Write-Host "  5. Run automated checks:" -NoNewline
    Write-Host " ./scripts/run-tests.sh" -ForegroundColor Green
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

try {
    Push-Location $script:ProjectRoot
    Invoke-Main
    Cleanup-Temp
    exit 0
}
catch {
    Write-ErrorMessage $_.Exception.Message
    Cleanup-Temp
    exit 1
}
finally {
    Pop-Location | Out-Null
}
