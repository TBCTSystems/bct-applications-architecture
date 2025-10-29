<#
.SYNOPSIS
    Configuration management module for Edge Certificate Agent PoC.

.DESCRIPTION
    This module provides configuration loading and validation functionality for ACME and EST
    certificate agents. It supports:
    - Reading agent configuration from YAML files
    - Environment variable overrides (uppercase naming convention)
    - JSON Schema validation against config/agent_config_schema.json
    - Default value application for optional fields
    - Type conversion and format validation

    Configuration Precedence (highest to lowest):
    1. Environment variables (e.g., $env:PKI_URL overrides pki_url from YAML)
    2. YAML file values
    3. Schema default values (renewal_threshold_pct: 75, check_interval_sec: 60)

    Environment Variable Naming Convention:
    - YAML field names use snake_case (e.g., pki_url, cert_path)
    - Environment variable names use UPPER_SNAKE_CASE (e.g., PKI_URL, CERT_PATH)

    Supported Configuration Fields:
    - pki_url (required): Base URL of step-ca PKI API
    - cert_path (required): Filesystem path for certificate output
    - key_path (required): Filesystem path for private key output
    - domain_name (optional): Subject/SAN for certificate request
    - renewal_threshold_pct (optional, default: 75): Renewal trigger percentage
    - check_interval_sec (optional, default: 60): Check interval in seconds
    - bootstrap_token (optional, sensitive): One-time EST enrollment token
    - agent_id (optional): Unique identifier for logging

.NOTES
    Module Name: ConfigManager
    Author: Edge Certificate Agent Project
    Requires: PowerShell Core 7.0+
    Dependencies:
      - powershell-yaml module (for YAML parsing)
      - Logger module (for structured logging)
      - config/agent_config_schema.json (JSON Schema)

    Security Considerations:
    - bootstrap_token is SENSITIVE and must never appear in logs
    - All logging of configuration redacts sensitive fields
    - Configuration validation prevents injection of unknown fields

.EXAMPLE
    Import-Module ./agents/common/ConfigManager.psm1
    $config = Read-AgentConfig -ConfigFilePath "/config/agent.yaml"

.EXAMPLE
    $env:PKI_URL = "https://pki.example.com:9000"
    $config = Read-AgentConfig -ConfigFilePath "./config.yaml"
    # $config['pki_url'] will be "https://pki.example.com:9000" (from env var)

.EXAMPLE
    $config = @{pki_url='https://pki:9000'; cert_path='/certs/cert.pem'; key_path='/certs/key.pem'}
    $isValid = Test-ConfigValid -Config $config
    # Returns: $true

.LINK
    JSON Schema: config/agent_config_schema.json
    Architecture: docs/03_System_Structure_and_Data.md
#>

#Requires -Version 7.0

# Import Logger module for structured logging
Import-Module (Join-Path $PSScriptRoot 'Logger.psm1') -Force

# ============================================================================
# INTERNAL HELPER FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Internal helper - Redacts sensitive fields from configuration for safe logging.

.DESCRIPTION
    Creates a shallow copy of the configuration hashtable with sensitive fields
    (tokens, passwords) replaced with '***REDACTED***' to prevent accidental
    exposure in logs.

.PARAMETER Config
    The configuration hashtable to redact.

.OUTPUTS
    System.Collections.Hashtable - Redacted copy safe for logging.
#>
function Get-RedactedConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $redacted = @{}
    foreach ($key in $Config.Keys) {
        # Redact any field containing 'token', 'password', 'secret', or 'key' (except key_path, cert_path)
        if ($key -match '(token|password|secret)' -and $key -notmatch '(_path|_url)') {
            $redacted[$key] = '***REDACTED***'
        }
        else {
            $redacted[$key] = $Config[$key]
        }
    }
    return $redacted
}

<#
.SYNOPSIS
    Internal helper - Merges environment variables into configuration hashtable.

.DESCRIPTION
    Checks for environment variables matching configuration field names (using
    UPPER_SNAKE_CASE convention) and overrides YAML values with environment values.
    Handles type conversion for integer fields.

.PARAMETER Config
    The configuration hashtable to merge environment variables into (modified in-place).

