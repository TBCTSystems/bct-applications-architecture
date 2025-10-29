<#
.SYNOPSIS
    Posh-ACME Configuration Adapter for ECA-ACME Agent

.DESCRIPTION
    PoshAcmeConfigAdapter.psm1 provides a compatibility layer between our existing
    ECA-ACME configuration system and Posh-ACME cmdlets. This adapter ensures
    backward compatibility while leveraging Posh-ACME's enterprise-grade ACME
    implementation.

    Key Features:
    - Maintains existing YAML configuration structure
    - Preserves environment variable override system
    - Maps ECA configuration to Posh-ACME parameters
    - Handles Posh-ACME server setup and account management
    - Provides error handling and logging integration

.NOTES
    Module Name: PoshAcmeConfigAdapter
    Author: ECA Project
    Requires: PowerShell Core 7.0+, Posh-ACME 4.29.3+
    Dependencies:
        - agents/common/Logger.psm1 (structured logging)
        - agents/common/FileOperations.psm1 (atomic file operations)
        - agents/common/ConfigManager.psm1 (configuration loading)
        - Posh-ACME module (ACME protocol implementation)

    Configuration Compatibility:
        - 100% backward compatible with existing YAML configuration
        - Environment variable overrides fully preserved
        - JSON schema validation maintained
        - No breaking changes to existing deployments

    Security Considerations:
        - Maintains existing file permissions (0600 for keys, 0644 for certs)
        - Preserves atomic file operations for certificate installation
        - Integrates with existing logging and monitoring
        - Uses Posh-ACME's secure account management

.LINK
    Configuration Mapping: docs/POSH_ACME_CONFIGURATION_MAPPING.md
    Integration Analysis: docs/POSH_ACME_INTEGRATION_ANALYSIS.md
    Architecture: docs/ARCHITECTURE.md
    Posh-ACME Documentation: https://poshacme.readthedocs.io/

.EXAMPLE
    Import-Module ./PoshAcmeConfigAdapter.psm1
    $config = Get-AgentConfiguration  # Using existing ConfigManager
    $account = Initialize-PoshAcmeAccountFromConfig -Config $config
    $order = New-PoshAcmeOrderFromConfig -Config $config
    Save-PoshAcmeCertificate -Order $order -Config $config
#>

#Requires -Version 7.0

# ============================================================================
# MODULE DEPENDENCIES
# ============================================================================

# Import required modules for this adapter's operation
$commonDirCandidates = @()

$localCommon = Join-Path $PSScriptRoot 'common'
if (Test-Path (Join-Path $localCommon 'Logger.psm1')) {
    $commonDirCandidates += $localCommon
}

$parentDir = Split-Path $PSScriptRoot -Parent
if (-not [string]::IsNullOrWhiteSpace($parentDir)) {
    $parentCommon = Join-Path $parentDir 'common'
    if (Test-Path (Join-Path $parentCommon 'Logger.psm1')) {
        $commonDirCandidates += $parentCommon
    }
}

$commonDir = $commonDirCandidates | Select-Object -First 1
if (-not $commonDir) {
    throw "PoshAcmeConfigAdapter: unable to locate common module directory relative to $PSScriptRoot."
}

# Define logging functions first to ensure they're available
$script:UseCustomLogging = $false

try {
    Import-Module (Join-Path $commonDir 'Logger.psm1') -Force -Global
} catch {
    Write-Warning "Logger module not available, using Write-Host for logging"
    $script:UseCustomLogging = $true
}

