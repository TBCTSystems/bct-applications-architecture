<#
.SYNOPSIS
    Run ACME agent locally on Windows (without copying files).

.DESCRIPTION
    Sets up and runs agent-PoshACME.ps1 directly from source directory.
    
    Steps performed:
    1. Validates Docker containers are running
    2. Installs required PowerShell modules
    3. Creates working directories
    4. Sets environment variables
    5. Runs agent from source

.PARAMETER WorkingPath
    Directory for runtime data. Default: C:\temp

.PARAMETER SkipModuleInstall
    Skip module installation if already installed.

.PARAMETER ConfigureOnly
    Setup only, don't run agent.

.EXAMPLE
    .\Run-LocalAgent.ps1
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$WorkingPath = "C:\temp",
    [switch]$SkipModuleInstall,
    [switch]$ConfigureOnly
)

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-ColorOutput {
    param([string]$Message, [ValidateSet('Info','Success','Warning','Error')]$Level = 'Info')
    $colors = @{ Info = 'Cyan'; Success = 'Green'; Warning = 'Yellow'; Error = 'Red' }
    Write-Host $Message -ForegroundColor $colors[$Level]
}

function Write-SectionHeader {
    param([string]$Title)
    Write-Host "`n================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "================================`n" -ForegroundColor Cyan
}

# ============================================================================
# VALIDATION
# ============================================================================

Write-SectionHeader "Validating Prerequisites"

# Check PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-ColorOutput "PowerShell 7.0+ required. Current: $($PSVersionTable.PSVersion)" -Level Error
    exit 1
}
Write-ColorOutput "✓ PowerShell $($PSVersionTable.PSVersion)" -Level Success

# Check Docker containers
Write-ColorOutput "Checking Docker containers..." -Level Info
$pkiRunning = docker ps --format "{{.Names}}" | Select-String -Pattern "eca-pki" -Quiet
$targetRunning = docker ps --format "{{.Names}}" | Select-String -Pattern "eca-target-server" -Quiet

if (-not $pkiRunning) {
    Write-ColorOutput "✗ Container 'eca-pki' not running" -Level Error
    exit 1
}
if (-not $targetRunning) {
    Write-ColorOutput "✗ Container 'eca-target-server' not running" -Level Error
    exit 1
}
Write-ColorOutput "✓ Docker containers running" -Level Success

# ============================================================================
# MODULE INSTALLATION
# ============================================================================

if (-not $SkipModuleInstall) {
    Write-SectionHeader "Installing PowerShell Modules"
    
    $modules = @(
        @{ Name = 'Posh-ACME'; MinVersion = '4.29.3' }
        @{ Name = 'powershell-yaml'; MinVersion = '0.4.0' }
    )
    
    foreach ($mod in $modules) {
        $installed = Get-Module -ListAvailable -Name $mod.Name | 
                     Where-Object { $_.Version -ge [version]$mod.MinVersion } |
                     Select-Object -First 1
        
        if ($installed) {
            Write-ColorOutput "✓ $($mod.Name) $($installed.Version) already installed" -Level Success
        } else {
            Write-ColorOutput "Installing $($mod.Name)..." -Level Info
            Install-Module -Name $mod.Name -MinimumVersion $mod.MinVersion -Force -Scope CurrentUser -AllowClobber
            Write-ColorOutput "✓ $($mod.Name) installed" -Level Success
        }
    }
}

# ============================================================================
# DIRECTORY SETUP
# ============================================================================

Write-SectionHeader "Creating Working Directories"

$certPath = Join-Path $WorkingPath "certs"
$logPath = Join-Path $WorkingPath "logs"
$challengePath = Join-Path $WorkingPath "challenge"
$poshAcmePath = Join-Path $WorkingPath "posh-acme-state"

@($certPath, $logPath, $challengePath, $poshAcmePath) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
        Write-ColorOutput "Created: $_" -Level Success
    } else {
        Write-ColorOutput "Exists: $_" -Level Info
    }
}

$configFile = Join-Path $PSScriptRoot "agents\acme\config.yaml"

# ============================================================================
# ENVIRONMENT VARIABLES
# ============================================================================

Write-SectionHeader "Setting Environment Variables"

# Clear existing ACME variables
Get-ChildItem Env: | Where-Object { $_.Name -match "^ACME" } | ForEach-Object {
    Remove-Item "Env:$($_.Name)" -ErrorAction SilentlyContinue
}

$schemaPath = Join-Path $PSScriptRoot "config\agent_config_schema.json"

# Only set essential environment variables for Windows-specific overrides
# Most config comes from config.yaml - these ENV vars override for local Windows execution
$envVars = @{
    # Required: Tell agent where to find config files
    'AGENT_CONFIG_PATH' = $configFile
    'AGENT_CONFIG_SCHEMA_PATH' = $schemaPath
    
    # Windows-specific path overrides (config.yaml has Linux paths)
    'ACME_PKI_URL' = 'https://localhost:9000'  # Override pki:9000 (Docker internal hostname)
    'ACME_DOMAIN_NAME' = 'eca-target-server'    # Container name for Windows host
    'ACME_CERT_PATH' = "$certPath\server.crt"   # Windows path instead of /certs/server/server.crt
    'ACME_KEY_PATH' = "$certPath\server.key"    # Windows path instead of /certs/server/server.key
    'ACME_CHALLENGE_DIRECTORY' = $challengePath # Windows path instead of /challenge
    
    # Posh-ACME state directory
    'POSHACME_HOME' = $poshAcmePath
    
    # Logging
    'LOG_PATH' = "$logPath\acme-agent.log"
}

foreach ($key in $envVars.Keys) {
    Set-Item -Path "env:$key" -Value $envVars[$key]
}

Write-ColorOutput "✓ Environment variables configured" -Level Success

# ============================================================================
# RUN AGENT
# ============================================================================

if ($ConfigureOnly) {
    Write-SectionHeader "Configuration Complete"
    Write-ColorOutput "Setup complete. Run agent manually:" -Level Info
    Write-ColorOutput "  .\agents\acme\agent-PoshACME.ps1" -Level Info
    exit 0
}

Write-SectionHeader "Starting ACME Agent"

$agentScript = Join-Path $PSScriptRoot "agents\acme\agent-PoshACME.ps1"

if (-not (Test-Path $agentScript)) {
    Write-ColorOutput "✗ Agent script not found: $agentScript" -Level Error
    exit 1
}

Write-ColorOutput "Running: $agentScript" -Level Info
Write-ColorOutput "Press Ctrl+C to stop`n" -Level Warning

try {
    & $agentScript
} catch {
    Write-ColorOutput "✗ Agent failed: $($_.Exception.Message)" -Level Error
    exit 1
}
