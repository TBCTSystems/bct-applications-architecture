<#
.SYNOPSIS
    ACME agent main script orchestrating automated certificate lifecycle management.

.DESCRIPTION
    agent.ps1 is the main entry point for the ECA-ACME agent. This script implements
    an autonomous event-driven architecture using time-based polling to manage server
    certificate lifecycle through the ACME protocol (RFC 8555).

    The agent runs an infinite loop executing the following phases:
    1. DETECT: Check current certificate status (expiry date, lifetime percentage)
    2. DECIDE: Apply renewal policy (threshold-based or force-trigger file)
    3. ACT: Execute ACME protocol flow if renewal is needed
    4. SLEEP: Wait for next polling interval

    Workflow:
    - Load configuration from YAML file with environment variable overrides
    - Initialize ACME account (create on first run, load existing on subsequent runs)
    - Enter main loop:
        - Monitor certificate expiry using CertificateMonitor
        - Trigger renewal when LifetimeElapsedPercent > RenewalThreshold or force file exists
        - Generate new RSA key pair and CSR
        - Execute ACME protocol: newOrder -> challenge -> finalize -> download
        - Install certificate and key atomically with correct permissions
        - Reload NGINX for zero-downtime activation
        - Sleep for configured check interval (default: 60 seconds)
    - Handle graceful shutdown (SIGTERM cleanup)

.NOTES
    Author: ECA Project
    Requires: PowerShell Core 7.0+
    Dependencies:
        - agents/acme/AcmeClient.psm1 (ACME protocol implementation)
        - agents/acme/ServiceReloadController.psm1 (NGINX reload)
        - agents/common/Logger.psm1 (structured logging)
        - agents/common/CryptoHelper.psm1 (key generation, CSR creation)
        - agents/common/CertificateMonitor.psm1 (certificate checking)
        - agents/common/ConfigManager.psm1 (configuration loading)
        - agents/common/FileOperations.psm1 (atomic file writes, permissions)

    Configuration:
        - Primary source: /agent/config.yaml (YAML)
        - Override mechanism: Environment variables (uppercase snake_case)
        - Required fields: pki_url, cert_path, key_path, domain_name
        - Optional fields: renewal_threshold_pct (default: 75), check_interval_sec (default: 60)

    Security Considerations:
        - Account private key stored at /config/acme-account.key with 0600 permissions
        - Certificate private keys set to 0600 immediately after creation
        - Certificates set to 0644 for service read access
        - RSA objects disposed properly to release unmanaged resources

    Architecture:
        - Event-Driven: Time-based polling with configurable interval
        - Autonomous: No external scheduler dependencies
        - Resilient: Temporary failures auto-retry on next cycle
        - Resource Efficient: Sleep intervals prevent CPU waste

.LINK
    Architecture: docs/ARCHITECTURE.md (Event-Driven Architecture Pattern)
    Sequence Diagram: docs/diagrams/acme_renewal_sequence.puml
    Task Specification: I2.T7 (ACME Agent Main Script)

.EXAMPLE
    # Run agent with default configuration
    ./agents/acme/agent.ps1

.EXAMPLE
    # Run with custom configuration path
    PKI_URL=https://pki:9000 DOMAIN=myserver.local ./agents/acme/agent.ps1
#>

#Requires -Version 7.0

# NOTE: using namespace statement removed - it was causing module import scope issues
# Classes will use fully-qualified names instead

# Resolve shared module directory so the script works inside the container (/agent/common)
# and when executed from the repo checkout (agents/common).
$commonModuleCandidates = @()

$localCommon = Join-Path $PSScriptRoot 'common'
if (Test-Path (Join-Path $localCommon 'Logger.psm1')) {
    $commonModuleCandidates += $localCommon
}

$parentDir = Split-Path $PSScriptRoot -Parent
if (-not [string]::IsNullOrWhiteSpace($parentDir)) {
    $parentCommon = Join-Path $parentDir 'common'
    if (Test-Path (Join-Path $parentCommon 'Logger.psm1')) {
        $commonModuleCandidates += $parentCommon
    }
}