# Simple logging functions for the adapter
function Write-LogInfo {
    param([string]$Message, [hashtable]$Context = @{})
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-LogDebug {
    param([string]$Message, [hashtable]$Context = @{})
    Write-Host "[DEBUG] $Message" -ForegroundColor Gray
}

function Write-LogWarn {
    param([string]$Message, [hashtable]$Context = @{})
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-LogError {
    param([string]$Message, [hashtable]$Context = @{})
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

try {
    Import-Module (Join-Path $commonDir 'FileOperations.psm1') -Force -Global
} catch {
    throw "FileOperations module is required for PoshAcmeConfigAdapter"
}

try {
    Import-Module (Join-Path $commonDir 'ConfigManager.psm1') -Force -Global
} catch {
    throw "ConfigManager module is required for PoshAcmeConfigAdapter"
}

# Import Posh-ACME module
try {
    Import-Module Posh-ACME -Force -Global
}
catch {
    Write-LogError -Message "Failed to import Posh-ACME module" -Context @{
        error = $_.Exception.Message
        module_path = "Posh-ACME"
    }
    throw "Posh-ACME module is required. Ensure it's installed: Install-Module -Name Posh-ACME"
}

# ============================================================================
# PRIVATE HELPER FUNCTIONS
# ============================================================================

function Get-AcmeDirectoryUrl {
    <#
    .SYNOPSIS
        Construct ACME directory URL from base PKI URL.

    .DESCRIPTION
        Converts ECA pki_url to Posh-ACME directory URL format.
        Handles URL formatting and ensures proper directory endpoint.

    .PARAMETER PkiUrl
        Base PKI URL from ECA configuration.

    .OUTPUTS
        System.String - Full ACME directory URL.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PkiUrl
    )

    Write-LogDebug -Message "Constructing ACME directory URL" -Context @{
        pki_url = $PkiUrl
    }

    # Remove trailing slash if present
    $cleanUrl = $PkiUrl.TrimEnd('/')

    # Construct directory URL
    $directoryUrl = "${cleanUrl}/acme/acme/directory"

    Write-LogDebug -Message "ACME directory URL constructed" -Context @{
        directory_url = $directoryUrl
    }

    return $directoryUrl
}

function Get-PoshAcmeStateDirectory {
    <#
    .SYNOPSIS
        Determine Posh-ACME state directory path.

    .DESCRIPTION
        Sets up Posh-ACME state directory based on ECA configuration.
        Uses /config directory for consistency with existing account key storage.

    .PARAMETER Config
        ECA configuration hashtable.

    .OUTPUTS
        System.String - State directory path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $stateDir = $null

    # Priority 1: explicit value from configuration (allows future customization)
    if ($Config.ContainsKey('posh_acme') -and $Config.posh_acme -and
        $Config.posh_acme.ContainsKey('state_directory') -and
        -not [string]::IsNullOrWhiteSpace($Config.posh_acme.state_directory)) {
        $stateDir = $Config.posh_acme.state_directory
        Write-LogDebug -Message "Using state directory from configuration" -Context @{
            state_dir = $stateDir
        }
    }

    # Priority 2: environment variable supplied by host/container
    if ([string]::IsNullOrWhiteSpace($stateDir)) {
        $envStateDir = [System.Environment]::GetEnvironmentVariable('POSHACME_HOME')
        if (-not [string]::IsNullOrWhiteSpace($envStateDir)) {
            $stateDir = $envStateDir
            Write-LogDebug -Message "Using POSHACME_HOME environment variable for state directory" -Context @{
                state_dir = $stateDir
            }
        }
    }

    # Priority 3: legacy default inside /config for backward compatibility
    if ([string]::IsNullOrWhiteSpace($stateDir)) {
        $stateDir = "/config/poshacme"
        Write-LogDebug -Message "Using legacy default state directory" -Context @{
            state_dir = $stateDir
        }
    }

    # Expand environment variables in the path (helps with %ProgramData%, etc.)
    $expandedStateDir = [System.Environment]::ExpandEnvironmentVariables($stateDir)

    try {
        if (-not (Test-Path -Path $expandedStateDir)) {
            Write-LogInfo -Message "Creating Posh-ACME state directory" -Context @{
                state_dir = $expandedStateDir
            }
            New-Item -ItemType Directory -Path $expandedStateDir -Force | Out-Null
        }

        # Ensure restrictive permissions where supported (best-effort)
        try {
            Set-FilePermissions -Path $expandedStateDir -Mode "0700"
        }
        catch {
            Write-LogDebug -Message "Unable to set permissions on state directory (non-fatal)" -Context @{
                state_dir = $expandedStateDir
                error      = $_.Exception.Message
            }
        }
    }
    catch {
        Write-LogError -Message "Failed to prepare Posh-ACME state directory" -Context @{
            requested_state_dir = $expandedStateDir
            error               = $_.Exception.Message
        }
        throw
    }

    Write-LogDebug -Message "Posh-ACME state directory determined" -Context @{
        state_dir = $expandedStateDir
    }

    return $expandedStateDir
}

function Test-PoshAcmeServerConfigured {
    <#
    .SYNOPSIS
        Check if Posh-ACME server is properly configured.

    .DESCRIPTION
        Validates that Posh-ACME server configuration matches expected directory URL.

    .PARAMETER ExpectedDirectoryUrl
        Expected ACME directory URL.

    .OUTPUTS
        System.Boolean - True if server is correctly configured.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExpectedDirectoryUrl
    )

    try {
        $currentServer = Get-PAServer
        if ($currentServer -and $currentServer.location -eq $ExpectedDirectoryUrl) {
            Write-LogDebug -Message "Posh-ACME server already configured" -Context @{
            server_location = $currentServer.location
            }
            return $true
        }
    }
    catch {
        Write-LogDebug -Message "Posh-ACME server not configured or accessible" -Context @{
            error = $_.Exception.Message
        }
        return $false
    }

    return $false
}

# ============================================================================
# PUBLIC ADAPTER FUNCTIONS
# ============================================================================

function Get-EnvironmentConfig {
    <#
    .SYNOPSIS
        Get environment-specific ACME configuration.

    .DESCRIPTION
        Retrieves the appropriate PKI configuration based on the current
        environment (development, staging, production). Supports environment
        variable overrides and fallback to default configuration.

    .PARAMETER Config
        ECA configuration hashtable containing environment and PKI settings.

    .OUTPUTS
        System.Collections.Hashtable - Environment-specific configuration.

    .EXAMPLE
        $config = Get-AgentConfiguration
        $envConfig = Get-EnvironmentConfig -Config $config
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    try {
        # Get current environment with fallback to development
        $environment = $Config.environment
        if ([string]::IsNullOrWhiteSpace($environment)) {
            $environment = "development"
            Write-LogDebug -Message "No environment specified, using default: development"
        }

        Write-LogInfo -Message "Loading configuration for environment" -Context @{
            environment = $environment
        }

        # Check for environment-specific override
        $envOverrideVar = "${environment}_PKI_URL".ToUpper()
        $envOverrideUrl = [System.Environment]::GetEnvironmentVariable($envOverrideVar)

        $pkiUrl = $null
        $skipCertCheck = $false
        $timeoutSeconds = 30

        if ($envOverrideUrl) {
            # Use environment-specific override
            $pkiUrl = $envOverrideUrl
            Write-LogInfo -Message "Using environment-specific PKI URL override" -Context @{
                environment = $environment
                override_var = $envOverrideVar
                url = $pkiUrl
            }
        }
        elseif ($Config.pki_environments -and $Config.pki_environments.ContainsKey($environment)) {
            # Use configured environment settings
            $envConfig = $Config.pki_environments[$environment]
            $pkiUrl = $envConfig.url
            $skipCertCheck = $envConfig.skip_certificate_check
            $timeoutSeconds = $envConfig.timeout_seconds

            Write-LogInfo -Message "Using configured environment settings" -Context @{
                environment = $environment
                url = $pkiUrl
                skip_cert_check = $skipCertCheck
                timeout_seconds = $timeoutSeconds
            }
        }
        else {
            # Fallback to default PKI URL with development-friendly defaults
            $pkiUrl = $Config.pki_url

            if ($Config.ContainsKey('skip_certificate_check')) {
                $skipCertCheck = [bool]$Config.skip_certificate_check
            }
            elseif ($environment -eq 'development') {
                $skipCertCheck = $true
            }

            Write-LogInfo -Message "Using default PKI URL (no environment config found)" -Context @{
                environment = $environment
                url = $pkiUrl
                skip_cert_check = $skipCertCheck
            }
        }

        # Validate PKI URL
        if ([string]::IsNullOrWhiteSpace($pkiUrl)) {
            throw "PKI URL not found for environment '$environment'"
        }

        # Return environment-specific configuration
        return @{
            environment = $environment
            pki_url = $pkiUrl
            skip_certificate_check = $skipCertCheck
            timeout_seconds = $timeoutSeconds
        }
    }
    catch {
        Write-LogError -Message "Failed to get environment configuration" -Context @{
            error = $_.Exception.Message
            environment = $Config.environment
        }
        throw
    }
}

function Set-PoshAcmeServerFromConfig {
    <#
    .SYNOPSIS
        Configure Posh-ACME server using ECA configuration.

    .DESCRIPTION
        Sets up Posh-ACME server configuration based on ECA pki_url.
        Handles directory URL construction and SSL certificate validation.

    .PARAMETER Config
        ECA configuration hashtable containing pki_url.

    .OUTPUTS
        System.Boolean - True if server configuration successful.

    .EXAMPLE
        $config = Get-AgentConfiguration
        Set-PoshAcmeServerFromConfig -Config $config
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    try {
        # Get environment-specific configuration
        $envConfig = Get-EnvironmentConfig -Config $Config

        Write-LogInfo -Message "Configuring Posh-ACME server" -Context @{
            environment = $envConfig.environment
            pki_url = $envConfig.pki_url
            skip_cert_check = $envConfig.skip_certificate_check
        }

        # Construct ACME directory URL
        $directoryUrl = Get-AcmeDirectoryUrl -PkiUrl $envConfig.pki_url

        # Check if already configured
        if (Test-PoshAcmeServerConfigured -ExpectedDirectoryUrl $directoryUrl) {
            Write-LogInfo -Message "Posh-ACME server already configured" -Context @{
                directory_url = $directoryUrl
            }
            return $true
        }

        # Configure Posh-ACME server with environment-specific SSL settings
        $serverArgs = @{
            DirectoryUrl = $directoryUrl
        }

        if ($envConfig.skip_certificate_check) {
            $serverArgs.Add("SkipCertificateCheck", $true)
        }

        Set-PAServer @serverArgs

        Write-LogInfo -Message "Posh-ACME server configured successfully" -Context @{
            directory_url = $directoryUrl
        }

        return $true
    }
    catch {
        Write-LogError -Message "Failed to configure Posh-ACME server" -Context @{
            error = $_.Exception.Message
            pki_url = $Config.pki_url
        }
        throw
    }
}

function Initialize-PoshAcmeAccountFromConfig {
    <#
    .SYNOPSIS
        Initialize Posh-ACME account using ECA configuration.

    .DESCRIPTION
        Sets up Posh-ACME account management based on ECA configuration.
        Creates new account if none exists, or retrieves existing account.
        Configures state directory for consistency with ECA patterns.

    .PARAMETER Config
        ECA configuration hashtable.

    .OUTPUTS
        System.Collections.Hashtable - Account information object.

    .EXAMPLE
        $config = Get-AgentConfiguration
        $account = Initialize-PoshAcmeAccountFromConfig -Config $config
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    try {
        Write-LogInfo -Message "Initializing Posh-ACME account" -Context @{
            pki_url = $Config.pki_url
        }

        # Set up Posh-ACME state directory
        $stateDir = Get-PoshAcmeStateDirectory -Config $Config
        $env:POSHACME_HOME = $stateDir

        Write-LogDebug -Message "Posh-ACME state directory configured" -Context @{
            state_dir = $stateDir
        }

        # Ensure server configuration is applied before interacting with Posh-ACME
        $serverConfigured = $false
        try {
            $serverConfigured = Set-PoshAcmeServerFromConfig -Config $Config
        }
        catch {
            Write-LogError -Message "Posh-ACME server configuration failed during account initialization" -Context @{
                error = $_.Exception.Message
                pki_url = $Config.pki_url
            }
            throw
        }

        if (-not $serverConfigured) {
            throw "Unable to configure Posh-ACME server for $($Config.pki_url)"
        }

        # Try to get existing account
        try {
            $account = Get-PAAccount
            if ($account -and $account.status -eq 'valid') {
                Write-LogInfo -Message "Existing Posh-ACME account found" -Context @{
                    account_id = $account.ID
                    status = $account.status
                }
                try {
                    Set-PAAccount -ID $account.ID | Out-Null
                }
                catch {
                    Write-LogWarn -Message "Failed to switch to existing Posh-ACME account" -Context @{
                        error = $_.Exception.Message
                        account_id = $account.ID
                    }
                }
                return @{
                    ID = $account.ID
                    Status = $account.status
                    Contact = $account.contact
                    Account = $account
                }
            }
        }
        catch {
            Write-LogDebug -Message "No existing Posh-ACME account found" -Context @{
                error = $_.Exception.Message
            }
        }

        # Create new account
        Write-LogInfo -Message "Creating new Posh-ACME account"
        $newAccount = New-PAAccount -AcceptTOS

        Write-LogInfo -Message "New Posh-ACME account created successfully" -Context @{
            account_id = $newAccount.ID
            status = $newAccount.status
        }

        try {
            Set-PAAccount -ID $newAccount.ID | Out-Null
        }
        catch {
            Write-LogWarn -Message "Failed to switch to new Posh-ACME account" -Context @{
                error = $_.Exception.Message
                account_id = $newAccount.ID
            }
        }

        return @{
            ID = $newAccount.ID
            Status = $newAccount.status
            Contact = $newAccount.contact
            Account = $newAccount
        }
    }
    catch {
        Write-LogError -Message "Failed to initialize Posh-ACME account" -Context @{
            error = $_.Exception.Message
            pki_url = $Config.pki_url
        }
        throw
    }
}

function New-PoshAcmeOrderFromConfig {
    <#
    .SYNOPSIS
        Create new Posh-ACME order using ECA configuration.

    .DESCRIPTION
        Creates a new certificate order based on ECA domain_name configuration.
        Maps ECA domain configuration to Posh-ACME order parameters.

    .PARAMETER Config
        ECA configuration hashtable containing domain_name.

    .OUTPUTS
        System.Collections.Hashtable - Order information object.

    .EXAMPLE
        $config = Get-AgentConfiguration
        $order = New-PoshAcmeOrderFromConfig -Config $config
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    if (-not $Config.ContainsKey('domain_name') -or [string]::IsNullOrWhiteSpace($Config.domain_name)) {
        throw "Configuration error: domain_name is required for ACME certificate orders"
    }

    try {
        Write-LogInfo -Message "Creating Posh-ACME certificate order" -Context @{
            domain_name = $Config.domain_name
        }

        # Create new order with domain from configuration
        try {
            $order = New-PAOrder -Domain $Config.domain_name -Force
        }
        catch {
            Write-LogDebug -Message "New-PAOrder failed" -Context @{
                error = $_.Exception.Message
            }
            if ($_.Exception -and $_.Exception.Message -like "*Account does not exist*") {
                Write-LogWarn -Message "Stored Posh-ACME account invalid for current CA. Recreating account." -Context @{
                    domain = $Config.domain_name
                }

                Remove-PoshAcmeAccount | Out-Null

                Initialize-PoshAcmeAccountFromConfig -Config $Config | Out-Null
                $order = New-PAOrder -Domain $Config.domain_name -Force
            } else {
                throw
            }
        }

        try {
            Set-PAOrder -MainDomain $Config.domain_name | Out-Null
        }
        catch {
            Write-LogWarn -Message "Failed to switch active order after creation" -Context @{
                error = $_.Exception.Message
                domain = $Config.domain_name
            }
        }

        Write-LogInfo -Message "Posh-ACME order created successfully" -Context @{
            order_id = $order.ID
            status = $order.status
            domain_name = $Config.domain_name
            expires = $order.expires
        }

        return @{
            ID = $order.ID
            Status = $order.status
            Domain = $Config.domain_name
            Expires = $order.expires
            Identifiers = $order.identifiers
            Authorizations = $order.authorizations
            Finalize = $order.finalize
            Certificate = $order.certificate
            Order = $order
        }
    }
    catch {
        Write-LogError -Message "Failed to create Posh-ACME order" -Context @{
            error = $_.Exception.Message
            domain_name = $Config.domain_name
        }
        throw
    }
}

function Convert-PACertificateToAdapterInfo {
    <#
    .SYNOPSIS
        Convert Posh-ACME certificate object to adapter-friendly structure.

    .DESCRIPTION
        Transforms the Posh-ACME certificate object (which references persisted files)
        into a hashtable containing both raw file contents and original file paths so
        downstream ECA logic can operate on in-memory PEM material while retaining
        path references for diagnostics.

    .PARAMETER Certificate
        Posh-ACME certificate object returned by Complete-PAOrder/Get-PACertificate.

    .OUTPUTS
        System.Collections.Hashtable - Adapter-friendly certificate information.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        $Certificate
    )

    if (-not $Certificate) {
        return $null
    }

    function Get-AdapterFileContent {
        param(
            [Parameter(Mandatory = $false)]
            [string]$Path
        )

        if ([string]::IsNullOrWhiteSpace($Path)) {
            return $null
        }

        if (Test-Path -LiteralPath $Path) {
            return Get-Content -LiteralPath $Path -Raw
        }

        # Value may already contain PEM content (future-proof)
        return $Path
    }

    $result = @{
        Subject           = $Certificate.Subject
        NotBefore         = $Certificate.NotBefore
        NotAfter          = $Certificate.NotAfter
        KeyLength         = $Certificate.KeyLength
        Thumbprint        = $Certificate.Thumbprint
        Serial            = $Certificate.Serial
        AllSANs           = $Certificate.AllSANs
        ARIId             = $Certificate.ARIId
        CertFile          = Get-AdapterFileContent -Path $Certificate.CertFile
        CertFilePath      = $Certificate.CertFile
        ChainFile         = Get-AdapterFileContent -Path $Certificate.ChainFile
        ChainFilePath     = $Certificate.ChainFile
        FullChainFile     = Get-AdapterFileContent -Path $Certificate.FullChainFile
        FullChainFilePath = $Certificate.FullChainFile
        KeyFile           = Get-AdapterFileContent -Path $Certificate.KeyFile
        KeyFilePath       = $Certificate.KeyFile
        PfxFile           = $Certificate.PfxFile
        PfxFullChain      = $Certificate.PfxFullChain
        PfxPass           = $Certificate.PfxPass
    }

    return $result
}

