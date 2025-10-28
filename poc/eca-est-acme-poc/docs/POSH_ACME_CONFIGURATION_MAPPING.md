# Posh-ACME Configuration Mapping Analysis

## Overview

This document maps our current ECA-ACME configuration structure to Posh-ACME parameters and defines the adapter pattern needed for seamless integration.

## Current Configuration Structure Analysis

### Primary Configuration Fields

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `pki_url` | string | ✅ | - | Step-ca base URL |
| `cert_path` | string | ✅ | - | Certificate output path |
| `key_path` | string | ✅ | - | Private key output path |
| `domain_name` | string | ❌ | - | Domain for certificate (CN/SAN) |
| `renewal_threshold_pct` | integer | ❌ | 75 | Renewal trigger percentage |
| `check_interval_sec` | integer | ❌ | 60 | Polling interval in seconds |

### CRL Configuration (Nested Object)

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `crl.enabled` | boolean | ❌ | false | Enable CRL validation |
| `crl.url` | string | ❌ | - | CRL download URL |
| `crl.cache_path` | string | ❌ | - | Local CRL cache path |
| `crl.max_age_hours` | number | ❌ | 24.0 | CRL cache max age |
| `crl.check_before_renewal` | boolean | ❌ | true | Check CRL before renewal |

### Environment Variable Override System

- **Prefix Support**: `AGENT_ENV_PREFIX` or `AGENT_NAME` for namespacing
- **Precedence**: Prefixed → Unprefixed → YAML → Schema defaults
- **Current Examples**: `ACME_PKI_URL`, `ACME_DOMAIN_NAME`, etc.

## Posh-ACME Parameter Mapping

### Core Posh-ACME Server Configuration

| Current Field | Posh-ACME Parameter | Mapping Strategy | Notes |
|---------------|--------------------|------------------|-------|
| `pki_url` | `-DirectoryUrl` in `Set-PAServer` | Direct mapping with `/acme/acme/directory` suffix | Convert base URL to directory URL |
| N/A | `-SkipCertificateCheck` | Always `true` for step-ca self-signed certs | Hardcoded for step-ca compatibility |

### Account Management

| Current Field | Posh-ACME Parameter | Mapping Strategy | Notes |
|---------------|--------------------|------------------|-------|
| N/A | `New-PAAccount` | Auto-create account | Handle account lifecycle internally |
| N/A | `Get-PAAccount` | Retrieve account info | For status and validation |
| N/A | `Remove-PAAccount` | Account cleanup | For testing/maintenance |

### Certificate Order Configuration

| Current Field | Posh-ACME Parameter | Mapping Strategy | Notes |
|---------------|--------------------|------------------|-------|
| `domain_name` | `-Domain` in `New-PAOrder` | Direct mapping | Single domain for ACME agent |
| N/A | `-KeyLength` | Default `2048` | RSA key length |
| N/A | `-AlwaysNewKey` | `$true` | Generate new key each renewal |
| N/A | `-Force` | Always `true` | Skip confirmation prompts |

### File Output Management

| Current Field | Posh-ACME Parameter | Mapping Strategy | Notes |
|---------------|--------------------|------------------|-------|
| `cert_path` | Custom file management | Manual file operations | Posh-ACME doesn't handle file paths |
| `key_path` | Custom file management | Manual file operations | Use atomic file operations |

### Renewal Logic (Custom Implementation)

| Current Field | Posh-ACME Parameter | Mapping Strategy | Notes |
|---------------|--------------------|------------------|-------|
| `renewal_threshold_pct` | Custom renewal logic | Maintain current logic | Posh-ACME doesn't provide this |
| `check_interval_sec` | Custom polling logic | Maintain current loop | Posh-ACME doesn't provide this |

### CRL Configuration (Maintain Current)

| Current Field | Posh-ACME Parameter | Mapping Strategy | Notes |
|---------------|--------------------|------------------|-------|
| `crl.*` | Custom CRL handling | Maintain current implementation | Posh-ACME doesn't provide CRL validation |

## Configuration Adapter Design

### Adapter Module: `PoshAcmeConfigAdapter.psm1`

#### Purpose
- Map ECA configuration to Posh-ACME parameters
- Maintain backward compatibility with existing YAML structure
- Handle environment variable overrides with existing prefixing system
- Provide Posh-ACME server setup and account management

#### Core Functions

```powershell
# Initialize Posh-ACME server configuration
function Set-PoshAcmeServerFromConfig {
    param([hashtable]$Config)
    # Set-PAServer -DirectoryUrl $Config.pki_url/acme/acme/directory -SkipCertificateCheck
}

# Create or retrieve ACME account
function Initialize-PoshAcmeAccount {
    param([hashtable]$Config)
    # Handle account lifecycle automatically
}

# Create certificate order from configuration
function New-PoshAcmeOrderFromConfig {
    param([hashtable]$Config)
    # New-PAOrder -Domain $Config.domain_name -Force
}

# Save certificate and key using ECA paths
function Save-PoshAcmeCertificate {
    param([object]$Certificate, [hashtable]$Config)
    # Use existing FileOperations.psm1 for atomic writes
}
```