.PARAMETER EnvPrefixes
    Optional. Array of environment-variable prefixes to evaluate in order of precedence.
    Each prefix is concatenated directly with the upper snake-case name (e.g.,
    prefix "ACME_" + "PKI_URL" => "ACME_PKI_URL"). An empty string represents the
    legacy, non-prefixed environment variable name. The first prefix that supplies
    a value wins.

.OUTPUTS
    None - Modifies $Config hashtable in-place.
#>
function Merge-ConfigWithEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter(Mandatory = $false)]
        [string[]]$EnvPrefixes = @("")
    )

    if ($EnvPrefixes.Count -eq 0) {
        $EnvPrefixes = @("")
    }

    # Mapping of YAML field names (snake_case) to environment variable names (UPPER_SNAKE_CASE)
    $envMappings = @{
        'agent_name'                       = 'AGENT_NAME'
        'pki_url'                          = 'PKI_URL'
        'cert_path'                        = 'CERT_PATH'
        'key_path'                         = 'KEY_PATH'
        'domain_name'                      = 'DOMAIN_NAME'
        'device_name'                      = 'DEVICE_NAME'
        'renewal_threshold_pct'            = 'RENEWAL_THRESHOLD_PCT'
        'check_interval_sec'               = 'CHECK_INTERVAL_SEC'
        'bootstrap_token'                  = 'BOOTSTRAP_TOKEN'
        'agent_id'                         = 'AGENT_ID'
        'challenge_directory'              = 'CHALLENGE_DIRECTORY'
        'acme_account_contact_email'       = 'ACME_ACCOUNT_CONTACT_EMAIL'
        'acme_directory_path'              = 'ACME_DIRECTORY_PATH'
        'acme_certificate_key_type'        = 'ACME_CERTIFICATE_KEY_TYPE'
        'acme_certificate_key_size'        = 'ACME_CERTIFICATE_KEY_SIZE'
        'service_reload_container_name'    = 'SERVICE_RELOAD_CONTAINER_NAME'
        'service_reload_timeout_seconds'   = 'SERVICE_RELOAD_TIMEOUT_SECONDS'
    }

    foreach ($configKey in $envMappings.Keys) {
        $envVar = $envMappings[$configKey]
        foreach ($prefix in $EnvPrefixes) {
            $envVarName = if ([string]::IsNullOrWhiteSpace($prefix)) {
                $envVar
            }
            else {
                "$prefix$envVar"
            }

            $envValue = [System.Environment]::GetEnvironmentVariable($envVarName)

            if (-not [string]::IsNullOrWhiteSpace($envValue)) {
                $Config[$configKey] = $envValue

                # Log override (redact sensitive fields)
                if ($configKey -match 'token') {
                    Write-LogDebug -Message "Environment variable override applied" -Context @{
                        field   = $configKey
                        env_var = $envVarName
                        value   = '***REDACTED***'
                    }
                }
                else {
                    Write-LogDebug -Message "Environment variable override applied" -Context @{
                        field   = $configKey
                        env_var = $envVarName
                        value   = $envValue
                    }
                }

                break
            }
        }
    }

    # Type conversion for integer fields (environment variables are always strings)
    if ($Config.ContainsKey('renewal_threshold_pct') -and $Config['renewal_threshold_pct'] -is [string]) {
        try {
            $Config['renewal_threshold_pct'] = [int]$Config['renewal_threshold_pct']
        }
        catch {
            throw "Configuration error: Field 'renewal_threshold_pct' must be an integer (got: '$($Config['renewal_threshold_pct'])')"
        }
    }

    if ($Config.ContainsKey('check_interval_sec') -and $Config['check_interval_sec'] -is [string]) {
        try {
            $Config['check_interval_sec'] = [int]$Config['check_interval_sec']
        }
        catch {
            throw "Configuration error: Field 'check_interval_sec' must be an integer (got: '$($Config['check_interval_sec'])')"
        }
    }

    if ($Config.ContainsKey('acme_certificate_key_size') -and $Config['acme_certificate_key_size'] -is [string]) {
        try {
            $Config['acme_certificate_key_size'] = [int]$Config['acme_certificate_key_size']
        }
        catch {
            throw "Configuration error: Field 'acme_certificate_key_size' must be an integer (got: '$($Config['acme_certificate_key_size'])')"
        }
    }

    if ($Config.ContainsKey('service_reload_timeout_seconds') -and $Config['service_reload_timeout_seconds'] -is [string]) {
        try {
            $Config['service_reload_timeout_seconds'] = [int]$Config['service_reload_timeout_seconds']
        }
        catch {
            throw "Configuration error: Field 'service_reload_timeout_seconds' must be an integer (got: '$($Config['service_reload_timeout_seconds'])')"
        }
    }
}