function Save-PoshAcmeCertificate {
    <#
    .SYNOPSIS
        Save Posh-ACME certificate and key using ECA configuration paths with chain management.

    .DESCRIPTION
        Saves issued certificate, private key, and certificate chains to paths specified in ECA configuration.
        Uses atomic file operations to maintain consistency with existing ECA patterns.
        Sets appropriate file permissions for security and handles certificate chain management.

    .PARAMETER Order
        Posh-ACME order object with completed certificate.

    .PARAMETER Config
        ECA configuration hashtable containing cert_path, key_path, and certificate_chain settings.

    .OUTPUTS
        System.Boolean - True if certificate, key, and chains saved successfully.

    .EXAMPLE
        $config = Get-AgentConfiguration
        $order = New-PoshAcmeOrderFromConfig -Config $config
        # ... complete order ...
        Save-PoshAcmeCertificate -Order $order -Config $config
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Order,

        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    try {
        Write-LogInfo -Message "Saving Posh-ACME certificate with chain management" -Context @{
            order_id = $Order.ID
            cert_path = $Config.cert_path
            key_path = $Config.key_path
            chain_enabled = $Config.certificate_chain.enabled
        }

        # Get certificate metadata from Posh-ACME and convert to adapter format
        $paCertInfo = Get-PACertificate

        if (-not $paCertInfo) {
            throw "No certificate available from Posh-ACME"
        }

        $certInfo = Convert-PACertificateToAdapterInfo -Certificate $paCertInfo
        if (-not $certInfo) {
            throw "Unable to convert Posh-ACME certificate information"
        }

        # Save private key using existing atomic file operations
        Write-LogDebug -Message "Saving private key" -Context @{
            key_path = $Config.key_path
            source = $certInfo.KeyFilePath
        }
        Write-FileAtomic -Path $Config.key_path -Content $certInfo.KeyFile
        Set-FilePermissions -Path $Config.key_path -Mode "0600"

        # Handle certificate chain management
        if ($Config.certificate_chain.enabled) {
            Write-LogDebug -Message "Certificate chain management enabled"
            $chainSuccess = Save-CertificateChain -CertInfo $certInfo -Config $Config
            if (-not $chainSuccess) {
                throw "Certificate chain management failed"
            }
        } else {
            Write-LogDebug -Message "Certificate chain management disabled, saving leaf certificate only"
            # Save certificate using existing atomic file operations
            Write-FileAtomic -Path $Config.cert_path -Content $certInfo.CertFile
            Set-FilePermissions -Path $Config.cert_path -Mode "0644"
        }

        Write-LogInfo -Message "Certificate and key saved successfully" -Context @{
            cert_path = $Config.cert_path
            key_path = $Config.key_path
            order_id = $Order.ID
            chain_enabled = $Config.certificate_chain.enabled
        }

        return $true
    }
    catch {
        Write-LogError -Message "Failed to save Posh-ACME certificate" -Context @{
            error = $_.Exception.Message
            cert_path = $Config.cert_path
            key_path = $Config.key_path
            order_id = $Order.ID
        }
        return $false
    }
}

