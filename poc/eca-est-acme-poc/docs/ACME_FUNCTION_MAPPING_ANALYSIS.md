# ACME Function Mapping Analysis

## Overview

This document maps the current custom AcmeClient.psm1 functions to Posh-ACME equivalents for the migration strategy.

## Current AcmeClient.psm1 Public Functions

### Core ACME Protocol Functions
| Current Function | Posh-ACME Equivalent | Complexity | Notes |
|------------------|---------------------|------------|-------|
| `Get-AcmeDirectory` | `Set-PAServer` | **95% reduction** | Posh-ACME handles directory discovery internally |
| `New-AcmeAccount` | `New-PAAccount` | **90% reduction** | Direct 1:1 mapping with simpler parameters |
| `Get-AcmeAccount` | `Get-PAAccount` | **95% reduction** | Direct 1:1 mapping |
| `New-AcmeOrder` | `New-PAOrder` | **85% reduction** | Simpler parameter structure |
| `Get-AcmeAuthorization` | `Get-PAAuthorization` | **80% reduction** | Posh-ACME handles this internally |
| `Complete-Http01Challenge` | `Complete-PAChallenge` | **80% reduction** | Direct mapping with built-in validation |
| `Wait-ChallengeValidation` | Built into Posh-ACME | **100% reduction** | No equivalent needed |
| `Complete-AcmeOrder` | `Submit-PAOrder` | **85% reduction** | Direct mapping |
| `Get-AcmeCertificate` | `Get-PACertificate` | **90% reduction** | Direct mapping |

### Low-Level Protocol Functions
| Current Function | Posh-ACME Equivalent | Complexity | Notes |
|------------------|---------------------|------------|-------|
| `New-JwsSignedRequest` | Built into Posh-ACME | **100% reduction** | No equivalent needed - handled internally |
| `ConvertTo-Base64Url` | Built into Posh-ACME | **100% reduction** | No equivalent needed |
| `Get-FreshNonce` | Built into Posh-ACME | **100% reduction** | No equivalent needed |
| `Export-RsaPublicKeyJwk` | Built into Posh-ACME | **100% reduction** | No equivalent needed |
| `Get-JwkThumbprint` | Built into Posh-ACME | **100% reduction** | No equivalent needed |

## Function-by-Function Analysis

### 1. Get-AcmeDirectory
**Current Implementation** (~120 lines)
- Retrieves ACME directory from step-ca
- Caches directory URL for subsequent requests
- Handles HTTP errors and retry logic
- Validates directory structure

**Posh-ACME Replacement** (~1 line)
```powershell
Set-PAServer -DirectoryUrl $BaseUrl -SkipCertificateCheck
```

**Migration Strategy**:
- Function no longer needed - Posh-ACME handles directory discovery
- Update agent.ps1 to use `Set-PAServer` instead
- Remove directory caching logic

### 2. New-AcmeAccount
**Current Implementation** (~170 lines)
- Generates RSA 2048-bit key pair
- Creates JWK key representation
- Creates ACME account with contact information
- Handles account key registration with step-ca
- Stores account key with proper permissions

**Posh-ACME Replacement** (~5 lines)
```powershell
# Posh-ACME handles key generation automatically
$account = New-PAAccount -AcceptTOS
```

**Migration Strategy**:
- Create wrapper function for backward compatibility
- Posh-ACME handles key generation automatically
- Account key storage managed by Posh-ACME state system

### 3. Get-AcmeAccount
**Current Implementation** (~170 lines)
- Retrieves existing account information
- Validates account status
- Handles account key loading and verification

**Posh-ACME Replacement** (~1 line)
```powershell
$account = Get-PAAccount
```

**Migration Strategy**:
- Simple wrapper function
- Return same structure as current implementation
- Posh-ACME handles account state management

### 4. New-AcmeOrder
**Current Implementation** (~230 lines)
- Creates certificate order for domain
- Handles order structure and validation
- Manages order status tracking
- Supports multiple domain names (SANs)

**Posh-ACME Replacement** (~2 lines)
```powershell
$order = New-PAOrder -Domain $DomainName -Force
```

**Migration Strategy**:
- Wrapper function with parameter mapping
- Posh-ACME handles order creation and validation
- Return same structure as current implementation

### 5. Complete-Http01Challenge
**Current Implementation** (~180 lines)
- Generates challenge response token
- Places token file in challenge directory
- Notifies ACME server of challenge completion
- Handles challenge response validation

**Posh-ACME Replacement** (~1 line)
```powershell
# Posh-ACME handles challenges automatically during order creation
```

**Migration Strategy**:
- Function no longer needed for basic HTTP-01 challenges
- Posh-ACME handles challenge completion automatically
- May need wrapper for advanced challenge scenarios

### 6. Complete-AcmeOrder
**Current Implementation** (~250 lines)
- Submits CSR to ACME server
- Handles order finalization process
- Manages certificate issuance workflow
- Processes final certificate retrieval