$script:CommonModuleDirectory = $commonModuleCandidates | Select-Object -First 1
if (-not $script:CommonModuleDirectory) {
    throw "ACME agent: unable to locate common module directory relative to $PSScriptRoot."
}

function Import-AgentCommonModule {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleFileName,

        [switch]$GlobalScope
    )

    $fullPath = Join-Path $script:CommonModuleDirectory $ModuleFileName
    if (-not (Test-Path $fullPath)) {
        throw "ACME agent: common module not found at $fullPath."
    }

    $importParams = @{
        Name        = $fullPath
        Force       = $true
        ErrorAction = 'Stop'
    }

    if ($GlobalScope) {
        $importParams['Global'] = $true
    }

    Import-Module @importParams | Out-Null
}

# ============================================================================
# LOGGING FUNCTIONS (inlined to avoid PowerShell module scoping issues)
# ============================================================================

function global:Write-LogEntry {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('INFO','WARN','ERROR','DEBUG')]
        [string]$Severity,
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [Parameter(Mandatory=$false)]
        [hashtable]$Context = @{}
    )
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $logFormat = if ($env:LOG_FORMAT) { $env:LOG_FORMAT } else { "console" }

    if ($logFormat -eq "json") {
        $logEntry = [ordered]@{
            timestamp = $timestamp
            severity  = $Severity
            message   = $Message
            context   = $Context
        }
        # NOTE: Using Write-Host instead of Write-Output to prevent log pollution in function return values
        Write-Host ($logEntry | ConvertTo-Json -Compress -Depth 3)
    } else {
        $colorMap = @{ 'INFO' = [ConsoleColor]::Cyan; 'WARN' = [ConsoleColor]::Yellow; 'ERROR' = [ConsoleColor]::Red; 'DEBUG' = [ConsoleColor]::Gray }
        $consoleMessage = "[$timestamp] $Severity`: $Message"
        if ($Context.Count -gt 0) {
            $contextPairs = $Context.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
            $consoleMessage += " ($($contextPairs -join ', '))"
        }
        Write-Host $consoleMessage -ForegroundColor $colorMap[$Severity]
    }
}

function global:Write-LogInfo { param([Parameter(Mandatory=$true)][string]$Message, [hashtable]$Context = @{}) Write-LogEntry -Severity 'INFO' -Message $Message -Context $Context }
function global:Write-LogWarn { param([Parameter(Mandatory=$true)][string]$Message, [hashtable]$Context = @{}) Write-LogEntry -Severity 'WARN' -Message $Message -Context $Context }
function global:Write-LogError { param([Parameter(Mandatory=$true)][string]$Message, [hashtable]$Context = @{}) Write-LogEntry -Severity 'ERROR' -Message $Message -Context $Context }
function global:Write-LogDebug { param([Parameter(Mandatory=$true)][string]$Message, [hashtable]$Context = @{}) Write-LogEntry -Severity 'DEBUG' -Message $Message -Context $Context }

# ============================================================================
# ENVIRONMENT PREFIX HELPERS
# ============================================================================

function Add-PrefixDelimiterIfMissing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    if ([string]::IsNullOrWhiteSpace($Prefix)) {
        return ""
    }

    if ($Prefix.EndsWith("_")) {
        return $Prefix
    }

    return "${Prefix}_"
}

function Get-AgentEnvPrefixList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$DefaultPrefix = "ACME_"
    )

    $prefixes = New-Object System.Collections.Generic.List[string]

    $explicitPrefix = $env:AGENT_ENV_PREFIX
    if (-not [string]::IsNullOrWhiteSpace($explicitPrefix)) {
        $prefixes.Add($explicitPrefix)
    }

    if ([string]::IsNullOrWhiteSpace($explicitPrefix) -and -not [string]::IsNullOrWhiteSpace($env:AGENT_NAME)) {
        $prefixes.Add((Add-PrefixDelimiterIfMissing -Prefix $env:AGENT_NAME))
    }

    if (-not [string]::IsNullOrWhiteSpace($DefaultPrefix)) {
        $prefixes.Add((Add-PrefixDelimiterIfMissing -Prefix $DefaultPrefix))
    }

    $prefixes.Add("")

    return $prefixes | Where-Object { $_ -ne $null } | Select-Object -Unique
}

