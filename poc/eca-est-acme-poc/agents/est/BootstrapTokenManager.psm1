<#
.SYNOPSIS
    Bootstrap token management module for EST enrollment.

.DESCRIPTION
    This module provides secure loading and validation of EST bootstrap tokens used for
    initial certificate enrollment. Bootstrap tokens are shared secrets that authenticate
    devices during their first enrollment when they do not yet have a client certificate.

    Features:
    - Loads tokens from environment variables or configuration files
    - Validates token format and minimum security requirements
    - Automatic token redaction in all log messages (prevents credential leakage)
    - Supports configuration precedence (environment > config file)

    Security Considerations:
    - Token values are NEVER logged in plain text (always redacted)
    - Tokens must meet minimum length requirements (16 characters)
    - Tokens must use safe character sets (alphanumeric or base64)
    - Environment variable: EST_BOOTSTRAP_TOKEN

.NOTES
    Module Name: BootstrapTokenManager
    Author: Edge Certificate Agent Project
    Requires: PowerShell Core 7.0+
    Dependencies:
      - Logger module (for structured logging)

    SECURITY WARNING: Bootstrap tokens are sensitive credentials. This module automatically
    redacts token values in all log messages. Token values are shown as "***REDACTED***" or
    with partial masking (e.g., "facto-***-12345").

.EXAMPLE
    Import-Module ./agents/est/BootstrapTokenManager.psm1
    $token = Get-BootstrapToken
    # Returns token from $env:EST_BOOTSTRAP_TOKEN or config

.EXAMPLE
    $config = @{bootstrap_token = 'factory-secret-token-12345'}
    $token = Get-BootstrapToken -Config $config
    # Returns: 'factory-secret-token-12345'

.EXAMPLE
    $token = 'factory-secret-token-12345'
    $isValid = Test-BootstrapTokenValid -Token $token
    # Returns: $true

.LINK
    EST Protocol Reference: docs/api/est_protocol_reference.md (Section 2.1)
    Architecture: docs/01_Purpose_and_Constraints.md
#>

#Requires -Version 7.0

# Resolve shared module directory (container: /agent/common, repo: agents/common)
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
    throw "BootstrapTokenManager: unable to locate common module directory relative to $PSScriptRoot."
}

# Import Logger module for structured logging
Import-Module (Join-Path $commonDir 'Logger.psm1') -Force -Global

# Environment prefix detection (allows namespaced env vars per agent)
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

function Get-TokenEnvPrefixList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$DefaultPrefix = "EST_"
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

function Get-TokenEnvValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    foreach ($prefix in $script:TokenEnvPrefixes) {
        $envVarName = if ([string]::IsNullOrWhiteSpace($prefix)) { $Name } else { "$prefix$Name" }
        $value = [System.Environment]::GetEnvironmentVariable($envVarName)

        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return [PSCustomObject]@{
                Value  = $value
                EnvVar = $envVarName
            }
        }
    }

    return $null
}

$script:TokenEnvPrefixes = Get-TokenEnvPrefixList -DefaultPrefix "EST_"

# ============================================================================
# INTERNAL HELPER FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Internal helper - Redacts bootstrap token for safe logging.

.DESCRIPTION
    Creates a redacted representation of a bootstrap token showing only the first
    and last few characters with asterisks in the middle. This prevents credential
    leakage in logs while still providing diagnostic value.

.PARAMETER Token
    The bootstrap token to redact.

.OUTPUTS
    System.String - Redacted token string (e.g., "facto-***-12345").

.EXAMPLE
    Get-RedactedToken -Token "factory-secret-token-12345"
    # Returns: "facto-***-12345"
#>
function Get-RedactedToken {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Token
    )

    # Handle null or empty tokens
    if ([string]::IsNullOrEmpty($Token)) {
        return '***REDACTED***'
    }

    # For tokens shorter than 10 characters, fully redact
    if ($Token.Length -lt 10) {
        return '***REDACTED***'
    }

    # Show first 5 and last 5 characters with asterisks in middle
    $prefix = $Token.Substring(0, [Math]::Min(5, $Token.Length))
    $suffix = $Token.Substring($Token.Length - 5)
    return "$prefix-***-$suffix"
}

# ============================================================================
# PUBLIC FUNCTIONS
# ============================================================================