**Posh-ACME Replacement** (~2 lines)
```powershell
# Certificate issuance handled automatically in Posh-ACME
$cert = Get-PACertificate
```

**Migration Strategy**:
- Function no longer needed for basic workflow
- Posh-ACME handles order finalization automatically
- May need wrapper for complex CSR scenarios

### 7. Get-AcmeCertificate
**Current Implementation** (~170 lines)
- Downloads issued certificate from ACME server
- Handles certificate chain validation
- Manages certificate format conversion
- Stores certificate with proper permissions

**Posh-ACME Replacement** (~3 lines)
```powershell
$certInfo = Get-PACertificate
# Certificate files automatically managed by Posh-ACME
```

**Migration Strategy**:
- Wrapper function to retrieve certificate info
- Certificate file handling managed by our Save-PoshAcmeCertificate function
- Return same structure as current implementation

## Migration Complexity Assessment

### High-Impact Functions (Immediate Replacement)
1. **New-AcmeAccount** - Critical for account lifecycle
2. **New-AcmeOrder** - Critical for certificate ordering
3. **Get-AcmeCertificate** - Critical for certificate retrieval

### Medium-Impact Functions (Wrapper Creation)
1. **Get-AcmeAccount** - Simple wrapper needed
2. **Complete-Http01Challenge** - May not be needed
3. **Complete-AcmeOrder** - May not be needed

### Low-Impact Functions (Complete Removal)
1. **Get-AcmeDirectory** - No longer needed
2. **New-JwsSignedRequest** - No longer needed
3. **All low-level crypto functions** - No longer needed

## Code Reduction Estimate

### Current AcmeClient.psm1
- **Total Lines**: ~1,980 lines
- **Public Functions**: 10 functions
- **Internal Functions**: 5 functions
- **Crypto Implementation**: ~500 lines
- **HTTP Protocol Logic**: ~800 lines
- **Error Handling**: ~300 lines
- **Comments/Documentation**: ~380 lines

### Posh-ACME Replacement
- **Wrapper Functions**: ~200 lines
- **Error Handling**: Built into Posh-ACME
- **Crypto Implementation**: Built into Posh-ACME
- **HTTP Protocol Logic**: Built into Posh-ACME

### **Net Reduction**: ~1,780 lines (90% code reduction)

## Backward Compatibility Strategy

### Wrapper Function Design
```powershell
function New-AcmeAccount {
    param(
        [string]$BaseUrl,
        [string]$AccountKeyPath,
        [string[]]$Contact = @()
    )

    # Map to Posh-ACME equivalent
    $result = Initialize-PoshAcmeAccountFromConfig -Config @{
        pki_url = $BaseUrl
    }

    # Return same structure as current implementation
    return @{
        Account = $result.Account
        Status = $result.Status
        ID = $result.ID
        # ... other fields for compatibility
    }
}
```

### Migration Benefits

#### Immediate Benefits
- **90% Code Reduction**: From ~1,980 lines to ~200 lines
- **Reliability**: Battle-tested Posh-ACME implementation
- **Standards Compliance**: Full ACME v2 RFC 8555 compliance
- **Security**: Regular security updates from Posh-ACME community

#### Long-term Benefits
- **Maintenance**: Dramatically reduced maintenance burden
- **Features**: Access to advanced Posh-ACME capabilities
- **Testing**: Built-in Posh-ACME validation and error handling
- **Community**: Active development and support

## Risk Assessment

### Low Risk
- **Function Signatures**: Can maintain exact same signatures
- **Return Structures**: Can replicate current return structures
- **Error Handling**: Posh-ACME provides superior error handling
- **Configuration**: Existing configuration system preserved

### Medium Risk
- **Error Messages**: Different error format from custom implementation
- **Debugging**: New debugging patterns for Posh-ACME issues
- **Performance**: Different performance characteristics

### Mitigation Strategies
- **Comprehensive Testing**: Complete test coverage for all functions
- **Error Mapping**: Map Posh-ACME errors to existing error patterns
- **Gradual Migration**: Maintain both implementations during transition
- **Documentation**: Detailed migration guide and troubleshooting

## Implementation Priority

### Phase 1: Core Functions (High Priority)
1. `New-AcmeAccount` - Account lifecycle management
2. `New-AcmeOrder` - Certificate ordering
3. `Get-AcmeCertificate` - Certificate retrieval

### Phase 2: Support Functions (Medium Priority)
1. `Get-AcmeAccount` - Account information retrieval
2. Wrapper functions for remaining operations

### Phase 3: Cleanup (Low Priority)
1. Remove internal functions
2. Remove crypto implementations
3. Remove HTTP protocol logic

## Success Criteria

1. **Functional Equivalence**: 100% of current functionality preserved
2. **Performance**: No regression in certificate issuance time
3. **Reliability**: Improved error handling and recovery
4. **Maintainability**: 90% code reduction achieved
5. **Testing**: 100% test coverage for new implementation

This analysis provides the foundation for creating the Posh-ACME wrapper module that will replace our custom AcmeClient.psm1 while maintaining full backward compatibility.