<#
.SYNOPSIS
    Internal helper - Applies default values for optional configuration fields.

.DESCRIPTION
    Applies schema-defined default values for optional fields that are not present
    in the configuration. Default values:
    - renewal_threshold_pct: 75
    - check_interval_sec: 60

.PARAMETER Config
    The configuration hashtable to apply defaults to (modified in-place).

.OUTPUTS
    None - Modifies $Config hashtable in-place.
#>
function Apply-ConfigDefaults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    # Apply default for renewal_threshold_pct
    if (-not $Config.ContainsKey('renewal_threshold_pct')) {
        $Config['renewal_threshold_pct'] = 75
        Write-LogDebug -Message "Applied default value" -Context @{
            field = 'renewal_threshold_pct'
            value = 75
        }
    }

    # Apply default for check_interval_sec
    if (-not $Config.ContainsKey('check_interval_sec')) {
        $Config['check_interval_sec'] = 60
        Write-LogDebug -Message "Applied default value" -Context @{
            field = 'check_interval_sec'
            value = 60
        }
    }
}

<#
.SYNOPSIS
    Internal helper - Validates configuration hashtable against JSON Schema rules.

.DESCRIPTION
    Implements manual JSON Schema validation since PowerShell lacks a native validator.
    Validates:
    - Required field presence
    - Field types (string, integer)
    - Format validation (URI for pki_url)
    - Range validation (renewal_threshold_pct: 1-100, check_interval_sec: >=1)
    - Additional properties check (no unknown fields)

.PARAMETER Config
    The configuration hashtable to validate.

.PARAMETER SchemaPath
    Path to the JSON Schema file.

.OUTPUTS
    None - Throws descriptive exception if validation fails.
