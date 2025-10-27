<#
.SYNOPSIS
    Structured logging module for Edge Certificate Agent PoC.

.DESCRIPTION
    This module provides structured logging functionality with support for both
    JSON output (machine-readable) and color-coded console output (human-readable).

    The output format is controlled by the LOG_FORMAT environment variable:
    - "json": Outputs structured JSON logs to stdout
    - "console": Outputs color-coded formatted logs to console (default)

    All log entries include:
    - Timestamp in ISO 8601 UTC format
    - Severity level (INFO, WARN, ERROR, DEBUG)
    - Message string
    - Optional context hashtable with additional key-value pairs

.NOTES
    Version: 1.0.0
    Author: Edge Certificate Agent Project

    SECURITY WARNING: Do NOT pass sensitive data (private keys, passwords, tokens)
    in the message or context parameters. This module does not perform automatic
    redaction of sensitive information.

.EXAMPLE
    Import-Module ./agents/common/Logger.psm1
    Write-LogInfo -Message "Certificate renewal triggered" -Context @{domain="example.com"}

.EXAMPLE
    $env:LOG_FORMAT = "json"
    Import-Module ./agents/common/Logger.psm1
    Write-LogError -Message "Failed to connect to PKI" -Context @{url="https://pki.local"; error="Timeout"}
#>

#Requires -Version 7.0

# Internal helper function - not exported
function Write-LogEntry {
    <#
    .SYNOPSIS
        Internal helper function that handles log formatting and output.

    .DESCRIPTION
        This function is called by all public logging functions (Write-LogInfo, etc.)
        and handles the core logic for format detection, timestamp generation, and
        output formatting.

    .PARAMETER Severity
        The severity level of the log entry (INFO, WARN, ERROR, DEBUG).

    .PARAMETER Message
        The log message string.

    .PARAMETER Context
        Optional hashtable containing additional context key-value pairs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Severity,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [hashtable]$Context = @{}
    )

    # Generate ISO 8601 UTC timestamp
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    # Detect log format from environment variable, default to console
    $logFormat = $env:LOG_FORMAT
    if ([string]::IsNullOrWhiteSpace($logFormat)) {
        $logFormat = "console"
    }

    # Validate format and fallback to console if invalid
    if ($logFormat -notin @("json", "console")) {
        $logFormat = "console"
    }

    # Output based on selected format
    if ($logFormat -eq "json") {
        # Build structured log entry
        $logEntry = [ordered]@{
            timestamp = $timestamp
            severity  = $severity
            message   = $Message
            context   = $Context
        }

        # Convert to compressed JSON and output to stdout
        # NOTE: Using Write-Host instead of Write-Output to prevent log pollution in function return values
        # Write-Output adds to the return value pipeline, which causes issues when functions log and return values
        $jsonOutput = $logEntry | ConvertTo-Json -Compress -Depth 3
        Write-Host $jsonOutput
    }
    else {
        # Console format with color coding

        # Define color mapping
        $colorMap = @{
            'INFO'  = [ConsoleColor]::Cyan
            'WARN'  = [ConsoleColor]::Yellow
            'ERROR' = [ConsoleColor]::Red
            'DEBUG' = [ConsoleColor]::Gray
        }

        $color = $colorMap[$Severity]

        # Build console message
        $consoleMessage = "[$timestamp] $Severity`: $Message"

        # Append context if provided
        if ($Context.Count -gt 0) {
            $contextPairs = $Context.GetEnumerator() | ForEach-Object {
                "$($_.Key)=$($_.Value)"
            }
            $contextString = $contextPairs -join ", "
            $consoleMessage += " ($contextString)"
        }

        # Output with color coding
        Write-Host $consoleMessage -ForegroundColor $color
    }
}

function Write-LogInfo {
    <#
    .SYNOPSIS
        Writes an informational log entry.

    .DESCRIPTION
        Logs informational messages for normal lifecycle events such as
        certificate checks, renewal triggers, and successful operations.

    .PARAMETER Message
        The log message string. This parameter is required.

    .PARAMETER Context
        Optional hashtable containing additional context information as key-value pairs.
        Example: @{domain="example.com"; lifetime_elapsed_pct=80}

    .EXAMPLE
        Write-LogInfo -Message "Certificate check complete"

    .EXAMPLE
        Write-LogInfo -Message "Certificate renewal triggered" -Context @{
            domain = "target-server"
            lifetime_elapsed_pct = 80
            threshold_pct = 75
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $false, Position = 1)]
        [hashtable]$Context = @{}
    )

    Write-LogEntry -Severity 'INFO' -Message $Message -Context $Context
}

function Write-LogWarn {
    <#
    .SYNOPSIS
        Writes a warning log entry.

    .DESCRIPTION
        Logs warning messages for recoverable errors such as transient network
        failures, retry attempts, or degraded conditions.

    .PARAMETER Message
        The log message string. This parameter is required.

    .PARAMETER Context
        Optional hashtable containing additional context information as key-value pairs.
        Example: @{retry_attempt=1; error="Connection timeout"}

    .EXAMPLE
        Write-LogWarn -Message "Transient network failure"

    .EXAMPLE
        Write-LogWarn -Message "Retry attempt" -Context @{
            retry_attempt = 1
            max_retries = 3
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $false, Position = 1)]
        [hashtable]$Context = @{}
    )

    Write-LogEntry -Severity 'WARN' -Message $Message -Context $Context
}

function Write-LogError {
    <#
    .SYNOPSIS
        Writes an error log entry.

    .DESCRIPTION
        Logs error messages for non-recoverable errors such as invalid configuration,
        persistent failures, or critical issues that prevent normal operation.

    .PARAMETER Message
        The log message string. This parameter is required.

    .PARAMETER Context
        Optional hashtable containing additional context information as key-value pairs.
        Example: @{field="pki_url"; error="Invalid URI format"}

    .EXAMPLE
        Write-LogError -Message "Invalid configuration"

    .EXAMPLE
        Write-LogError -Message "Certificate installation failed" -Context @{
            path = "/certs/server/cert.pem"
            error = "Permission denied"
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $false, Position = 1)]
        [hashtable]$Context = @{}
    )

    Write-LogEntry -Severity 'ERROR' -Message $Message -Context $Context
}

function Write-LogDebug {
    <#
    .SYNOPSIS
        Writes a debug log entry.

    .DESCRIPTION
        Logs detailed debug messages for protocol-level details such as HTTP
        requests/responses, CSR content, or detailed state information useful
        for troubleshooting.

    .PARAMETER Message
        The log message string. This parameter is required.

    .PARAMETER Context
        Optional hashtable containing additional context information as key-value pairs.
        Example: @{order_id="abc123"; status="pending"}

    .EXAMPLE
        Write-LogDebug -Message "ACME order created"

    .EXAMPLE
        Write-LogDebug -Message "HTTP request sent" -Context @{
            method = "POST"
            url = "https://pki.local/acme/new-order"
            status_code = 201
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $false, Position = 1)]
        [hashtable]$Context = @{}
    )

    Write-LogEntry -Severity 'DEBUG' -Message $Message -Context $Context
}

# Export only the public functions
Export-ModuleMember -Function Write-LogInfo, Write-LogWarn, Write-LogError, Write-LogDebug