#### Configuration Processing Flow

1. **Load Configuration**: Use existing ConfigManager.psm1
2. **Apply Overrides**: Existing environment variable system preserved
3. **Validate Schema**: Existing JSON schema validation maintained
4. **Initialize Posh-ACME**: Set server and account
5. **Execute Operations**: Use Posh-ACME cmdlets with mapped parameters
6. **Save Results**: Use existing file operations for certificate/key output

### Backward Compatibility Strategy

#### Existing Interface Preservation
- **YAML Configuration**: No changes required
- **Environment Variables**: No changes required
- **Agent Script**: Minimal changes - replace ACME calls with adapter calls
- **File Operations**: Maintain existing atomic file operations
- **Logging**: Maintain existing structured logging format

#### Migration Path
1. **Phase 1**: Adapter module created, existing interface preserved
2. **Phase 2**: Agent script gradually updated to use adapter
3. **Phase 3**: Custom AcmeClient.psm1 removed
4. **Phase 4**: Enhanced capabilities leveraging Posh-ACME features

## Implementation Details

### Directory URL Construction

```powershell
function Get-AcmeDirectoryUrl {
    param([string]$PkiUrl)

    # Ensure proper URL format
    if (-not $PkiUrl.EndsWith('/acme/acme/directory')) {
        if ($PkiUrl.EndsWith('/')) {
            return "${PkiUrl}acme/acme/directory"
        } else {
            return "${PkiUrl}/acme/acme/directory"
        }
    }
    return $PkiUrl
}
```

### Account Management

```powershell
function Initialize-AcmeAccount {
    param([string]$DirectoryUrl, [string]$StateDir)

    # Set Posh-ACME state directory
    $env:POSHACME_HOME = $StateDir

    # Try to get existing account
    try {
        $account = Get-PAAccount
        if ($account -and $account.status -eq 'valid') {
            return $account
        }
    } catch {
        # Account doesn't exist, create new one
    }

    # Create new account
    return New-PAAccount -AcceptTOS
}
```

### Error Handling Integration

```powershell
function Invoke-PoshAcmeOperation {
    param(
        [scriptblock]$Operation,
        [string]$OperationName,
        [hashtable]$Context
    )

    try {
        $result = & $Operation
        Write-LogInfo -Message "Posh-ACME operation succeeded" -Context @{
            operation = $OperationName
            context = $Context
        }
        return $result
    } catch {
        Write-LogError -Message "Posh-ACME operation failed" -Context @{
            operation = $OperationName
            error = $_.Exception.Message
            context = $Context
        }
        throw
    }
}
```

## Testing Strategy

### Unit Tests
- Test configuration mapping functions
- Test URL construction logic
- Test account management flow
- Test error handling scenarios

### Integration Tests
- End-to-end certificate issuance
- Environment variable override testing
- File operation validation
- Error recovery scenarios

### Backward Compatibility Tests
- Existing YAML configurations work unchanged
- Environment variable overrides preserved
- Agent behavior consistent with current implementation
- Logging format maintained

## Risk Assessment

### Low Risk
- **Configuration Structure**: No changes to existing YAML format
- **Environment Variables**: Existing override system preserved
- **File Operations**: Atomic file operations maintained
- **Logging Format**: Structured logging unchanged

### Medium Risk
- **Posh-ACME Learning Curve**: Team needs to understand Posh-ACME patterns
- **Error Messages**: Different error format from custom implementation
- **Debugging**: New debugging patterns for Posh-ACME issues

### Mitigation Strategies
- **Comprehensive Documentation**: Detailed adapter function documentation
- **Training Materials**: Posh-ACME usage guides for the team
- **Error Mapping**: Map Posh-ACME errors to existing error handling patterns
- **Gradual Migration**: Maintain fallback capabilities during transition

## Success Criteria

1. **Backward Compatibility**: 100% - existing configurations work unchanged
2. **Functionality Preservation**: 100% - all current features maintained
3. **Code Reduction**: 80-90% reduction in ACME implementation code
4. **Performance**: No regression in certificate issuance time
5. **Reliability**: Improved error handling and recovery capabilities

## Next Steps

1. **Create PoshAcmeConfigAdapter.psm1** module with core functions
2. **Implement configuration mapping** with proper error handling
3. **Update agent.ps1** to use adapter functions
4. **Create comprehensive tests** for all adapter functions
5. **Validate backward compatibility** with existing configurations

This mapping analysis provides the foundation for creating a seamless adapter that maintains our existing interface while leveraging Posh-ACME's powerful capabilities.