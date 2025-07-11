# Multi-Feature Key Support: Final Approach Plan

## Executive Summary

This document presents the recommended approach for supporting multiple Feature Keys in the TOMEs system during fleet firmware upgrade transitions. After comprehensive analysis of the codebase, constraints, and use case requirements, we recommend implementing a **Proxy Communication Broker** solution that enables TOMEs to connect to both old and new firmware devices without modifying existing TOMEs or Terminal codebases.

## Problem Statement

### The Real Use Case: Fleet Firmware Upgrade Transition

The multi-Feature Key requirement stems from **fleet firmware upgrade scenarios**:

- **Mixed Trima V7 Fleet Environment**: During firmware upgrades, some Trima V7 devices run old firmware (old Feature Keys) while others run new firmware with non-DEHP support (new Feature Keys)
- **Extended Transition Period**: Fleet upgrades take significant time, requiring TOMEs to support both Trima V7 device firmware types simultaneously
- **End State**: After upgrade completion, all Trima V7 devices will use the same new non-DEHP-compatible Feature Key
- **Business Need**: Maintain operational continuity during the transition period

### Current System Constraints

#### 1. TOMEs Architecture Constraints
- **Singleton TrimaDeviceManager**: Single instance manages all device connections
- **Global Feature Key State**: `FeatureKey.GlobalConfirmationCode` set once at startup
- **Single Feature Key Configuration**: TOMEs configured with one Feature Key per instance
- **Minimal Code Changes Required**: Preference to avoid extensive TOMEs modifications

#### 2. DeviceControllers Library Constraints
- **2017 Legacy Codebase**: Cannot modify the DeviceControllers library
- **Hard Feature Key Validation**: `ApiFactory.CreateTrimaDeviceManager()` fails on invalid keys
- **Bidirectional Confirmation Code Validation**: Strict comparison between TOMEs and device codes
- **Hard Failure on Mismatch**: `SetDisconnected()` called when confirmation codes don't match

#### 3. Terminal/Communication Broker Constraints
- **Ancient Messaging Platform**: Preference to avoid modifying the existing Terminal codebase
- **WebSocket Protocol**: Custom messaging protocol with auto-generated message classes
- **Existing Protocol Support**: Already supports multiple Feature Codes in `ApplicationInitializationPayload`

## Analysis of Alternative Approaches

### Option 1: Modify TOMEs CommonComponent Wrapper

**Approach**: Extend TOMEs wrapper to handle multiple Feature Keys before calling DeviceControllers.

**Pros**:
- Contained within TOMEs codebase
- No external dependencies

**Cons**:
- Violates singleton TrimaDeviceManager constraint
- Requires significant TOMEs code changes
- Complex Feature Key compatibility detection logic
- Risk of breaking existing functionality

**Verdict**: ❌ **Rejected** - Too many changes to TOMEs architecture

### Option 2: Modify DeviceControllers Library

**Approach**: Update the 2017 DeviceControllers library to support multiple Feature Keys natively.

**Pros**:
- Clean architectural solution
- Native multi-key support

**Cons**:
- Requires modifying ancient, stable codebase
- High risk of introducing bugs
- Extensive testing required
- Deployment complexity

**Verdict**: ❌ **Rejected** - Cannot modify 2017 legacy library

### Option 3: Proxy Communication Broker (Recommended)

**Approach**: Deploy a lightweight proxy between TOMEs and the existing Communication Broker that transforms Feature Key messages.

**Pros**:
- Zero changes to TOMEs or Terminal codebases
- Leverages existing protocol support for multiple Feature Codes
- Transparent to both endpoints
- Configuration-driven mapping
- Easy deployment and rollback

**Cons**:
- Additional component to maintain
- Single point of failure (mitigated with high availability)
- Slight performance overhead

**Verdict**: ✅ **RECOMMENDED** - Best balance of functionality and risk

## Recommended Solution: Proxy Communication Broker

### Current System: Confirmation Code Validation Flow

The following diagram illustrates the exact mechanism of Feature Key validation and the critical points where mismatches cause device disconnection:

```mermaid
sequenceDiagram
    participant TOMEs as TOMEs<br/>(TrimaDeviceManager)
    participant Terminal as Communication<br/>Broker
    participant Device as Trima Device

    Note over TOMEs: 1. Feature Key Set at Startup
    TOMEs->>TOMEs: FeatureKey.GlobalConfirmationCode =<br/>FeatureKey.ConvertFeatureKeyToBytes(featureKey)
    TOMEs->>TOMEs: FeatureKeyConfirmationCode =<br/>FeatureKey.ConvertFeatureKey(featureKey)

    Note over TOMEs,Device: 2. Application Initialization
    TOMEs->>Terminal: ApplicationInitializationMessage<br/>{FeatureCodes: [confirmationCode]}
    Terminal->>Device: Forward message
    
    Note over Device: 3. Device Processing
    Device->>Device: Process with device's own Feature Key
    Device->>Device: Generate device confirmation code
    
    Note over Device,TOMEs: 4. Response with Device's Confirmation Code
    Device->>Terminal: ApplicationInitializationResponsePayload<br/>{FeatureKeysConfirmationCode: deviceCode}
    Terminal->>TOMEs: Forward response

    Note over TOMEs: 5. CRITICAL VALIDATION in DoApplicationInitializationResponse
    TOMEs->>TOMEs: codeBytes = FeatureKey.ConvertConfirmationCode(<br/>payload.FeatureKeysConfirmationCode)
    TOMEs->>TOMEs: localBytes = FeatureKey.ConvertConfirmationCode(<br/>applicationConfirmationCode)
    
    alt Confirmation Code Invalid
        TOMEs->>TOMEs: if (codeBytes == null || !IsConfirmationCodeValid(codeBytes))
        TOMEs->>TOMEs: SetDisconnected() ❌
        Note over TOMEs: HARD FAILURE - Device Unusable
    else Confirmation Codes Don't Match
        TOMEs->>TOMEs: if (!FeatureKey.CompareConfirmationCode(codeBytes, localBytes))
        TOMEs->>TOMEs: SetDisconnected() ❌
        Note over TOMEs: HARD FAILURE - Device Unusable
    else Success
        TOMEs->>TOMEs: m_appInitFeatureKeyCompatible = true ✅
        Note over TOMEs: Device Ready for Operations
    end
```

### Feature Key to Confirmation Code Conversion Process

```mermaid
flowchart TD
    A[Feature Key String<br/>e.g., '03AZ0CGG8X4E51G55STFHCDG8X'] --> B[FeatureKey.ConvertFeatureKey]
    B --> C[Decode Key to Bits]
    C --> D[Extract Feature Definitions]
    D --> E[Generate Confirmation Code<br/>Hex String]
    E --> F[FeatureKey.ConvertFeatureKeyToBytes]
    F --> G[Convert Hex to Byte Array<br/>GlobalConfirmationCode]
    
    H[Device Feature Key] --> I[Device Confirmation Code]
    
    J[TOMEs Confirmation Code] --> K[FeatureKey.CompareConfirmationCode]
    I --> K
    K --> L{Codes Match?}
    L -->|Yes| M[Success ✅]
    L -->|No| N[SetDisconnected ❌<br/>HARD FAILURE]
    
    style N fill:#ff6b6b
    style M fill:#51cf66
```

### Proxy Solution: Message Transformation Flow

The following diagram shows how the proxy intercepts and transforms Feature Key messages to enable compatibility between TOMEs and mixed fleet devices:

```mermaid
sequenceDiagram
    participant TOMEs as TOMEs<br/>(Old Feature Key)
    participant Proxy as Proxy Communication<br/>Broker
    participant Terminal as Terminal<br/>Broker
    participant OldDevice as Old Device<br/>(Old Feature Key)
    participant NewDevice as New Device<br/>(New Feature Key)

    Note over TOMEs: TOMEs configured with Old Feature Key
    TOMEs->>TOMEs: FeatureKeyConfirmationCode = "OLD_CODE"

    Note over TOMEs,NewDevice: Scenario 1: TOMEs → New Device
    TOMEs->>Proxy: ApplicationInitializationMessage<br/>{FeatureCodes: ["OLD_CODE"]}
    
    Note over Proxy: Proxy detects non-DEHP Feature Key requirement
    Proxy->>Proxy: requiresMapping = CheckFeatureKeyMapping(featureCode)
    Proxy->>Proxy: if (requiresMapping)<br/>transform OLD_CODE → NEW_CODE
    
    Proxy->>Terminal: ApplicationInitializationMessage<br/>{FeatureCodes: ["NEW_CODE"]}
    Terminal->>NewDevice: Forward transformed message
    
    NewDevice->>NewDevice: Process with NEW_CODE ✅
    NewDevice->>Terminal: ApplicationInitializationResponsePayload<br/>{FeatureKeysConfirmationCode: "NEW_CODE"}
    Terminal->>Proxy: Forward response
    
    Note over Proxy: Transform response back to OLD_CODE
    Proxy->>Proxy: Transform NEW_CODE → OLD_CODE<br/>for TOMEs compatibility
    
    Proxy->>TOMEs: ApplicationInitializationResponsePayload<br/>{FeatureKeysConfirmationCode: "OLD_CODE"}
    TOMEs->>TOMEs: CompareConfirmationCode(OLD_CODE, OLD_CODE) ✅
    TOMEs->>TOMEs: Success - Device Ready

    Note over TOMEs,OldDevice: Scenario 2: TOMEs → Old Device (Passthrough)
    TOMEs->>Proxy: ApplicationInitializationMessage<br/>{FeatureCodes: ["OLD_CODE"]}
    
    Note over Proxy: Proxy detects legacy Feature Key compatibility
    Proxy->>Proxy: requiresMapping = CheckFeatureKeyMapping(featureCode)
    Proxy->>Proxy: if (!requiresMapping)<br/>no transformation needed
    
    Proxy->>Terminal: ApplicationInitializationMessage<br/>{FeatureCodes: ["OLD_CODE"]} (unchanged)
    Terminal->>OldDevice: Forward message
    
    OldDevice->>OldDevice: Process with OLD_CODE ✅
    OldDevice->>Terminal: ApplicationInitializationResponsePayload<br/>{FeatureKeysConfirmationCode: "OLD_CODE"}
    Terminal->>Proxy: Forward response
    
    Note over Proxy: No transformation needed
    Proxy->>TOMEs: ApplicationInitializationResponsePayload<br/>{FeatureKeysConfirmationCode: "OLD_CODE"} (unchanged)
    TOMEs->>TOMEs: CompareConfirmationCode(OLD_CODE, OLD_CODE) ✅
    TOMEs->>TOMEs: Success - Device Ready
```

### Proxy Internal Logic Flow

```mermaid
flowchart TD
    A[Message from TOMEs] --> B{Message Type?}
    B -->|ApplicationInitialization| C[Extract FeatureCodes]
    B -->|Other| D[Passthrough]
    
    C --> E[Check Feature Key Mapping]
    E --> F{Requires Mapping?}
    
    F -->|No| G[No Transformation<br/>Forward as-is]
    F -->|Yes| H[Transform Feature Key]
    F -->|Unknown| I[Try Mapping<br/>Store Result]
    
    H --> J[Lookup in Mapping Table<br/>OLD_KEY → NEW_KEY]
    J --> K[Update FeatureCodes Array]
    K --> L[Forward to Terminal]
    
    G --> L
    I --> L
    
    M[Response from Device] --> N{Message Type?}
    N -->|ApplicationInitializationResponse| O[Extract FeatureKeysConfirmationCode]
    N -->|Other| P[Passthrough]
    
    O --> Q[Check if Transformation Needed]
    Q --> R{Transform Response?}
    
    R -->|Yes| S[Reverse Transform<br/>NEW_CODE → OLD_CODE]
    R -->|No| T[Forward as-is]
    
    S --> U[Update FeatureKeysConfirmationCode]
    U --> V[Forward to TOMEs]
    T --> V
    
    style H fill:#ffd43b
    style S fill:#ffd43b
    style G fill:#51cf66
    style T fill:#51cf66
```