function Get-AgentEnvValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    foreach ($name in $Names) {
        foreach ($prefix in $script:AgentEnvPrefixes) {
            $envVarName = if ([string]::IsNullOrWhiteSpace($prefix)) { $name } else { "$prefix$name" }
            $value = [System.Environment]::GetEnvironmentVariable($envVarName)

            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return $value
            }
        }
    }

    return $null
}

# ============================================================================
# MODULE IMPORTS
# ============================================================================

# Import all required modules at script-level (before function definitions)
# This ensures functions from these modules are available globally
$modulePath = Split-Path -Parent $PSCommandPath
Write-Host "DEBUG: Module path: $modulePath" -ForegroundColor Cyan

try {
    # NOTE: Logger.psm1 NOT imported - using inlined logging functions above
    # Use paths relative to working directory (/agent) with explicit ./ prefix
    Import-AgentCommonModule -ModuleFileName 'CryptoHelper.psm1' -GlobalScope
    Import-AgentCommonModule -ModuleFileName 'FileOperations.psm1' -GlobalScope
    Import-AgentCommonModule -ModuleFileName 'CertificateMonitor.psm1' -GlobalScope
    Import-AgentCommonModule -ModuleFileName 'ConfigManager.psm1' -GlobalScope
    Import-AgentCommonModule -ModuleFileName 'CrlValidator.psm1' -GlobalScope
    Import-Module "./AcmeClient.psm1" -Force -Global -ErrorAction Stop
    Import-Module "./ServiceReloadController.psm1" -Force -Global -ErrorAction Stop
    Write-Host "DEBUG: All modules imported successfully" -ForegroundColor Green
} catch {
    Write-Host "FATAL: Failed to import modules: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

# ACME account object (persisted across loop iterations)
$script:AcmeAccount = $null

# Flag for graceful shutdown
$script:ShutdownRequested = $false

# Environment variable prefixes evaluated for overrides (namespaced per agent)
$script:AgentEnvPrefixes = Get-AgentEnvPrefixList -DefaultPrefix "ACME_"

# ============================================================================
# GRACEFUL SHUTDOWN HANDLER
# ============================================================================

# NOTE: Shutdown handler moved to inside Start-AcmeAgent function
# where imported functions are guaranteed to be in scope

# ============================================================================
# CONFIGURATION LOADING
# ============================================================================

function Get-AgentConfiguration {
    <#
    .SYNOPSIS
        Load agent configuration from YAML file with environment variable overrides.

    .DESCRIPTION
        Attempts to load configuration from /agent/config.yaml. If file does not exist,
        falls back to environment variables. Environment variables always override YAML values.

    .OUTPUTS
        System.Collections.Hashtable - Configuration object with all required fields.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    try {
        $configPath = "/agent/config.yaml"
        Write-Host "DEBUG: Checking config file: $configPath"
        $pathExists = Test-Path -Path $configPath -PathType Leaf
        Write-Host "DEBUG: Config file exists: $pathExists"

        if ($pathExists) {
            try {
                Write-Host "DEBUG: Entering config load block"
                Write-LogInfo -Message "Loading configuration from YAML" -Context @{path = $configPath}
                Write-Host "DEBUG: About to call Read-AgentConfig"
                $configResult = Read-AgentConfig -ConfigFilePath $configPath -EnvVarPrefixes $script:AgentEnvPrefixes
                Write-Host "DEBUG: Read-AgentConfig returned, finding hashtable in output"
                # ConfigManager logs to stdout, which pollutes the return value
                # Filter to find the actual hashtable (not string log lines)
                $config = $configResult | Where-Object { $_ -is [hashtable] } | Select-Object -First 1
                if ($null -eq $config) {
                    throw "Read-AgentConfig did not return a hashtable (got $($configResult.GetType().FullName) with $($configResult.Length) elements)"
                }
                Write-Host "DEBUG: Config hashtable found, pki_url: [$($config.pki_url)]"
                Write-LogInfo -Message "Config loaded" -Context @{
                    pki_url = $config.pki_url
                    domain_name = $config.domain_name
                    cert_path = $config.cert_path
                    key_path = $config.key_path
                }
            }
            catch {
                Write-Host "DEBUG: Exception in config load: $($_.Exception.Message)"
                Write-Host "DEBUG: Exception type: $($_.Exception.GetType().FullName)"
                Write-Host "DEBUG: Stack trace: $($_.ScriptStackTrace)"
                throw
            }
        }
        else {
            Write-LogWarn -Message "Config file not found, using environment variables" -Context @{path = $configPath}

            # Fall back to environment variables using configured prefixes
            $config = @{
                pki_url = Get-AgentEnvValue -Names @("PKI_URL")
                cert_path = Get-AgentEnvValue -Names @("CERT_PATH")
                key_path = Get-AgentEnvValue -Names @("KEY_PATH")
                domain_name = Get-AgentEnvValue -Names @("DOMAIN_NAME", "DOMAIN")
                renewal_threshold_pct = 75
                check_interval_sec = 60
            }

            $renewalEnv = Get-AgentEnvValue -Names @("RENEWAL_THRESHOLD_PCT")
            if (-not [string]::IsNullOrWhiteSpace($renewalEnv)) {
                try {
                    $config.renewal_threshold_pct = [int]$renewalEnv
                }
                catch {
                    throw "Configuration error: Field 'RENEWAL_THRESHOLD_PCT' must be an integer (got: '$renewalEnv')"
                }
            }

            $intervalEnv = Get-AgentEnvValue -Names @("CHECK_INTERVAL_SEC")
            if (-not [string]::IsNullOrWhiteSpace($intervalEnv)) {
                try {
                    $config.check_interval_sec = [int]$intervalEnv
                }
                catch {
                    throw "Configuration error: Field 'CHECK_INTERVAL_SEC' must be an integer (got: '$intervalEnv')"
                }
            }
        }

        # Validate required fields
        $requiredFields = @('pki_url', 'cert_path', 'key_path', 'domain_name')
        foreach ($field in $requiredFields) {
            if ([string]::IsNullOrWhiteSpace($config[$field])) {
                throw "Required configuration field missing: $field"
            }
        }

        # Apply defaults for optional fields
        if (-not $config.ContainsKey('renewal_threshold_pct') -or $null -eq $config.renewal_threshold_pct) {
            $config.renewal_threshold_pct = 75
        }
        if (-not $config.ContainsKey('check_interval_sec') -or $null -eq $config.check_interval_sec) {
            $config.check_interval_sec = 60
        }

        Write-LogInfo -Message "Configuration loaded successfully" -Context @{
            pki_url = $config.pki_url
            cert_path = $config.cert_path
            key_path = $config.key_path
            domain_name = $config.domain_name
            renewal_threshold_pct = $config.renewal_threshold_pct
            check_interval_sec = $config.check_interval_sec
        }

        return $config
    }
    catch {
        Write-LogError -Message "Configuration failed" -Context @{
            error = $_.Exception.Message
            stack_trace = $_.ScriptStackTrace
        }
        throw
    }
}

# ============================================================================
# ACME ACCOUNT INITIALIZATION
# ============================================================================

function Initialize-AcmeAccount {
    <#
    .SYNOPSIS
        Initialize ACME account (create new or load existing).

    .DESCRIPTION
        Checks if account key file exists at /config/acme-account.key.
        If exists, loads existing account. If not, creates new account.

    .PARAMETER BaseUrl
        Base URL of step-ca PKI server.

    .OUTPUTS
        System.Collections.Hashtable - Account object with AccountKey property.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl
    )

    $accountKeyPath = "/config/acme-account.key"

    try {
        if (Test-Path -Path $accountKeyPath -PathType Leaf) {
            # Load existing account
            Write-LogInfo -Message "Loading existing ACME account" -Context @{key_path = $accountKeyPath}
            $account = Get-AcmeAccount -BaseUrl $BaseUrl -AccountKeyPath $accountKeyPath
            Write-LogInfo -Message "ACME account loaded" -Context @{
                account_url = $account.URL
                status = $account.Status
            }
        }
        else {
            # Create new account
            Write-LogInfo -Message "Creating new ACME account" -Context @{key_path = $accountKeyPath}
            $account = New-AcmeAccount -BaseUrl $BaseUrl -AccountKeyPath $accountKeyPath
            Write-LogInfo -Message "ACME account created" -Context @{
                account_url = $account.URL
                status = $account.Status
            }
        }

        return $account
    }
    catch {
        Write-LogError -Message "ACME account initialization failed" -Context @{
            error = $_.Exception.Message
            stack_trace = $_.ScriptStackTrace
        }
        throw
    }
}