#>
function Invoke-SchemaValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter(Mandatory = $true)]
        [string]$SchemaPath
    )

    # Load and parse JSON Schema
    if (-not (Test-Path -Path $SchemaPath -PathType Leaf)) {
        Write-LogError -Message "JSON Schema file not found" -Context @{path = $SchemaPath}
        throw "JSON Schema file not found: $SchemaPath"
    }

    try {
        $schemaContent = Get-Content -Path $SchemaPath -Raw
        $schema = $schemaContent | ConvertFrom-Json
    }
    catch {
        Write-LogError -Message "Failed to parse JSON Schema" -Context @{
            path  = $SchemaPath
            error = $_.Exception.Message
        }
        throw "Failed to parse JSON Schema from '$SchemaPath': $($_.Exception.Message)"
    }

    # 1. Validate required fields
    foreach ($requiredField in $schema.required) {
        if (-not $Config.ContainsKey($requiredField)) {
            $errorMsg = "Configuration validation failed: Required field '$requiredField' is missing"
            Write-LogError -Message $errorMsg -Context @{field = $requiredField}
            throw $errorMsg
        }

        # Check for null or empty string values
        $value = $Config[$requiredField]
        if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value))) {
            $errorMsg = "Configuration validation failed: Required field '$requiredField' is null or empty"
            Write-LogError -Message $errorMsg -Context @{field = $requiredField; value = $value}
            throw $errorMsg
        }
    }

    # 2. Validate pki_url is a valid URI
    if ($Config.ContainsKey('pki_url')) {
        $pki_url = $Config['pki_url']
        $uri = $null
        if (-not [System.Uri]::TryCreate($pki_url, [System.UriKind]::Absolute, [ref]$uri)) {
            $errorMsg = "Configuration validation failed: Field 'pki_url' must be a valid absolute URI (got: '$pki_url')"
            Write-LogError -Message $errorMsg -Context @{field = 'pki_url'; value = $pki_url}
            throw $errorMsg
        }
    }

    # 3. Validate renewal_threshold_pct range (1-100)
    if ($Config.ContainsKey('renewal_threshold_pct')) {
        $threshold = $Config['renewal_threshold_pct']

        # Type check
        if ($threshold -isnot [int]) {
            $errorMsg = "Configuration validation failed: Field 'renewal_threshold_pct' must be an integer (got: $($threshold.GetType().Name))"
            Write-LogError -Message $errorMsg -Context @{field = 'renewal_threshold_pct'; value = $threshold; type = $threshold.GetType().Name}
            throw $errorMsg
        }

        # Range check
        if ($threshold -lt 1 -or $threshold -gt 100) {
            $errorMsg = "Configuration validation failed: Field 'renewal_threshold_pct' must be between 1 and 100 (got: $threshold)"
            Write-LogError -Message $errorMsg -Context @{field = 'renewal_threshold_pct'; value = $threshold; constraint = '1-100'}
            throw $errorMsg
        }
    }

    # 4. Validate check_interval_sec is positive integer
    if ($Config.ContainsKey('check_interval_sec')) {
        $interval = $Config['check_interval_sec']

        # Type check
        if ($interval -isnot [int]) {
            $errorMsg = "Configuration validation failed: Field 'check_interval_sec' must be an integer (got: $($interval.GetType().Name))"
            Write-LogError -Message $errorMsg -Context @{field = 'check_interval_sec'; value = $interval; type = $interval.GetType().Name}
            throw $errorMsg
        }

        # Range check
        if ($interval -lt 1) {
            $errorMsg = "Configuration validation failed: Field 'check_interval_sec' must be >= 1 (got: $interval)"
            Write-LogError -Message $errorMsg -Context @{field = 'check_interval_sec'; value = $interval; constraint = '>=1'}
            throw $errorMsg
        }
    }

    # 5. Validate cert_path and key_path are non-empty strings (minLength: 1)
    foreach ($pathField in @('cert_path', 'key_path')) {
        if ($Config.ContainsKey($pathField)) {
            $pathValue = $Config[$pathField]
            if ($pathValue -isnot [string] -or [string]::IsNullOrWhiteSpace($pathValue)) {
                $errorMsg = "Configuration validation failed: Field '$pathField' must be a non-empty string"
                Write-LogError -Message $errorMsg -Context @{field = $pathField; value = $pathValue}
                throw $errorMsg
            }
        }
    }

    # 6. Check for additional properties (schema has "additionalProperties": false)
    $allowedKeys = $schema.properties.PSObject.Properties.Name
    foreach ($key in $Config.Keys) {
        if ($key -notin $allowedKeys) {
            $errorMsg = "Configuration validation failed: Unknown field '$key' (not defined in schema)"
            Write-LogError -Message $errorMsg -Context @{field = $key; allowed_fields = ($allowedKeys -join ', ')}
            throw $errorMsg
        }
    }

    Write-LogDebug -Message "Configuration validated successfully against JSON Schema" -Context @{
        schema_path   = $SchemaPath
        field_count   = $Config.Count
        required_met  = $schema.required.Count
    }
}

# ============================================================================
# PUBLIC FUNCTIONS
# ============================================================================