### Architecture Overview

```
TOMEs (Single Feature Key) → [Proxy Broker] → [Terminal Broker] → Mixed Trima V7 Fleet
                                    ↓
                            Feature Key Mapping
                                    ↓
                          Legacy Firmware ← Old Keys
                          Non-DEHP Firmware ← New Keys
```

### Core Components

#### 1. Feature Key Mapping Service
```csharp
public class FeatureKeyMappingService
{
    private Dictionary<string, string> _oldToNewMapping;
    private Dictionary<string, string> _newToOldMapping;
    
    public string MapOldToNew(string oldConfirmationCode);
    public string MapNewToOld(string newConfirmationCode);
    public bool IsLegacyKey(string confirmationCode);
    public bool IsNonDEHPKey(string confirmationCode);
    public bool RequiresMapping(string confirmationCode);
}
```

#### 2. Proxy Communication Broker
```csharp
public class FeatureKeyProxyBroker
{
    private WebSocketServer _tomesListener;        // TOMEs connects here
    private WebSocketClient _terminalConnection;   // Connects to real Terminal
    private FeatureKeyMappingService _mappingService;
    private Dictionary<string, bool> _featureKeyMappingCache;
    
    // Transform messages from TOMEs to Terminal
    public void OnMessageFromTOMEs(string clientId, string message);
    
    // Transform responses from Terminal to TOMEs
    public void OnMessageFromTerminal(string clientId, string message);
}
```

### Implementation Details

#### Message Transformation Logic

**1. TOMEs → Device (ApplicationInitialization)**
```csharp
public void OnMessageFromTOMEs(string clientId, string message)
{
    if (IsApplicationInitializationMessage(message))
    {
        var payload = JsonConvert.DeserializeObject<ApplicationInitializationPayload>(message);
        var tomesConfirmationCode = payload.FeatureCodes?.FirstOrDefault();
        
        // Check if Feature Key mapping is required
        var requiresMapping = _mappingService.RequiresMapping(tomesConfirmationCode);
        
        if (requiresMapping)
        {
            var targetKey = _mappingService.MapOldToNew(tomesConfirmationCode);
            payload.FeatureCodes = new List<string> { targetKey };
            message = JsonConvert.SerializeObject(payload);
        }
    }
    
    _terminalConnection.Send(message);
}
```

**2. Device → TOMEs (ApplicationInitializationResponse)**
```csharp
public void OnMessageFromTerminal(string clientId, string message)
{
    if (IsApplicationInitializationResponseMessage(message))
    {
        var response = JsonConvert.DeserializeObject<ApplicationInitializationResponsePayload>(message);
        var deviceConfirmationCode = response.FeatureKeysConfirmationCode;
        var tomesExpectedCode = _tomesConfiguration.FeatureKeyConfirmationCode;
        
        // Transform device response to match TOMEs expectation
        if (_mappingService.IsNonDEHPKey(deviceConfirmationCode))
        {
            response.FeatureKeysConfirmationCode = _mappingService.MapNewToOld(deviceConfirmationCode);
            message = JsonConvert.SerializeObject(response);
        }
    }
    
    _tomesConnection.Send(message);
}
```

#### Feature Key Mapping Strategy

**Primary Approach: FeatureKey to ConfirmationCode Mapping**
```csharp
public bool RequiresMapping(string confirmationCode)
{
    // Check if this confirmation code needs to be mapped to non-DEHP-compatible version
    return _oldToNewMapping.ContainsKey(confirmationCode);
}

public string MapToCompatibleKey(string originalConfirmationCode)
{
    // Map legacy Feature Key to non-DEHP-compatible Feature Key for Trima V7
    if (_oldToNewMapping.TryGetValue(originalConfirmationCode, out var mappedKey))
    {
        return mappedKey;
    }
    
    return originalConfirmationCode; // No mapping needed
}
```