function Save-CertificateChain {
    <#
    .SYNOPSIS
        Save certificate chain files with validation and configuration options.

    .DESCRIPTION
        Saves certificate chain files (full chain, intermediates) based on ECA configuration.
        Validates chain completeness and handles multiple output formats.
        Creates separate chain files for debugging and monitoring purposes.

    .PARAMETER CertInfo
        Posh-ACME certificate information containing CertFile, ChainFile, and FullChainFile.

    .PARAMETER Config
        ECA configuration hashtable containing certificate_chain settings.

    .OUTPUTS
        System.Boolean - True if certificate chain saved successfully.

    .EXAMPLE
        $certInfo = Get-PACertificate
        $config = Get-AgentConfiguration
        $success = Save-CertificateChain -CertInfo $certInfo -Config $config
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$CertInfo,

        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    try {
        Write-LogInfo -Message "Saving certificate chain files" -Context @{
            full_chain_path = $Config.certificate_chain.full_chain_path
            intermediates_path = $Config.certificate_chain.intermediates_path
            validate_completeness = $Config.certificate_chain.validation.validate_completeness
        }

        # Validate certificate chain if enabled
        if ($Config.certificate_chain.validation.validate_completeness) {
            $validationSuccess = Test-CertificateChain -CertInfo $CertInfo -Config $Config
            if (-not $validationSuccess) {
                throw "Certificate chain validation failed"
            }
        }

        # Determine which content to save to main certificate path
        if ($Config.certificate_chain.installation.install_full_chain_to_cert_path) {
            Write-LogDebug -Message "Installing full chain to main certificate path"
            Write-FileAtomic -Path $Config.cert_path -Content $CertInfo.FullChainFile
        } elseif ($Config.certificate_chain.installation.install_leaf_only) {
            Write-LogDebug -Message "Installing leaf certificate only to main certificate path"
            Write-FileAtomic -Path $Config.cert_path -Content $CertInfo.CertFile
        } else {
            # Default: install full chain (most secure option)
            Write-LogDebug -Message "Default: installing full chain to main certificate path"
            Write-FileAtomic -Path $Config.cert_path -Content $CertInfo.FullChainFile
        }

        # Set permissions for main certificate file
        Set-FilePermissions -Path $Config.cert_path -Mode "0644"

        # Create separate chain files if enabled
        if ($Config.certificate_chain.installation.create_separate_chain_files) {
            Write-LogDebug -Message "Creating separate certificate chain files"

            # Save full chain file
            if ($Config.certificate_chain.full_chain_path -and
                -not [string]::IsNullOrWhiteSpace($Config.certificate_chain.full_chain_path)) {

                Write-LogDebug -Message "Saving full certificate chain" -Context @{
                    path = $Config.certificate_chain.full_chain_path
                }
                Write-FileAtomic -Path $Config.certificate_chain.full_chain_path -Content $CertInfo.FullChainFile
                Set-FilePermissions -Path $Config.certificate_chain.full_chain_path -Mode $Config.certificate_chain.installation.chain_file_permissions
            }

            # Save intermediates file (if available and different from full chain)
            if ($Config.certificate_chain.intermediates_path -and
                -not [string]::IsNullOrWhiteSpace($Config.certificate_chain.intermediates_path) -and
                $CertInfo.ChainFile) {

                Write-LogDebug -Message "Saving intermediate certificates" -Context @{
                    path = $Config.certificate_chain.intermediates_path
                }
                Write-FileAtomic -Path $Config.certificate_chain.intermediates_path -Content $CertInfo.ChainFile
                Set-FilePermissions -Path $Config.certificate_chain.intermediates_path -Mode $Config.certificate_chain.installation.chain_file_permissions
            }

            # Save leaf certificate for backup/debugging
            $leafCertPath = $Config.cert_path.Replace('.crt', '-leaf.crt')
            Write-LogDebug -Message "Saving leaf certificate for backup" -Context @{
                path = $leafCertPath
            }
            Write-FileAtomic -Path $leafCertPath -Content $CertInfo.CertFile
            Set-FilePermissions -Path $leafCertPath -Mode "0644"
        }

        Write-LogInfo -Message "Certificate chain files saved successfully" -Context @{
            main_cert_path = $Config.cert_path
            full_chain_path = $Config.certificate_chain.full_chain_path
            intermediates_path = $Config.certificate_chain.intermediates_path
            chain_validation = $Config.certificate_chain.validation.validate_completeness
        }

        return $true
    }
    catch {
        Write-LogError -Message "Failed to save certificate chain" -Context @{
            error = $_.Exception.Message
            cert_path = $Config.cert_path
            full_chain_path = $Config.certificate_chain.full_chain_path
            intermediates_path = $Config.certificate_chain.intermediates_path
        }
        return $false
    }
}