# ============================================================================
# CRL VALIDATION
# ============================================================================

function Test-CertificateAgainstCrl {
    <#
    .SYNOPSIS
        Validate certificate against CRL and update cache.

    .DESCRIPTION
        Downloads/updates CRL cache and checks if certificate is revoked.

    .PARAMETER Config
        Configuration hashtable with CRL settings.

    .PARAMETER CertPath
        Path to certificate file to validate.

    .OUTPUTS
        System.Collections.Hashtable - Validation result with revoked status.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter(Mandatory = $true)]
        [string]$CertPath
    )

    $result = @{
        CrlEnabled = $false
        CrlChecked = $false
        Revoked = $false
        CrlAge = -1.0
        RevokedCount = 0
        Error = $null
    }

    try {
        # Check if CRL is enabled in config
        if (-not $Config.ContainsKey('crl') -or -not $Config.crl.enabled) {
            Write-LogDebug -Message "CRL validation disabled in configuration"
            return $result
        }

        $result.CrlEnabled = $true

        # Validate CRL configuration
        if ([string]::IsNullOrWhiteSpace($Config.crl.url) -or
            [string]::IsNullOrWhiteSpace($Config.crl.cache_path)) {
            Write-LogWarn -Message "CRL enabled but URL or cache_path not configured"
            return $result
        }

        # Update CRL cache
        Write-LogDebug -Message "Updating CRL cache" -Context @{
            crl_url = $Config.crl.url
            cache_path = $Config.crl.cache_path
        }

        $maxAge = if ($Config.crl.max_age_hours) { $Config.crl.max_age_hours } else { 24.0 }
        $updateResult = Update-CrlCache `
            -Url $Config.crl.url `
            -CachePath $Config.crl.cache_path `
            -MaxAgeHours $maxAge

        $result.CrlAge = $updateResult.CrlAge
        $result.RevokedCount = $updateResult.RevokedCount

        if ($null -ne $updateResult.Error) {
            Write-LogWarn -Message "CRL cache update failed" -Context @{
                error = $updateResult.Error
            }
            $result.Error = $updateResult.Error
            return $result
        }

        Write-LogInfo -Message "CRL cache updated" -Context @{
            crl_age_hours = [math]::Round($updateResult.CrlAge, 2)
            revoked_count = $updateResult.RevokedCount
            downloaded = $updateResult.Downloaded
        }

        # Check if certificate exists
        if (-not (Test-Path $CertPath)) {
            Write-LogDebug -Message "Certificate does not exist - skipping CRL check" -Context @{
                cert_path = $CertPath
            }
            return $result
        }

        # Validate certificate against CRL
        Write-LogDebug -Message "Checking certificate against CRL" -Context @{
            cert_path = $CertPath
            crl_path = $Config.crl.cache_path
        }

        $revoked = Test-CertificateRevoked `
            -CertificatePath $CertPath `
            -CrlPath $Config.crl.cache_path

        $result.CrlChecked = $true

        if ($null -eq $revoked) {
            Write-LogWarn -Message "CRL validation inconclusive"
            $result.Error = "CRL validation returned null"
            return $result
        }

        $result.Revoked = $revoked

        if ($revoked) {
            Write-LogWarn -Message "Certificate is REVOKED according to CRL" -Context @{
                cert_path = $CertPath
            }
        } else {
            Write-LogInfo -Message "Certificate is VALID (not revoked)" -Context @{
                cert_path = $CertPath
            }
        }

        return $result
    }
    catch {
        Write-LogError -Message "CRL validation failed" -Context @{
            error = $_.Exception.Message
            cert_path = $CertPath
        }
        $result.Error = $_.Exception.Message
        return $result
    }
}

# ============================================================================
# CERTIFICATE RENEWAL WORKFLOW
# ============================================================================

function Invoke-CertificateRenewal {
    <#
    .SYNOPSIS
        Execute complete ACME certificate renewal workflow.

    .DESCRIPTION
        Performs the following steps:
        1. Generate new RSA key pair and CSR
        2. Create ACME order
        3. Get authorization and challenge
        4. Complete HTTP-01 challenge
        5. Wait for challenge validation
        6. Finalize order with CSR
        7. Download certificate
        8. Install certificate and key with atomic writes and permissions
        9. Reload NGINX service

    .PARAMETER Config
        Configuration hashtable from Get-AgentConfiguration.

    .PARAMETER Account
        ACME account object from Initialize-AcmeAccount.

    .OUTPUTS
        System.Boolean - $true if renewal succeeded, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter(Mandatory = $true)]
        [hashtable]$Account
    )

    try {
        Write-LogInfo -Message "Renewal triggered" -Context @{
            domain = $Config.domain_name
        }

        # STEP 1: Generate new RSA key pair
        Write-LogDebug -Message "Generating new RSA 2048-bit key pair"
        $rsa = [System.Security.Cryptography.RSA]::Create(2048)

        # STEP 2: Create CSR
        Write-LogDebug -Message "Creating certificate signing request" -Context @{
            subject_dn = "CN=$($Config.domain_name)"
            sans = @($Config.domain_name)
        }
        $csrPem = New-CertificateRequest `
            -SubjectDN "CN=$($Config.domain_name)" `
            -SubjectAlternativeNames @($Config.domain_name) `
            -RsaKey $rsa

        # STEP 2.5: Export RSA key to PEM for storage
        Write-LogDebug -Message "Exporting private key to PEM format"
        $newKeyPem = Export-PrivateKey -RsaKey $rsa

        # STEP 3: Get ACME directory
        $directory = Get-AcmeDirectory -BaseUrl $Config.pki_url

        # STEP 4: Create ACME order
        Write-LogDebug -Message "Creating ACME order" -Context @{
            domains = @($Config.domain_name)
        }
        $order = New-AcmeOrder `
            -BaseUrl $Config.pki_url `
            -DomainNames @($Config.domain_name) `
            -AccountKey $Account.AccountKey `
            -AccountKeyId $Account.URL

        Write-LogInfo -Message "ACME order created" -Context @{
            order_url = $order.URL
            status = $order.Status
            authorizations_count = $order.Authorizations.Count
        }

        # STEP 5: Get authorization
        Write-LogDebug -Message "Fetching authorization" -Context @{
            authorization_url = $order.Authorizations[0]
        }
        $authz = Get-AcmeAuthorization `
            -AuthorizationUrl $order.Authorizations[0] `
            -AccountKey $Account.AccountKey `
            -AccountKeyId $Account.URL `
            -NewNonceUrl $directory.newNonce

        # Find HTTP-01 challenge
        $challengePso = $authz.Challenges | Where-Object { $_.type -eq "http-01" }
        if ($null -eq $challengePso) {
            throw "HTTP-01 challenge not found in authorization"
        }

        # Convert PSCustomObject to Hashtable
        $challenge = @{
            type = $challengePso.type
            status = $challengePso.status
            token = $challengePso.token
            url = $challengePso.url
        }

        Write-LogDebug -Message "HTTP-01 challenge found" -Context @{
            token = $challenge.token
            challenge_url = $challenge.url
        }

        # STEP 6: Complete HTTP-01 challenge
        Write-LogDebug -Message "Completing HTTP-01 challenge"
        Complete-Http01Challenge `
            -Challenge $challenge `
            -AccountKey $Account.AccountKey `
            -AccountKeyId $Account.URL `
            -NewNonceUrl $directory.newNonce

        Write-LogInfo -Message "Challenge response submitted" -Context @{
            challenge_url = $challenge.url
        }

        # STEP 7: Wait for challenge validation
        Write-LogDebug -Message "Waiting for challenge validation"
        Wait-ChallengeValidation `
            -AuthorizationUrl $order.Authorizations[0] `
            -AccountKey $Account.AccountKey `
            -AccountKeyId $Account.URL `
            -NewNonceUrl $directory.newNonce

        Write-LogInfo -Message "Challenge validated successfully"

        # STEP 8: Finalize order
        Write-LogDebug -Message "Finalizing ACME order" -Context @{
            finalize_url = $order.Finalize
        }
        $finalOrder = Complete-AcmeOrder `
            -Order $order `
            -CsrPem $csrPem `
            -AccountKey $Account.AccountKey `
            -AccountKeyId $Account.URL `
            -NewNonceUrl $directory.newNonce

        Write-LogInfo -Message "Order finalized" -Context @{
            status = $finalOrder.Status
            certificate_url = $finalOrder.Certificate
        }

        # STEP 9: Download certificate
        Write-LogDebug -Message "Downloading certificate" -Context @{
            certificate_url = $finalOrder.Certificate
        }
        $certPem = Get-AcmeCertificate `
            -CertificateUrl $finalOrder.Certificate `
            -AccountKey $Account.AccountKey `
            -AccountKeyId $Account.URL `
            -NewNonceUrl $directory.newNonce

        Write-LogInfo -Message "Certificate downloaded" -Context @{
            certificate_length = $certPem.Length
        }

        # STEP 10: Install private key
        Write-LogDebug -Message "Installing private key" -Context @{
            key_path = $Config.key_path
        }
        Write-FileAtomic -Path $Config.key_path -Content $newKeyPem
        Set-FilePermissions -Path $Config.key_path -Mode "0600"

        # STEP 11: Install certificate
        Write-LogDebug -Message "Installing certificate" -Context @{
            cert_path = $Config.cert_path
        }
        Write-FileAtomic -Path $Config.cert_path -Content $certPem
        Set-FilePermissions -Path $Config.cert_path -Mode "0644"

        Write-LogInfo -Message "Certificate installed" -Context @{
            cert_path = $Config.cert_path
            key_path = $Config.key_path
        }

        # STEP 12: Reload NGINX
        Write-LogDebug -Message "Reloading NGINX service"
        $reloadSuccess = Invoke-NginxReload

        if ($reloadSuccess) {
            Write-LogInfo -Message "NGINX reloaded" -Context @{
                container = "target-server"
            }
        }
        else {
            Write-LogWarn -Message "NGINX reload failed - certificate installed but not activated"
        }

        # Remove force-renew trigger file if it exists
        $forceRenewPath = "/tmp/force-renew"
        if (Test-Path -Path $forceRenewPath) {
            try {
                Remove-Item -Path $forceRenewPath -Force -ErrorAction SilentlyContinue
                Write-LogDebug -Message "Force-renew trigger file removed" -Context @{path = $forceRenewPath}
            }
            catch {
                # Ignore cleanup errors - file may not exist or be locked
            }
        }

        return $true
    }
    catch {
        Write-LogError -Message "Certificate renewal failed" -Context @{
            error = $_.Exception.Message
            stack_trace = $_.ScriptStackTrace
            domain = $Config.domain_name
        }
        return $false
    }
    finally {
        # Dispose RSA object to release unmanaged cryptographic resources
        if ($null -ne $rsa) {
            try {
                $rsa.Dispose()
            }
            catch {
                # Ignore disposal errors - resource may already be disposed
            }
        }
    }
}

# ============================================================================
# MAIN LOOP
# ============================================================================

function Start-AcmeAgent {
    <#
    .SYNOPSIS
        Main entry point - runs the ACME agent event loop.

    .DESCRIPTION
        Loads configuration, initializes ACME account, then enters infinite loop:
        1. Check certificate status
        2. Decide if renewal needed
        3. Execute renewal if needed
        4. Sleep for check interval
    #>
    [CmdletBinding()]
    param()

    # NOTE: All modules are imported at script-level (before function definitions)
    # This ensures global availability of all functions

    try {
        Write-LogInfo -Message "Agent started" -Context @{
            version = "1.0.0"
            powershell_version = $PSVersionTable.PSVersion.ToString()
        }

        # Load configuration
        $config = Get-AgentConfiguration

        # Initialize ACME account
        $script:AcmeAccount = Initialize-AcmeAccount -BaseUrl $config.pki_url

        # Main event loop
        while ($true) {
            try {
                # PHASE 1: DETECT - Check certificate status
                $certExists = Test-CertificateExists -Path $config.cert_path
                $lifetimeElapsedPercent = 0

                if ($certExists) {
                    $certInfo = Get-CertificateInfo -Path $config.cert_path
                    $lifetimeElapsedPercent = $certInfo.LifetimeElapsedPercent

                    Write-LogInfo -Message "Certificate check: $($lifetimeElapsedPercent)% elapsed" -Context @{
                        cert_path = $config.cert_path
                        lifetime_elapsed_pct = $lifetimeElapsedPercent
                        days_remaining = $certInfo.DaysRemaining
                        not_after = $certInfo.NotAfter.ToString("yyyy-MM-dd HH:mm:ss")
                    }

                    # CRL Validation - Check if certificate is revoked
                    $crlResult = Test-CertificateAgainstCrl -Config $config -CertPath $config.cert_path

                    if ($crlResult.CrlEnabled -and $crlResult.CrlChecked) {
                        if ($crlResult.Revoked) {
                            Write-LogWarn -Message "Certificate revoked - forcing renewal" -Context @{
                                cert_path = $config.cert_path
                                crl_age_hours = $crlResult.CrlAge
                            }
                            # Force renewal for revoked certificate
                            $lifetimeElapsedPercent = 100
                        }
                    }
                }
                else {
                    Write-LogInfo -Message "Certificate not found - initial issuance needed" -Context @{
                        cert_path = $config.cert_path
                    }
                }

                # PHASE 2: DECIDE - Determine if renewal needed
                $forceRenewPath = "/tmp/force-renew"
                $forceRenew = Test-Path -Path $forceRenewPath

                $renewalNeeded = (-not $certExists) -or
                                 ($lifetimeElapsedPercent -gt $config.renewal_threshold_pct) -or
                                 $forceRenew

                if ($forceRenew) {
                    Write-LogInfo -Message "Force renewal triggered by file" -Context @{
                        trigger_file = $forceRenewPath
                    }
                }

                # PHASE 3: ACT - Execute renewal if needed
                if ($renewalNeeded) {
                    $renewalSuccess = Invoke-CertificateRenewal -Config $config -Account $script:AcmeAccount

                    if ($renewalSuccess) {
                        Write-LogInfo -Message "Certificate renewal completed successfully"
                    }
                    else {
                        Write-LogWarn -Message "Certificate renewal failed - will retry on next iteration"
                    }
                }

                # PHASE 4: SLEEP - Wait for next check
                Write-LogInfo -Message "Sleeping $($config.check_interval_sec) seconds" -Context @{
                    check_interval_sec = $config.check_interval_sec
                }
                Start-Sleep -Seconds $config.check_interval_sec
            }
            catch {
                # Log error but continue loop (resilient to transient failures)
                Write-LogError -Message "Main loop iteration failed" -Context @{
                    error = $_.Exception.Message
                    stack_trace = $_.ScriptStackTrace
                }

                # Sleep before retry to avoid tight error loops
                Start-Sleep -Seconds 10
            }
        }
    }
    catch {
        Write-Host "FATAL ERROR: Agent initialization failed" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Type: $($_.Exception.GetType().FullName)" -ForegroundColor Red
        Write-Host "Stack: $($_.ScriptStackTrace)" -ForegroundColor Red
        exit 1
    }
    finally {
        # Cleanup on shutdown
        if ($null -ne $script:AcmeAccount -and $null -ne $script:AcmeAccount.AccountKey) {
            try {
                $script:AcmeAccount.AccountKey.Dispose()
            }
            catch {
                # Ignore disposal errors - resource may already be disposed
            }
        }
    }
}

# ============================================================================
# ENTRY POINT
# ============================================================================

# Start the agent
Start-AcmeAgent