**Validation Approach: Confirmation Code Verification**
```csharp
public bool ValidateMapping(string originalCode, string mappedCode)
{
    // Verify that the mapping preserves feature compatibility for Trima V7
    var originalFeatures = FeatureKey.ConvertConfirmationCode(originalCode);
    var mappedFeatures = FeatureKey.ConvertConfirmationCode(mappedCode);
    
    return AreFeatureCompatible(originalFeatures, mappedFeatures);
}
```

### Configuration Management

#### Mapping Table Configuration
```json
{
  "featureKeyMappings": {
    "oldToNew": {
      "03AZ0CGG8X4E51G55STFHCDG8X": "03X32638Z2ZHP629Y9T7PPM0X",
      "0YR4GB5SVIV7WBRE0X": "03ZE408K6Y2X2X918FNYUFWFP",
      "03ZE408K6Y2X2X918FNYUFWFP": "03X32638Z2ZHP629Y9T7PPM0X"
    },
    "confirmationCodeMappings": {
      "old_confirmation_code_1": "new_confirmation_code_1",
      "old_confirmation_code_2": "new_confirmation_code_2"
    }
  },
  "tomesConfiguration": {
    "featureKey": "03AZ0CGG8X4E51G55STFHCDG8X",
    "confirmationCode": "computed_confirmation_code"
  },
  "proxySettings": {
    "tomesListenPort": 8080,
    "terminalTargetHost": "localhost",
    "terminalTargetPort": 8081,
    "enableLogging": true,
    "fallbackBehavior": "passthrough"
  }
}
```

#### TOMEs Configuration Changes
```xml
<!-- Minimal change: Point TOMEs to proxy instead of Terminal -->
<add key="CommBrokerIp" value="localhost" />
<add key="CommBrokerPort" value="8080" />  <!-- Proxy port -->
```

## Risk Assessment and Mitigation

### High Risk Items

#### 1. Confirmation Code Mapping Accuracy
**Risk**: Incorrect mappings cause device disconnections
**Mitigation**: 
- Comprehensive mapping validation
- Automated testing of all key combinations
- Rollback procedures for mapping updates

#### 2. Proxy Availability
**Risk**: Proxy failure breaks all device connections
**Mitigation**:
- High availability deployment
- Health monitoring and alerting
- Automatic failover to direct connection

#### 3. Performance Impact
**Risk**: Message transformation adds latency
**Mitigation**:
- Optimize JSON parsing and transformation
- Implement caching for mapping lookups
- Monitor and alert on performance degradation

### Medium Risk Items

#### 1. Feature Key Mapping Accuracy
**Risk**: Incorrect Feature Key mapping causes connection failures
**Mitigation**:
- ConfirmationCode-based mapping verification approach
- Fallback mechanisms for unmapped keys
- Comprehensive logging for troubleshooting

#### 2. Configuration Management Complexity
**Risk**: Complex mapping configurations lead to errors
**Mitigation**:
- Configuration validation tools
- Version control for mapping tables
- Automated configuration testing

### Low Risk Items

#### 1. WebSocket Protocol Compatibility
**Risk**: Proxy doesn't handle all message types correctly
**Mitigation**:
- Comprehensive protocol testing
- Passthrough mode for unknown messages
- Gradual feature rollout

## Conclusion

The Proxy Communication Broker approach provides the optimal solution for supporting multi-Feature Key requirements during fleet firmware upgrades. It respects all architectural constraints, minimizes changes to existing systems, and provides a clean transition path for mixed fleet environments.

**Key Benefits**:
- ✅ Zero changes to TOMEs or Terminal codebases
- ✅ Supports mixed fleet during transition period
- ✅ Maintains strict Feature Key validation integrity
- ✅ Configuration-driven with easy rollback
- ✅ Transparent operation to existing systems

**Recommendation**: Proceed with Proxy Communication Broker implementation as the primary solution for multi-Feature Key support during fleet firmware upgrade transitions.