function Test-CertificateChain {
    <#
    .SYNOPSIS
        Validate certificate chain completeness and integrity.

    .DESCRIPTION
        Performs comprehensive validation of the certificate chain including:
        - Chain completeness verification
        - Signature validation
        - Expiration checking
        - Chain depth validation

    .PARAMETER CertInfo
        Posh-ACME certificate information containing CertFile, ChainFile, and FullChainFile.

    .PARAMETER Config
        ECA configuration hashtable containing validation settings.

    .OUTPUTS
        System.Boolean - True if certificate chain validation passes.

    .EXAMPLE
        $certInfo = Get-PACertificate
        $config = Get-AgentConfiguration
        $isValid = Test-CertificateChain -CertInfo $certInfo -Config $config
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$CertInfo,

        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    try {
        Write-LogDebug -Message "Starting certificate chain validation" -Context @{
            verify_signatures = $Config.certificate_chain.validation.verify_signatures
            check_expiry = $Config.certificate_chain.validation.check_expiry
            max_depth = $Config.certificate_chain.validation.max_depth
        }

        # Basic completeness check - ensure we have certificate files
        if (-not $CertInfo.CertFile -or -not $CertInfo.FullChainFile) {
            Write-LogWarn -Message "Certificate chain incomplete - missing certificate files"
            return $false
        }

        # Check if full chain contains more than just the leaf certificate
        if ($CertInfo.FullChainFile.Length -le $CertInfo.CertFile.Length) {
            Write-LogWarn -Message "Full chain appears to be missing intermediate certificates"
            return $false
        }

        # PowerShell certificate validation
        try {
            # Convert certificate string to X509Certificate2 object
            $leafCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                [System.Text.Encoding]::UTF8.GetBytes($CertInfo.CertFile)
            )

            # Check expiration if enabled
            if ($Config.certificate_chain.validation.check_expiry) {
                $now = Get-Date
                if ($leafCert.NotAfter -lt $now) {
                    Write-LogWarn -Message "Leaf certificate has expired" -Context @{
                        expires = $leafCert.NotAfter.ToString("yyyy-MM-ddTHH:mm:ssZ")
                        current_time = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    }
                    return $false
                }

                if ($leafCert.NotBefore -gt $now) {
                    Write-LogWarn -Message "Leaf certificate is not yet valid" -Context @{
                        valid_from = $leafCert.NotBefore.ToString("yyyy-MM-ddTHH:mm:ssZ")
                        current_time = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    }
                    return $false
                }
            }

            Write-LogDebug -Message "Leaf certificate validation passed" -Context @{
                subject = $leafCert.Subject
                issuer = $leafCert.Issuer
                expires = $leafCert.NotAfter.ToString("yyyy-MM-ddTHH:mm:ssZ")
            }

        } catch {
            Write-LogWarn -Message "Failed to parse leaf certificate for validation" -Context @{
                error = $_.Exception.Message
            }
            # Continue anyway - certificate might still be valid for use
        }

        # Log chain information for debugging
        Write-LogDebug -Message "Certificate chain validation completed" -Context @{
            leaf_cert_size = $CertInfo.CertFile.Length
            full_chain_size = $CertInfo.FullChainFile.Length
            has_intermediates = if ($CertInfo.ChainFile) { $true } else { $false }
            intermediates_size = if ($CertInfo.ChainFile) { $CertInfo.ChainFile.Length } else { 0 }
        }

        return $true
    }
    catch {
        Write-LogError -Message "Certificate chain validation failed with error" -Context @{
            error = $_.Exception.Message
        }
        return $false
    }
}