function Read-AgentConfig {
    <#
    .SYNOPSIS
        Loads and validates agent configuration from YAML file with environment variable overrides.

    .DESCRIPTION
        Reads agent configuration from a YAML file, merges with environment variables (which take
        precedence over YAML values), applies default values for optional fields, and validates
        against the JSON Schema. Returns a validated configuration hashtable ready for use by agents.

        Configuration Precedence (highest to lowest):
        1. Prefixed environment variables (e.g., $env:ACME_PKI_URL when EnvVarPrefixes = @("ACME_"))
        2. Legacy/unprefixed environment variables (e.g., $env:PKI_URL)
        3. YAML file values
        4. Schema default values (renewal_threshold_pct: 75, check_interval_sec: 60)

        Environment Variable Naming Convention:
        - pki_url → $env:PKI_URL
        - cert_path → $env:CERT_PATH
        - key_path → $env:KEY_PATH
        - domain_name → $env:DOMAIN_NAME
        - renewal_threshold_pct → $env:RENEWAL_THRESHOLD_PCT
        - check_interval_sec → $env:CHECK_INTERVAL_SEC
        - bootstrap_token → $env:BOOTSTRAP_TOKEN
        - agent_id → $env:AGENT_ID

.PARAMETER ConfigFilePath
        Absolute or relative path to the YAML configuration file.

.PARAMETER EnvVarPrefixes
        Optional array of prefixes to probe when reading environment overrides. Pass the agent
        specific prefix (e.g., @("ACME_", "")) to ensure overrides remain namespaced per agent.

    .OUTPUTS
        System.Collections.Hashtable
        Returns a validated configuration hashtable with all fields type-converted and defaults applied.

    .EXAMPLE
        $config = Read-AgentConfig -ConfigFilePath "/config/agent.yaml"

    .EXAMPLE
        $env:PKI_URL = "https://pki.example.com:9000"
        $config = Read-AgentConfig -ConfigFilePath "./config.yaml"
        # $config['pki_url'] will be "https://pki.example.com:9000" (from env var)

    .EXAMPLE
        $env:RENEWAL_THRESHOLD_PCT = "80"
        $config = Read-AgentConfig -ConfigFilePath "/config/acme-agent.yaml"
        # $config['renewal_threshold_pct'] will be 80 (integer, converted from string)

    .NOTES
        Throws an exception if:
        - Configuration file not found
        - YAML parsing fails (malformed YAML)
        - Validation fails (missing required fields, invalid values, unknown fields)

        Security: bootstrap_token values are redacted in all log messages.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$ConfigFilePath,

        [Parameter(Mandatory = $false)]
        [string[]]$EnvVarPrefixes = @("")
    )

    Write-LogInfo -Message "Loading agent configuration" -Context @{path = $ConfigFilePath}

    # 1. Verify configuration file exists
    if (-not (Test-Path -Path $ConfigFilePath -PathType Leaf)) {
        Write-LogError -Message "Configuration file not found" -Context @{path = $ConfigFilePath}
        throw "Configuration file not found: $ConfigFilePath"
    }

    # 2. Read and parse YAML file
    try {
        $yamlContent = Get-Content -Path $ConfigFilePath -Raw
        $configObject = ConvertFrom-Yaml -Yaml $yamlContent

        # Convert PSCustomObject to Hashtable for easier manipulation
        if ($configObject -is [System.Collections.IDictionary]) {
            $config = @{}
            foreach ($key in $configObject.Keys) {
                $config[$key] = $configObject[$key]
            }
        }
        elseif ($configObject -is [PSCustomObject]) {
            $config = @{}
            foreach ($property in $configObject.PSObject.Properties) {
                $config[$property.Name] = $property.Value
            }
        }
        else {
            throw "Unexpected YAML parse result type: $($configObject.GetType().Name)"
        }

        Write-LogDebug -Message "YAML file parsed successfully" -Context @{
            path        = $ConfigFilePath
            field_count = $config.Count
        }
    }
    catch {
        Write-LogError -Message "YAML parsing failed" -Context @{
            path  = $ConfigFilePath
            error = $_.Exception.Message
        }
        throw "Failed to parse YAML configuration from '$ConfigFilePath': $($_.Exception.Message)"
    }

    # 3. Build environment variable prefix list
    # Priority order:
    #   1. Explicit EnvVarPrefixes parameter (caller-provided)
    #   2. agent_name from config file (enables multi-instance deployments)
    #   3. Unprefixed fallback (legacy mode)

    $prefixList = @()

    # Use explicit prefixes if provided
    if ($EnvVarPrefixes -and $EnvVarPrefixes.Count -gt 0 -and $EnvVarPrefixes[0] -ne "") {
        $prefixList += $EnvVarPrefixes
        Write-LogDebug -Message "Using explicit environment variable prefixes" -Context @{
            prefixes = ($EnvVarPrefixes -join ", ")
            source = "EnvVarPrefixes parameter"
        }
    }
    # Otherwise derive prefix from agent_name in config file
    elseif ($config.ContainsKey('agent_name') -and -not [string]::IsNullOrWhiteSpace($config.agent_name)) {
        $agentName = $config.agent_name
        # Replace hyphens with underscores (env vars can't contain hyphens)
        # e.g., "acme-app1" becomes "ACME_APP1_"
        $derivedPrefix = ($agentName -replace '-', '_').ToUpper() + '_'
        $prefixList += $derivedPrefix

        Write-LogInfo -Message "Environment variable prefix derived from config" -Context @{
            agent_name = $agentName
            prefix = $derivedPrefix
            source = "agent_name field in config file"
        }
    }
    else {
        Write-LogWarn -Message "No environment variable prefix configured - using legacy unprefixed mode" -Context @{
            warning = "Multiple agent instances on same host may experience config collisions"
            recommendation = "Add 'agent_name' field to config file for multi-instance deployments"
            see_docs = "docs/WINDOWS_DEPLOYMENT.md"
        }
    }

    # Always include unprefixed fallback for backward compatibility
    if (-not ($prefixList | Where-Object { $_ -eq "" })) {
        $prefixList += ""
    }

    # 4. Merge with environment variables (overrides YAML values)
    Merge-ConfigWithEnvironment -Config $config -EnvPrefixes $prefixList

    # 4. Apply default values for optional fields
    Apply-ConfigDefaults -Config $config

    # 5. Validate configuration against JSON Schema
    # Use absolute path for schema file (Docker container layout)
    $schemaPath = '/config/agent_config_schema.json'
    try {
        Invoke-SchemaValidation -Config $config -SchemaPath $schemaPath
    }
    catch {
        # Re-throw validation errors (already logged by Invoke-SchemaValidation)
        throw
    }

    # 6. Log success with redacted configuration
    $redactedConfig = Get-RedactedConfig -Config $config
    Write-LogInfo -Message "Configuration loaded successfully" -Context @{
        path   = $ConfigFilePath
        config = ($redactedConfig | ConvertTo-Json -Compress)
    }

    return $config
}