function Get-BootstrapToken {
    <#
    .SYNOPSIS
        Retrieves the EST bootstrap token from environment variable or configuration.

    .DESCRIPTION
        Loads the bootstrap token using the following precedence (highest to lowest):
        1. Environment variable: $env:EST_BOOTSTRAP_TOKEN (supports agent-specific prefixes such as "<agent>_EST_BOOTSTRAP_TOKEN")
        2. Configuration hashtable: bootstrap_token field (from pre-loaded config)

        The bootstrap token is a shared secret used for initial EST enrollment when the
        client does not yet have a certificate. This function implements secure token
        retrieval with automatic redaction in log messages.

    .PARAMETER Config
        Optional. Pre-loaded configuration hashtable containing bootstrap_token field.
        This should be the configuration loaded by ConfigManager's Read-AgentConfig function.

    .OUTPUTS
        System.String
        Returns the bootstrap token string if found.

    .EXAMPLE
        $env:EST_BOOTSTRAP_TOKEN = 'factory-secret-token-12345'
        $token = Get-BootstrapToken
        # Returns: 'factory-secret-token-12345'

    .EXAMPLE
        $config = @{bootstrap_token = 'config-file-token-67890'}
        $token = Get-BootstrapToken -Config $config
        # Returns: 'config-file-token-67890' (if EST_BOOTSTRAP_TOKEN not set)

    .EXAMPLE
        Get-BootstrapToken
        # Throws: "Bootstrap token not configured. Set EST_BOOTSTRAP_TOKEN..."

    .NOTES
        Throws an exception if the bootstrap token is not found in either the environment
        variable or the configuration hashtable. The calling code (EST agent) must handle
        this exception appropriately.

        Security: Token values are NEVER logged in plain text. All log messages use
        redacted token representations.

        Acceptance Criteria:
        - Checks $env:EST_BOOTSTRAP_TOKEN first (highest priority)
        - Checks bootstrap_token field from Config parameter second
        - Returns token string if found
        - Throws descriptive exception if token not found
        - Logs success with redacted token value
        - Logs error with redacted token value
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [hashtable]$Config = @{}
    )

    # Priority 1: Check environment variable (highest priority)
    $envTokenInfo = Get-TokenEnvValue -Name 'EST_BOOTSTRAP_TOKEN'
    if ($envTokenInfo -ne $null -and -not [string]::IsNullOrWhiteSpace($envTokenInfo.Value)) {
        Write-LogInfo -Message "Bootstrap token loaded successfully" -Context @{
            source = 'environment variable'
            variable = $envTokenInfo.EnvVar
            token = (Get-RedactedToken -Token $envTokenInfo.Value)
        }
        return $envTokenInfo.Value
    }

    # Priority 2: Check configuration hashtable
    if ($Config.ContainsKey('bootstrap_token') -and -not [string]::IsNullOrWhiteSpace($Config['bootstrap_token'])) {
        $configToken = $Config['bootstrap_token']
        Write-LogInfo -Message "Bootstrap token loaded successfully" -Context @{
            source = 'configuration file'
            field = 'bootstrap_token'
            token = (Get-RedactedToken -Token $configToken)
        }
        return $configToken
    }

    # No token found - throw error
    $errorMessage = "Bootstrap token not configured. Set EST_BOOTSTRAP_TOKEN environment variable or configure bootstrap_token in config file."
    Write-LogError -Message "Bootstrap token not found" -Context @{
        checked_env_var = 'EST_BOOTSTRAP_TOKEN'
        checked_config_field = 'bootstrap_token'
        error = $errorMessage
    }
    throw $errorMessage
}

function Test-BootstrapTokenValid {
    <#
    .SYNOPSIS
        Validates a bootstrap token against security requirements.

    .DESCRIPTION
        Performs comprehensive validation of bootstrap tokens to ensure they meet
        minimum security requirements:
        - Token is not null or empty string
        - Token meets minimum length requirement (16 characters)
        - Token contains only safe characters (alphanumeric or base64 character set)

        This function returns a boolean value and logs validation failures for
        troubleshooting. It does NOT throw exceptions - validation results are
        returned as true/false.

    .PARAMETER Token
        The bootstrap token string to validate. This parameter is required.

    .OUTPUTS
        System.Boolean
        Returns $true if token passes all validation checks.
        Returns $false if token fails any validation check.

    .EXAMPLE
        $token = 'factory-secret-token-12345'
        $isValid = Test-BootstrapTokenValid -Token $token
        # Returns: $true

    .EXAMPLE
        $token = 'short'
        $isValid = Test-BootstrapTokenValid -Token $token
        # Returns: $false (length < 16 characters)

    .EXAMPLE
        $token = 'base64-encoded-token+/=='
        $isValid = Test-BootstrapTokenValid -Token $token
        # Returns: $true (base64 characters allowed)

    .EXAMPLE
        $token = 'invalid-token-with-special-chars-$$$'
        $isValid = Test-BootstrapTokenValid -Token $token
        # Returns: $false (contains invalid characters)

    .NOTES
        Validation Rules:
        - Minimum length: 16 characters (recommended for security)
        - Allowed character set: [A-Za-z0-9+/=_-] (alphanumeric + base64 characters)
        - Empty/null tokens are invalid

        Security: Token values are redacted in all log messages to prevent credential
        leakage during validation failures.

        Acceptance Criteria:
        - Validates token is non-empty string
        - Validates minimum length (16 characters)
        - Validates token matches alphanumeric or base64 pattern
        - Returns boolean ($true or $false)
        - Logs validation failures with redacted token value
        - Never logs actual token value in plain text
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Token
    )

    # Validation 1: Check for null or empty string
    if ([string]::IsNullOrEmpty($Token)) {
        Write-LogWarn -Message "Bootstrap token validation failed: Token is null or empty" -Context @{
            validation_rule = 'non_empty'
            token = (Get-RedactedToken -Token $Token)
        }
        return $false
    }

    # Validation 2: Check minimum length (16 characters for security)
    $minLength = 16
    if ($Token.Length -lt $minLength) {
        Write-LogWarn -Message "Bootstrap token validation failed: Token length below minimum" -Context @{
            validation_rule = 'min_length'
            token = (Get-RedactedToken -Token $Token)
            actual_length = $Token.Length
            required_length = $minLength
        }
        return $false
    }

    # Validation 3: Check character set (alphanumeric or base64 pattern)
    # Base64 uses: A-Z, a-z, 0-9, +, /, =
    # Also allow common token separators: -, _
    $tokenPattern = '^[A-Za-z0-9+/=_-]+$'
    if ($Token -notmatch $tokenPattern) {
        Write-LogWarn -Message "Bootstrap token validation failed: Token contains invalid characters" -Context @{
            validation_rule = 'character_set'
            token = (Get-RedactedToken -Token $Token)
            expected_pattern = 'alphanumeric or base64 ([A-Za-z0-9+/=_-])'
        }
        return $false
    }

    # All validations passed
    Write-LogDebug -Message "Bootstrap token validation passed" -Context @{
        token = (Get-RedactedToken -Token $Token)
        length = $Token.Length
    }
    return $true
}

# Export only the public functions
Export-ModuleMember -Function Get-BootstrapToken, Test-BootstrapTokenValid