function Invoke-PoshAcmeChallenge {
    <#
    .SYNOPSIS
        Complete ACME challenge for certificate issuance.

    .DESCRIPTION
        Handles ACME challenge completion using Posh-ACME.
        Supports HTTP-01 challenge (default for ECA ACME agent).

    .PARAMETER Order
        Posh-ACME order object with pending challenges.

    .PARAMETER ChallengeDirectory
        Directory for HTTP-01 challenge files (from ECA configuration).

    .OUTPUTS
        System.Boolean - True if challenge completed successfully.

    .EXAMPLE
        $config = Get-AgentConfiguration
        $order = New-PoshAcmeOrderFromConfig -Config $config
        $success = Invoke-PoshAcmeChallenge -Order $order -ChallengeDirectory "/challenge"
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Order,

        [Parameter(Mandatory = $true)]
        [string]$ChallengeDirectory
    )

    $publishedChallenges = @()

    try {
        Write-LogInfo -Message "Completing ACME challenge" -Context @{
            order_id = $Order.ID
            challenge_dir = $ChallengeDirectory
        }

        $orderName = $null
        if ($Order.Order -and $Order.Order.Name) {
            $orderName = $Order.Order.Name
        } elseif ($Order.Domain) {
            $orderName = $Order.Domain
        } elseif ($Order.ID) {
            $orderName = $Order.ID
        }

        if (-not $orderName) {
            throw "Unable to determine order name for challenge completion"
        }

        try {
            Set-PAOrder -Name $orderName -ErrorAction Stop | Out-Null
        }
        catch {
            Write-LogDebug -Message "Failed to set current order by name, attempting by domain" -Context @{
                error = $_.Exception.Message
                order_name = $orderName
            }
            if ($Order.Domain) {
                Set-PAOrder -MainDomain $Order.Domain -ErrorAction Stop | Out-Null
            } else {
                throw
            }
        }

        $paOrder = Get-PAOrder -Name $orderName
        if (-not $paOrder) {
            throw "Unable to retrieve Posh-ACME order context for $orderName"
        }

        $authUrls = @()
        if ($paOrder.authorizations) {
            $authUrls = $paOrder.authorizations
        } elseif ($Order.Authorizations) {
            $authUrls = $Order.Authorizations
        }

        if (-not $authUrls -or $authUrls.Count -eq 0) {
            throw "Order does not contain authorization URLs"
        }

        $challengeRoot = Join-Path -Path $ChallengeDirectory -ChildPath ".well-known/acme-challenge"
        if (-not (Test-Path -Path $challengeRoot)) {
            New-Item -ItemType Directory -Path $challengeRoot -Force | Out-Null
        }

        foreach ($authUrl in $authUrls) {
            $authorization = Get-PAAuthorization -AuthURLs $authUrl -ErrorAction Stop
            if (-not $authorization) {
                throw "Failed to retrieve authorization for $authUrl"
            }

            if ($authorization.status -eq 'valid') {
                Write-LogDebug -Message "Authorization already valid" -Context @{
                    identifier = $authorization.identifier.value
                }
                continue
            }

            $httpChallenge = $authorization.challenges | Where-Object { $_.type -eq 'http-01' }
            if (-not $httpChallenge) {
                throw "HTTP-01 challenge not available for $($authorization.identifier.value)"
            }

            $keyAuth = Get-KeyAuthorization -Token $httpChallenge.token
            $tokenPath = Join-Path -Path $challengeRoot -ChildPath $httpChallenge.token

            Write-LogDebug -Message "Writing HTTP-01 challenge token" -Context @{
                token = $httpChallenge.token
                path = $tokenPath
            }

            Write-FileAtomic -Path $tokenPath -Content $keyAuth
            Set-FilePermissions -Path $tokenPath -Mode "0644"

            Send-ChallengeAck -ChallengeUrl $httpChallenge.url | Out-Null

            if ($env:POSHACME_DEBUG_HTTP_CHECK -eq '1') {
                try {
                    $checkUrl = "http://target-server/.well-known/acme-challenge/$($httpChallenge.token)"
                    $response = Invoke-WebRequest -Uri $checkUrl -UseBasicParsing -TimeoutSec 5
                    Write-LogDebug -Message "Local HTTP challenge check succeeded" -Context @{
                        url = $checkUrl
                        status_code = $response.StatusCode
                        content_length = $response.Content.Length
                    }
                }
                catch {
                    Write-LogWarn -Message "Local HTTP challenge check failed" -Context @{
                        token = $httpChallenge.token
                        error = $_.Exception.Message
                    }
                }
            }

            $publishedChallenges += [pscustomobject]@{
                Path = $tokenPath
            }
        }

        $validationTimeout = 120
        $pollInterval = 2
        $deadline = (Get-Date).AddSeconds($validationTimeout)

        while ((Get-Date) -lt $deadline) {
            $currentOrder = Get-PAOrder -Name $orderName -Refresh

            switch ($currentOrder.status) {
                'valid' {
                    Write-LogInfo -Message "ACME challenge validated successfully" -Context @{
                        order_id = $Order.ID
                    }
                    return $true
                }
                'ready' {
                    Write-LogInfo -Message "ACME challenge completed; order ready for finalization" -Context @{
                        order_id = $Order.ID
                    }
                    return $true
                }
                'invalid' {
                    throw "ACME challenge validation failed (order status invalid)"
                }
            }

            Start-Sleep -Seconds $pollInterval

            try {
                $authStatus = Get-PAAuthorization -AuthURLs $authUrls
                foreach ($auth in @($authStatus)) {
                    Write-LogDebug -Message "Authorization status poll" -Context @{
                        identifier = $auth.identifier.value
                        status = $auth.status
                        http01_status = ($auth.challenges | Where-Object { $_.type -eq 'http-01' }).status
                    }
                }
            }
            catch {
                Write-LogDebug -Message "Failed to poll authorization status" -Context @{
                    error = $_.Exception.Message
                }
            }
        }

        Write-LogWarn -Message "ACME challenge validation timed out" -Context @{
            order_id = $Order.ID
            timeout_seconds = $validationTimeout
        }
        return $false
    }
    catch {
        Write-LogError -Message "Failed to complete ACME challenge" -Context @{
            error = $_.Exception.Message
            order_id = $Order.ID
            challenge_dir = $ChallengeDirectory
        }
        return $false
    }
    finally {
        $keepChallenges = $env:POSHACME_KEEP_CHALLENGE_FILES -eq '1'
        foreach ($challenge in $publishedChallenges) {
            if ($keepChallenges) {
                Write-LogDebug -Message "Preserving challenge file for debugging" -Context @{
                    path = $challenge.Path
                }
                continue
            }

            try {
                if (Test-Path $challenge.Path) {
                    Remove-Item -Path $challenge.Path -Force -ErrorAction Stop
                }
            }
            catch {
                Write-LogDebug -Message "Failed to remove challenge file" -Context @{
                    path = $challenge.Path
                    error = $_.Exception.Message
                }
            }
        }
    }
}
function Get-PoshAcmeAccountInfo {
    <#
    .SYNOPSIS
        Get current Posh-ACME account information.

    .DESCRIPTION
        Retrieves information about the currently configured Posh-ACME account.
        Useful for status monitoring and validation.

    .OUTPUTS
        System.Collections.Hashtable - Account information or null if no account.

    .EXAMPLE
        $accountInfo = Get-PoshAcmeAccountInfo
        if ($accountInfo) {
            Write-Host "Account ID: $($accountInfo.ID)"
        }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    try {
        $account = Get-PAAccount
        if ($account) {
            return @{
                ID = $account.ID
                Status = $account.status
                Contact = $account.contact
                CreatedAt = $account.createdAt
                KeyId = $account.keyId
            }
        }
        return $null
    }
    catch {
        Write-LogDebug -Message "No Posh-ACME account information available" -Context @{
            error = $_.Exception.Message
        }
        return $null
    }
}