function Test-ConfigValid {
    <#
    .SYNOPSIS
        Validates a configuration hashtable against the agent configuration JSON Schema.

    .DESCRIPTION
        Performs comprehensive validation of agent configuration including:
        - Required field presence checks (pki_url, cert_path, key_path)
        - Type validation (strings, integers)
        - Format validation (URI format for pki_url)
        - Range validation (renewal_threshold_pct: 1-100, check_interval_sec: >=1)
        - String constraints (minLength: 1 for path fields)
        - Additional properties check (no unknown fields)

        This function throws descriptive exceptions for validation failures with field names
        and constraint violations clearly identified.

    .PARAMETER Config
        The configuration hashtable to validate.

    .PARAMETER SchemaPath
        Optional. Path to the JSON Schema file. Defaults to config/agent_config_schema.json
        relative to the module's parent directory.

    .OUTPUTS
        System.Boolean
        Returns $true if validation passes. Throws an exception if validation fails.

    .EXAMPLE
        $config = @{pki_url='https://pki:9000'; cert_path='/certs/cert.pem'; key_path='/certs/key.pem'}
        $isValid = Test-ConfigValid -Config $config
        # Returns: $true

    .EXAMPLE
        $config = @{pki_url='invalid-uri'; cert_path='/certs/cert.pem'}
        Test-ConfigValid -Config $config
        # Throws: Configuration validation failed: Required field 'key_path' is missing

    .EXAMPLE
        $config = @{pki_url='https://pki:9000'; cert_path='/c.pem'; key_path='/k.pem'; renewal_threshold_pct=150}
        Test-ConfigValid -Config $config
        # Throws: Configuration validation failed: Field 'renewal_threshold_pct' must be between 1 and 100 (got: 150)

    .NOTES
        Acceptance Criteria:
        - Validates config hashtable against JSON schema
        - Returns boolean ($true on success)
        - Invalid configuration throws descriptive error with field name and constraint violation
        - Default schema path: config/agent_config_schema.json
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNull()]
        [hashtable]$Config,

        [Parameter(Mandatory = $false)]
        [string]$SchemaPath
    )

    # Default schema path if not provided
    if ([string]::IsNullOrWhiteSpace($SchemaPath)) {
        # Use absolute path for schema file (Docker container layout)
        $SchemaPath = '/config/agent_config_schema.json'
    }

    Write-LogDebug -Message "Validating configuration against schema" -Context @{
        schema_path = $SchemaPath
        field_count = $Config.Count
    }

    # Perform validation (throws on failure)
    Invoke-SchemaValidation -Config $Config -SchemaPath $SchemaPath

    Write-LogInfo -Message "Configuration validation passed" -Context @{field_count = $Config.Count}

    return $true
}

# Export only the public functions
Export-ModuleMember -Function Read-AgentConfig, Test-ConfigValid
