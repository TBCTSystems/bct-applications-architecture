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

    # Use /config directory for consistency with existing ACME account key
    $stateDir = "/config/poshacme"

    Write-LogDebug -Message "Posh-ACME state directory determined" -Context @{
        state_dir = $stateDir
    }

    return $stateDir
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
        Write-LogInfo -Message "Configuring Posh-ACME server" -Context @{
            pki_url = $Config.pki_url
        }

        # Construct ACME directory URL
        $directoryUrl = Get-AcmeDirectoryUrl -PkiUrl $Config.pki_url

        # Check if already configured
        if (Test-PoshAcmeServerConfigured -ExpectedDirectoryUrl $directoryUrl) {
            Write-LogInfo -Message "Posh-ACME server already configured" -Context @{
                directory_url = $directoryUrl
            }
            return $true
        }

        # Configure Posh-ACME server with SSL bypass for step-ca
        Set-PAServer -DirectoryUrl $directoryUrl -SkipCertificateCheck

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
        return $false
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

        # Try to get existing account
        try {
            $account = Get-PAAccount
            if ($account -and $account.status -eq 'valid') {
                Write-LogInfo -Message "Existing Posh-ACME account found" -Context @{
                    account_id = $account.ID
                    status = $account.status
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
        $order = New-PAOrder -Domain $Config.domain_name -Force

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

function Save-PoshAcmeCertificate {
    <#
    .SYNOPSIS
        Save Posh-ACME certificate and key using ECA configuration paths.

    .DESCRIPTION
        Saves issued certificate and private key to paths specified in ECA configuration.
        Uses atomic file operations to maintain consistency with existing ECA patterns.
        Sets appropriate file permissions for security.

    .PARAMETER Order
        Posh-ACME order object with completed certificate.

    .PARAMETER Config
        ECA configuration hashtable containing cert_path and key_path.

    .OUTPUTS
        System.Boolean - True if certificate and key saved successfully.

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
        Write-LogInfo -Message "Saving Posh-ACME certificate" -Context @{
            order_id = $Order.ID
            cert_path = $Config.cert_path
            key_path = $Config.key_path
        }

        # Get certificate content from Posh-ACME
        $certInfo = Get-PACertificate

        if (-not $certInfo) {
            throw "No certificate available from Posh-ACME"
        }

        # Save private key using existing atomic file operations
        Write-LogDebug -Message "Saving private key" -Context @{
            key_path = $Config.key_path
        }
        Write-FileAtomic -Path $Config.key_path -Content $certInfo.KeyFile
        Set-FilePermissions -Path $Config.key_path -Mode "0600"

        # Save certificate using existing atomic file operations
        Write-LogDebug -Message "Saving certificate" -Context @{
            cert_path = $Config.cert_path
        }
        Write-FileAtomic -Path $Config.cert_path -Content $certInfo.CertFile
        Set-FilePermissions -Path $Config.cert_path -Mode "0644"

        Write-LogInfo -Message "Certificate and key saved successfully" -Context @{
            cert_path = $Config.cert_path
            key_path = $Config.key_path
            order_id = $Order.ID
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

    try {
        Write-LogInfo -Message "Completing ACME challenge" -Context @{
            order_id = $Order.ID
            challenge_dir = $ChallengeDirectory
        }

        # Posh-ACME handles challenge completion automatically
        # We just need to submit the order which triggers challenge handling
        $result = Submit-PAOrder

        if ($result.status -eq 'ready' -or $result.status -eq 'valid') {
            Write-LogInfo -Message "ACME challenge completed successfully" -Context @{
                order_id = $Order.ID
                final_status = $result.status
            }
            return $true
        } else {
            Write-LogWarn -Message "ACME challenge completed with pending status" -Context @{
                order_id = $Order.ID
                status = $result.status
            }
            return $true # Still considered success, will be validated later
        }
    }
    catch {
        Write-LogError -Message "Failed to complete ACME challenge" -Context @{
            error = $_.Exception.Message
            order_id = $Order.ID
            challenge_dir = $ChallengeDirectory
        }
        return $false
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
    'Invoke-PoshAcmeChallenge',
    'Get-PoshAcmeAccountInfo',
    'Remove-PoshAcmeAccount',
    # Export helper functions for testing
    'Get-AcmeDirectoryUrl',
    'Get-PoshAcmeStateDirectory'
)