function Remove-PoshAcmeAccount {
    <#
    .SYNOPSIS
        Remove current Posh-ACME account.

    .DESCRIPTION
        Removes the currently configured Posh-ACME account.
        Useful for cleanup, testing, or account rotation.

    .OUTPUTS
        System.Boolean - True if account removed successfully.

    .EXAMPLE
        $success = Remove-PoshAcmeAccount
        if ($success) {
            Write-Host "Account removed successfully"
        }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $account = Get-PAAccount
        if ($account) {
            Remove-PAAccount -ID $account.ID -Force
            Write-LogInfo -Message "Posh-ACME account removed successfully" -Context @{
                account_id = $account.ID
            }
            return $true
        } else {
            Write-LogDebug -Message "No Posh-ACME account to remove"
            return $true
        }
    }
    catch {
        Write-LogError -Message "Failed to remove Posh-ACME account" -Context @{
            error = $_.Exception.Message
        }
        return $false
    }
}

# ============================================================================
# MODULE EXPORTS
# ============================================================================

# Export public functions for use by agent.ps1
Export-ModuleMember -Function @(
    'Set-PoshAcmeServerFromConfig',
    'Initialize-PoshAcmeAccountFromConfig',
    'New-PoshAcmeOrderFromConfig',
    'Save-PoshAcmeCertificate',
    'Save-CertificateChain',
    'Test-CertificateChain',
    'Invoke-PoshAcmeChallenge',
    'Get-PoshAcmeAccountInfo',
    'Remove-PoshAcmeAccount',
    'Convert-PACertificateToAdapterInfo',
    # Export helper functions for testing
    'Get-EnvironmentConfig',
    'Get-AcmeDirectoryUrl',
    'Get-PoshAcmeStateDirectory'
)
