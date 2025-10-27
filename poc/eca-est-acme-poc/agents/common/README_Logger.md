# Logger Module

Structured logging module for the Edge Certificate Agent (ECA) PoC project.

## Overview

`Logger.psm1` provides a PowerShell logging framework with support for:
- **JSON format**: Machine-readable structured logs for parsing and aggregation
- **Console format**: Human-readable color-coded logs for development and debugging

## Quick Start

```powershell
# Import the module
Import-Module ./agents/common/Logger.psm1

# Basic usage
Write-LogInfo -Message "Certificate check complete"

# With context
Write-LogInfo -Message "Certificate renewal triggered" -Context @{
    domain = "target-server"
    lifetime_elapsed_pct = 80
    threshold_pct = 75
}
```

## Output Formats

### Console Format (Default)

Color-coded human-readable format:

```powershell
$env:LOG_FORMAT = "console"  # or leave unset
Write-LogInfo -Message "Certificate renewal triggered" -Context @{domain="target-server"}
```

**Output:**
```
[2025-10-24T10:03:45Z] INFO: Certificate renewal triggered (domain=target-server)
```

**Color Scheme:**
- **INFO**: Cyan
- **WARN**: Yellow
- **ERROR**: Red
- **DEBUG**: Gray

### JSON Format

Structured JSON output for log aggregation tools:

```powershell
$env:LOG_FORMAT = "json"
Write-LogInfo -Message "Certificate renewal triggered" -Context @{
    domain = "target-server"
    lifetime_elapsed_pct = 80
}
```

**Output:**
```json
{"timestamp":"2025-10-24T10:03:45Z","severity":"INFO","message":"Certificate renewal triggered","context":{"domain":"target-server","lifetime_elapsed_pct":80}}
```

## Functions

### Write-LogInfo

Logs informational messages for normal lifecycle events.

```powershell
Write-LogInfo -Message "ACME order created successfully"
Write-LogInfo -Message "Certificate installed" -Context @{path="/certs/server/cert.pem"}
```

### Write-LogWarn

Logs warning messages for recoverable errors.

```powershell
Write-LogWarn -Message "Transient network failure" -Context @{retry_attempt=1}
Write-LogWarn -Message "Certificate expires soon" -Context @{days_remaining=7}
```

### Write-LogError

Logs error messages for non-recoverable errors.

```powershell
Write-LogError -Message "Invalid configuration" -Context @{field="pki_url"; error="Invalid URI"}
Write-LogError -Message "Certificate installation failed" -Context @{path="/certs/server"; error="Permission denied"}
```

### Write-LogDebug

Logs detailed debug information for troubleshooting.

```powershell
Write-LogDebug -Message "ACME HTTP request sent" -Context @{
    method = "POST"
    url = "https://pki.local/acme/new-order"
    status_code = 201
}
```

## Environment Variables

| Variable | Values | Default | Description |
|----------|--------|---------|-------------|
| `LOG_FORMAT` | `json`, `console` | `console` | Controls output format |

**Setting in Docker Compose:**

```yaml
environment:
  LOG_FORMAT: ${LOG_FORMAT:-console}
```

**Setting in Shell:**

```bash
export LOG_FORMAT=json
pwsh -Command 'Import-Module ./agents/common/Logger.psm1; Write-LogInfo -Message "Test"'
```

## Log Entry Structure

All log entries include:

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | string | ISO 8601 UTC timestamp (e.g., `2025-10-24T10:03:45Z`) |
| `severity` | string | Log level: `INFO`, `WARN`, `ERROR`, `DEBUG` |
| `message` | string | Human-readable log message |
| `context` | object | Optional key-value pairs with additional context |

## Architecture Integration

The Logger module is designed for Docker-based deployments:

- **Output Destination**: stdout/stderr (captured by `docker logs`)
- **Format Selection**: Environment variable `LOG_FORMAT`
- **Usage Pattern**: Called by all agent components (ACME client, certificate monitor, etc.)

### Docker Integration Example

```dockerfile
# Dockerfile for ECA-ACME agent
FROM mcr.microsoft.com/powershell:7.4-alpine

COPY agents/common/Logger.psm1 /app/agents/common/
ENV LOG_FORMAT=json

CMD ["pwsh", "-File", "/app/agents/acme/Agent.ps1"]
```

### Agent Usage Example

```powershell
# agents/acme/Agent.ps1
Import-Module /app/agents/common/Logger.psm1

Write-LogInfo -Message "Agent started" -Context @{version="1.0.0"}

# Main loop
while ($true) {
    try {
        # Certificate check logic
        Write-LogDebug -Message "Checking certificate" -Context @{path="/certs/server/cert.pem"}

        # Renewal decision
        Write-LogInfo -Message "Renewal triggered" -Context @{reason="threshold_exceeded"}

    } catch {
        Write-LogError -Message "Agent loop failed" -Context @{error=$_.Exception.Message}
    }

    Start-Sleep -Seconds 60
}
```

## Best Practices

### ✅ DO

- Use structured context for machine-readable data
- Log lifecycle events at INFO level
- Log recoverable errors at WARN level
- Log non-recoverable errors at ERROR level
- Use DEBUG for protocol-level details
- Include relevant context (certificate serial, domain, etc.)

### ❌ DON'T

- **NEVER** log sensitive data (private keys, passwords, tokens)
- Don't log in tight loops (causes log spam)
- Don't use Write-Host directly (use Logger functions)
- Don't mix logging formats in same application

### Security

**CRITICAL**: This module does NOT perform automatic redaction of sensitive data. Callers are responsible for ensuring that:
- Private keys are never passed in messages or context
- Authentication tokens are never logged
- Passwords and secrets are redacted

## Testing

### Manual Testing

```powershell
# Test console format
$env:LOG_FORMAT = "console"
Import-Module ./agents/common/Logger.psm1

Write-LogInfo -Message "Test info"
Write-LogWarn -Message "Test warning" -Context @{test="value"}
Write-LogError -Message "Test error"
Write-LogDebug -Message "Test debug"

# Test JSON format
$env:LOG_FORMAT = "json"
Import-Module ./agents/common/Logger.psm1 -Force

Write-LogInfo -Message "Test info" -Context @{key1="value1"; key2=42}
```

### PSScriptAnalyzer Validation

```powershell
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
Invoke-ScriptAnalyzer -Path agents/common/Logger.psm1 -Severity Error
```

Expected: No errors (warnings acceptable)

## Acceptance Criteria

✅ Module file exists at `agents/common/Logger.psm1`
✅ PSScriptAnalyzer reports no errors (warnings acceptable)
✅ All four functions (Info, Warn, Error, Debug) implemented and exported
✅ Console format includes color coding (Info: Cyan, Warn: Yellow, Error: Red, Debug: Gray)
✅ JSON format outputs valid JSON with fields: timestamp, severity, message, context
✅ Timestamp format: ISO 8601 (e.g., "2025-10-24T10:15:30Z")
✅ Context hashtable correctly serialized in both formats
✅ Environment variable LOG_FORMAT controls output format

## Version History

- **1.0.0** (2025-10-24): Initial implementation
  - Four severity levels (INFO, WARN, ERROR, DEBUG)
  - Two output formats (JSON, Console)
  - ISO 8601 UTC timestamps
  - Color-coded console output
  - Environment variable configuration
  - Comprehensive documentation

## See Also

- Architecture: `docs/05_Operational_Architecture.md` (Section 3.8.2: Logging & Monitoring)
- Component Diagram: `docs/03_System_Structure_and_Data.md` (Section 3.5: Logger Component)
- Docker Compose: `docker-compose.yml` (LOG_FORMAT configuration)
