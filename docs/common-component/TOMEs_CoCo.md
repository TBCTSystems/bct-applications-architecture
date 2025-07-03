# TOMEs Common Component Integration Architecture

## System Context (C4 Level 1)

```mermaid
C4Context
    title TOMEs Common Component System Context

    Person(operator, "Trima Operator", "Healthcare professional operating Trima device")
    Person(admin, "TOMEs Administrator", "System administrator managing device configurations")
    
    System(tomes, "TOMEs System", "TerumoBCT Operational Management and Enterprise System")
    System_Ext(trima, "Trima V7 Device", "Blood collection and processing device")
    System_Ext(commbroker, "Communications Broker", "Message routing and protocol translation")
    
    Rel(operator, trima, "Operates device", "Physical interaction")
    Rel(admin, tomes, "Configures devices", "Web interface")
    Rel(tomes, commbroker, "Device management", "WebSocket/TCP")
    Rel(commbroker, trima, "Device communication", "TCP/IP")
    Rel(trima, commbroker, "Status updates, events", "TCP/IP")
```

## Container Diagram (C4 Level 2)

```mermaid
C4Container
    title TOMEs Common Component Container Architecture

    Container_Boundary(tomes_boundary, "TOMEs System") {
        Container(wsa, "WSA Layer", "ASP.NET MVC", "Web Service Application - Device management interface")
        Container(daa, "DAA Layer", "WCF Services", "Data Access and Acquisition - Device communication")
        Container(db, "TOMEs Database", "SQL Server", "Device configurations, settings, feature keys")
        
        Container_Boundary(external_libs, "External Libraries") {
            Container(coco_wrapper, "CommonComponent Wrapper", "C# Library", "TOMEs-specific abstraction over Common Component")
            Container(coco_lib, "BCT Common Component", "C# Library", "Device communication and management library")
        }
    }
    
    System_Ext(commbroker, "Communications Broker", "Message routing service")
    System_Ext(trima, "Trima V7 Device", "Medical device")
    
    Rel(wsa, daa, "Device operations", "WCF")
    Rel(daa, coco_wrapper, "Device management", "Direct calls")
    Rel(coco_wrapper, coco_lib, "API calls", "Direct calls")
    Rel(coco_lib, commbroker, "WebSocket", "TCP/IP")
    Rel(commbroker, trima, "Device protocol", "TCP/IP")
    Rel(daa, db, "Settings, configurations", "SQL")
    Rel(wsa, db, "Settings management", "SQL")
```

## Component Diagram (C4 Level 3) - DAA Layer

```mermaid
C4Component
    title TOMEs DAA Layer Components

    Container_Boundary(daa_boundary, "DAA Layer") {
        Component(tdm_service, "TrimaSpecificService", "WCF Service", "DAA-WSA communication for Trima operations")
        Component(bootstrap, "CommonComponentBootstrap", "Service", "Manages Common Component lifecycle")
        Component(tdm_manager, "TrimaDeviceManager", "Business Logic", "Primary device management and event handling")
        Component(settings_mgr, "TrimaSettingsManager", "Data Access", "Database settings management")
        Component(validation, "TrimaValidationHelper", "Business Logic", "FeatureKey validation and updates")
    }
    
    Container_Boundary(wrapper_boundary, "CommonComponent Wrapper") {
        Component(cc_wrapper, "CommonComponent", "Wrapper", "TOMEs-specific Common Component abstraction")
        Component(fk_helper, "FeatureKeyHelper", "Helper", "FeatureKey validation and conversion")
        Component(comm_helper, "TrimaCommunicationHelper", "Helper", "Device communication operations")
    }
    
    Container_Boundary(coco_boundary, "BCT Common Component") {
        Component(api_factory, "ApiFactory", "Factory", "Creates device managers and APIs")
        Component(device_mgr, "TrimaDeviceManager", "Core", "Device connection and message handling")
        Component(feature_key, "FeatureKey", "Core", "Feature validation and authorization")
    }
    
    ContainerDb(db, "TOMEs Database", "SQL Server", "Device settings and configurations")
    System_Ext(commbroker, "Communications Broker")
    
    Rel(tdm_service, tdm_manager, "Device operations")
    Rel(bootstrap, cc_wrapper, "Lifecycle management")
    Rel(tdm_manager, cc_wrapper, "Device events")
    Rel(validation, fk_helper, "FeatureKey operations")
    Rel(cc_wrapper, api_factory, "Device manager creation")
    Rel(api_factory, device_mgr, "Creates")
    Rel(api_factory, feature_key, "Validates")
    Rel(device_mgr, commbroker, "WebSocket communication")
    Rel(settings_mgr, db, "CRUD operations")
```

## FeatureKey System Architecture

```mermaid
C4Component
    title FeatureKey System Components

    Container_Boundary(tomes_fk, "TOMEs FeatureKey Management") {
        Component(fk_init, "TrimaFeatureKeyInitializer", "Startup", "WSA startup FeatureKey initialization")
        Component(fk_validator, "TrimaValidationHelper", "Validator", "FeatureKey validation and business logic")
        Component(fk_settings, "TrimaSettingsManager", "Data Access", "Database FeatureKey persistence")
        Component(fk_dto, "TrimaDeviceOptionsViewModel", "DTO", "FeatureKey data transfer")
    }
    
    Container_Boundary(wrapper_fk, "Wrapper FeatureKey") {
        Component(fk_helper, "FeatureKeyHelper", "Helper", "TOMEs FeatureKey utilities")
        Component(fk_result, "FeatureKeyValidationResult", "Model", "Validation result with features")
        Component(trima_feature, "TrimaFeature", "Model", "TOMEs feature representation")
    }
    
    Container_Boundary(core_fk, "Core FeatureKey System") {
        Component(fk_core, "FeatureKey", "Core", "Feature validation, conversion, global state")
        Component(fk_def, "FeatureKeyDefinition", "Model", "Decoded feature structure")
        Component(bool_features, "TrimaBooleanFeature", "Enum", "Feature enumeration (34 features)")
        Component(default_list, "DefaultBooleanFeatureList", "Catalog", "Master feature definitions")
        Component(global_state, "GlobalConfirmationCode", "Static", "System-wide feature state")
    }
    
    ContainerDb(db, "TOMEs Database", "SQL Server", "FeatureOptions setting")
    
    Rel(fk_init, fk_settings, "Load on startup")
    Rel(fk_validator, fk_helper, "Validate and convert")
    Rel(fk_helper, fk_core, "Core validation")
    Rel(fk_core, default_list, "Feature definitions")
    Rel(fk_core, global_state, "Sets global state")
    Rel(fk_settings, db, "Persist FeatureKey")
    Rel(fk_core, bool_features, "Feature enumeration")
```

## System Startup Sequence

```mermaid
sequenceDiagram
    participant DB as TOMEs Database
    participant WSA as WSA Startup
    participant FKInit as TrimaFeatureKeyInitializer
    participant Settings as TrimaSettingsManager
    participant FKHelper as FeatureKeyHelper
    participant FKCore as FeatureKey (Core)
    participant GlobalState as GlobalConfirmationCode

    Note over WSA: WSA Application Startup
    WSA->>FKInit: OnStartup()
    FKInit->>Settings: GetSettings()
    Settings->>DB: SELECT FeatureOptions FROM TrimaSettings
    DB-->>Settings: "03AZ0CGG8X4E51G55STFHCDG8X"
    Settings-->>FKInit: TrimaDeviceOptionsViewModel
    
    FKInit->>FKHelper: SetFeatureKey(deviceOptions.FeatureOptions)
    FKHelper->>FKCore: ConvertFeatureKeyToBytes(featureKey)
    
    Note over FKCore: Validate and convert FeatureKey
    FKCore->>FKCore: IsFeatureKeyValid(featureKey)
    FKCore->>FKCore: DecodeKey(featureKey)
    FKCore->>FKCore: Validate against DefaultBooleanFeatureList
    FKCore-->>FKHelper: byte[] confirmationCode
    
    FKHelper->>GlobalState: Set GlobalConfirmationCode
    Note over GlobalState: System-wide feature state now available
    
    Note over WSA: WSA Ready - Features available for checking
```

## DAA Service Startup Sequence

```mermaid
sequenceDiagram
    participant Bootstrap as CommonComponentBootstrap
    participant Settings as TrimaSettingsManager
    participant CC as CommonComponent
    participant Factory as ApiFactory
    participant FKCore as FeatureKey (Core)
    participant TDM as TrimaDeviceManager
    participant CommBroker as Communications Broker

    Note over Bootstrap: DAA Service Startup
    Bootstrap->>Bootstrap: OnStartup()
    Bootstrap->>Settings: GetDeviceOptions()
    Settings-->>Bootstrap: TrimaDeviceOptionsViewModel
    
    alt FeatureOptions is empty
        Bootstrap->>Bootstrap: Set DefaultFeatureKey
        Note over Bootstrap: "03AZ0CGG8X4E51G55STFHCDG8X"
    end
    
    Bootstrap->>CC: Start(deviceOptions, serialNumber, version)
    CC->>CC: GetDeviceManager(deviceOptions.FeatureOptions, serialNumber, version)
    CC->>Factory: CreateTrimaDeviceManager(featureOptions, ip, serialNumber, version)
    
    Factory->>FKCore: IsFeatureKeyValid(featureKey)
    FKCore->>FKCore: Validate FeatureKey structure
    FKCore-->>Factory: validation result
    
    alt Valid FeatureKey
        Factory->>TDM: new TrimaDeviceManager(ip, featureKey, serialNumber, version)
        TDM->>TDM: Set FeatureKey property
        TDM->>FKCore: ConvertFeatureKey(featureKey)
        TDM->>FKCore: ConvertFeatureKeyToBytes(featureKey)
        FKCore-->>TDM: confirmationCode
        TDM->>FKCore: Set GlobalConfirmationCode
        
        Note over TDM: Device Manager Ready
        CC->>TDM: ConnectToCommunicationBroker()
        TDM->>CommBroker: WebSocket connection
        CommBroker-->>TDM: Connection established
        
    else Invalid FeatureKey
        Factory-->>CC: return null
        CC->>CC: throw TrimaDeviceManagerException
    end
```

## Device Connection Flow

```mermaid
sequenceDiagram
    participant Device as Trima Device
    participant CommBroker as Communications Broker
    participant TDMCore as TrimaDeviceManager (Core)
    participant CCWrapper as CommonComponent (Wrapper)
    participant TDMTomes as TrimaDeviceManager (TOMEs)
    participant StateStorage as TrimaDeviceStateStorage
    participant DeviceDao as TrimaDeviceDao

    Note over Device: Device Powers On
    Device->>CommBroker: TCP Connection + Handshake
    CommBroker->>TDMCore: ClientHandshakeEventReceivedCB()
    
    TDMCore->>TDMCore: ProcessConnectedClient()
    TDMCore->>TDMCore: CreateTrimaDevice()
    TDMCore->>CCWrapper: OnTrimaDeviceConnect(device)
    
    CCWrapper->>CCWrapper: GetTrimaDeviceConnectedArgs()
    CCWrapper->>TDMTomes: DeviceConnectedHandler(args)
    
    TDMTomes->>TDMTomes: GetDeviceCommunicationState(serialNumber)
    TDMTomes->>TDMTomes: Check license and authorization
    
    alt Device Allowed
        TDMTomes->>DeviceDao: CreateOrMerge(device)
        TDMTomes->>CCWrapper: InitializeDevice(serialNumber, getUsersFunc)
        CCWrapper->>Device: DoApplicationInitialization()
        Device-->>CCWrapper: Initialization response
        
        TDMTomes->>TDMTomes: UpdateConnectedDevice()
        TDMTomes->>TDMTomes: UpdateDevicePrograms()
        TDMTomes->>TDMTomes: UpdateDeviceGroupSettings()
        TDMTomes->>StateStorage: SetDeviceStatus(serialNumber, status)
        
    else Device Not Allowed
        TDMTomes->>StateStorage: SetDeviceStatus(serialNumber, NotAllowed)
        Note over TDMTomes: Device connection rejected
    end
```

## FeatureKey Update Flow

```mermaid
sequenceDiagram
    participant UI as TOMEs Web UI
    participant Controller as TrimaSettingsController
    participant Validator as TrimaValidationHelper
    participant FKHelper as FeatureKeyHelper
    participant FKCore as FeatureKey (Core)
    participant Settings as TrimaSettingsManager
    participant DB as TOMEs Database
    participant ProgramMgr as ProgramListManager

    UI->>Controller: POST /api/settings/trima
    Controller->>Validator: ValidateAndUpdateFeatureKey(newFeatureKey)
    
    Validator->>FKHelper: IsFeatureKeyValidWithInfo(newFeatureKey)
    FKHelper->>FKCore: IsFeatureKeyValid(newFeatureKey, out features, out valueFeatures)
    
    FKCore->>FKCore: DecodeKey(newFeatureKey)
    FKCore->>FKCore: Validate against DefaultBooleanFeatureList
    FKCore->>FKCore: Check CRC and structure
    FKCore-->>FKHelper: validation result + feature lists
    FKHelper-->>Validator: FeatureKeyValidationResult
    
    alt Valid FeatureKey
        Validator->>Validator: GetOldFeatureKeyInfo()
        Validator->>Validator: IsJapanFeaturesEnabled(old vs new)
        
        alt Japan Features Changed
            Note over Validator: Japan features availability changed
            Validator->>ProgramMgr: DeleteByDeviceType(DeviceType.Trima)
            Validator->>Validator: Delete procedure priority lists
            Validator->>Validator: Reset device group programs
        end
        
        Validator->>Settings: UpdateFeatureKey(newFeatureKey)
        Settings->>DB: UPDATE TrimaSettings SET VALUE = newFeatureKey
        
        Validator->>FKHelper: SetFeatureKey(newFeatureKey)
        FKHelper->>FKCore: ConvertFeatureKeyToBytes(newFeatureKey)
        FKCore->>FKCore: Set GlobalConfirmationCode
        
        Note over FKCore: Global feature state updated
        Validator-->>Controller: Success
        Controller-->>UI: 200 OK
        
    else Invalid FeatureKey
        Validator->>Validator: throw InvalidFeatureKeyException
        Validator-->>Controller: Exception
        Controller-->>UI: 400 Bad Request
    end
```

## BBIS Input Request Flow

```mermaid
sequenceDiagram
    participant Device as Trima Device
    participant TDMCore as TrimaDeviceManager (Core)
    participant CCWrapper as CommonComponent (Wrapper)
    participant TDMTomes as TrimaDeviceManager (TOMEs)
    participant Validator as TrimaBarcodeValidator
    participant InputMgr as TrimaInputLockManager
    participant FileSystem as FileSystemManager

    Device->>TDMCore: BbisInputRequestMessage
    TDMCore->>CCWrapper: OnBbisInputRequest(sequenceId, device, payload)
    CCWrapper->>CCWrapper: RequestBbisInputRecord(serialNumber, bbisIdentifier)
    CCWrapper->>TDMTomes: BbisInputDataRequestedHandler(args)
    
    TDMTomes->>Validator: ValidateBarcode(bbisIdentifier)
    Validator->>Validator: Lookup input record in database
    Validator-->>TDMTomes: TrimaBarcodeValidationResult
    
    alt Record Found
        TDMTomes->>TDMTomes: FillBbisInputArguments()
        
        alt Donor Picture Exists
            TDMTomes->>FileSystem: FileExists(picturePath)
            FileSystem-->>TDMTomes: true
            TDMTomes->>FileSystem: ReadAllBytes(picturePath)
            FileSystem-->>TDMTomes: byte[] pictureData
            TDMTomes->>TDMTomes: Convert.ToBase64String(pictureData)
        end
        
        TDMTomes->>InputMgr: UnLockForDevice(serialNumber)
        TDMTomes->>InputMgr: Lock(recordId, serialNumber)
        TDMTomes->>TDMTomes: Set args.Result = Found
        
    else Record Not Found
        TDMTomes->>TDMTomes: Set args.Result = NotFound
    end
    
    TDMTomes-->>CCWrapper: Updated args
    CCWrapper->>CCWrapper: Map to BbisInputResponsePayload
    CCWrapper-->>TDMCore: BbisInputResponsePayload
    TDMCore->>Device: BbisInputResponseMessage
```

## Device Status Change Flow

```mermaid
sequenceDiagram
    participant Device as Trima Device
    participant TDMCore as TrimaDeviceManager (Core)
    participant CCWrapper as CommonComponent (Wrapper)
    participant TDMTomes as TrimaDeviceManager (TOMEs)
    participant InitQueue as TrimaDeviceInitializationQueue
    participant StateStorage as TrimaDeviceStateStorage
    participant CommHelper as TrimaCommunicationHelper

    Device->>TDMCore: TrimaClientStatusNotificationMessage
    TDMCore->>CCWrapper: OnTrimaDeviceStateChange(device, newState)
    CCWrapper->>TDMTomes: DeviceStatusChangedHandler(args)
    
    TDMTomes->>InitQueue: AddToQueueOrExecute(serialNumber, action)
    
    InitQueue->>TDMTomes: Execute status change logic
    TDMTomes->>TDMTomes: IsCurrentDeviceAllowed(serialNumber)
    
    alt Device Allowed
        TDMTomes->>TDMTomes: UpdateDeviceOnStatusChanged(args)
        
        alt New Status = Free
            TDMTomes->>TDMTomes: UpdateConnectedDevice(device)
            
            alt Device needs program update
                TDMTomes->>CommHelper: SendDeviceProgramList(serialNumber, programs)
                CommHelper->>Device: DoSendProgramToDevice()
            end
            
            alt Device needs group settings update
                TDMTomes->>CommHelper: SendDeviceGroupSettings(serialNumber, deviceGroup)
                CommHelper->>Device: DoSendGroupSettingsToDevice()
            end
        end
        
        TDMTomes->>StateStorage: SetDeviceStatus(serialNumber, newStatus)
        
    else Device Not Allowed
        Note over TDMTomes: Ignore status change for unauthorized device
    end
```

## Program Download Flow

```mermaid
sequenceDiagram
    participant TOMEs as TOMEs Manager
    participant CommHelper as TrimaCommunicationHelper
    participant CCWrapper as CommonComponent
    participant Device as Trima Device
    participant TDMCore as TrimaDeviceManager (Core)

    TOMEs->>CommHelper: SendDeviceProgramList(serialNumber, programList)
    CommHelper->>CCWrapper: GetDevice(serialNumber)
    CCWrapper-->>CommHelper: ITrimaDevice
    
    CommHelper->>CommHelper: Map TOMEs model to TrimaProgram
    CommHelper->>Device: DoSendProgramToDevice(program, out downloadResult)
    
    Device->>TDMCore: ConfigurationBlocksDownloadRequestMessage
    TDMCore->>Device: Send program blocks
    Device->>TDMCore: ConfigurationBlocksDownloadResponseMessage
    TDMCore-->>Device: Download complete
    
    Device-->>CommHelper: SendConfigurationResultType + ProgramDownloadResult
    CommHelper->>CommHelper: Map to TrimaProgramExportResultViewModel
    
    CommHelper->>CommHelper: Create block results
    loop For each configuration block
        CommHelper->>CommHelper: Map block result (Ok/Failed)
    end
    
    CommHelper-->>TOMEs: TrimaProgramExportResultViewModel
    
    alt All blocks successful
        TOMEs->>TOMEs: Mark device as updated
        TOMEs->>TOMEs: Update device group settings
    else Some blocks failed
        Note over TOMEs: Log failure, retry may be needed
    end
```

## Feature Checking Runtime Flow

```mermaid
sequenceDiagram
    participant App as Application Code
    participant FKCore as FeatureKey (Core)
    participant GlobalState as GlobalConfirmationCode
    participant BoolEnum as TrimaBooleanFeature

    Note over App: Runtime feature check
    App->>FKCore: IsBooleanFeatureEnabled(TrimaBooleanFeature.JapanFeatures)
    FKCore->>GlobalState: Access GlobalConfirmationCode
    
    alt GlobalConfirmationCode is null
        FKCore-->>App: return false
    else GlobalConfirmationCode exists
        FKCore->>FKCore: Calculate byte index = mc_BFeatureIdxStart + (feature / 8)
        FKCore->>FKCore: Calculate bit mask = 0x01 << (feature % 8)
        FKCore->>GlobalState: Check confirmationCode[byteIdx] & bitMask
        GlobalState-->>FKCore: bit value
        FKCore-->>App: boolean result
    end
    
    alt Feature enabled
        App->>App: Execute feature-specific logic
    else Feature disabled
        App->>App: Skip feature or use default behavior
    end
```

## Error Handling and Recovery

```mermaid
sequenceDiagram
    participant System as System Component
    participant ErrorHandler as Error Handler
    participant Logger as SystemLogManager
    participant Recovery as Recovery Logic

    System->>System: Operation fails
    System->>ErrorHandler: Exception thrown
    
    alt TrimaDeviceManagerException
        ErrorHandler->>Logger: WriteError("Unable to start Trima DAA service")
        ErrorHandler->>Recovery: Use DefaultFeatureKey
        Recovery->>Recovery: Set "03AZ0CGG8X4E51G55STFHCDG8X"
        Recovery->>System: Retry with default
        
    else InvalidFeatureKeyException
        ErrorHandler->>Logger: WriteError("Invalid feature key")
        ErrorHandler->>Recovery: Reject update, keep current key
        Recovery-->>System: Validation failed
        
    else Communication Error
        ErrorHandler->>Logger: WriteError("Communication broker disconnected")
        ErrorHandler->>Recovery: Set all devices inactive
        Recovery->>Recovery: Reset device states
        Recovery->>Recovery: Attempt reconnection
        
    else Device Authorization Error
        ErrorHandler->>Logger: WriteWarning("Device not allowed")
        ErrorHandler->>Recovery: Set device status = NotAllowed
        Recovery->>Recovery: Block device operations
    end
```

## Component Dependencies

```mermaid
C4Component
    title Component Dependencies and Data Flow

    Container_Boundary(data_layer, "Data Layer") {
        ComponentDb(db, "TOMEs Database", "SQL Server", "FeatureOptions, Device settings")
        Component(settings_dao, "TrimaSettingsManager", "DAO", "Database access")
    }
    
    Container_Boundary(business_layer, "Business Layer") {
        Component(device_mgr, "TrimaDeviceManager", "Manager", "Device lifecycle")
        Component(validation, "TrimaValidationHelper", "Validator", "Business rules")
        Component(communication, "TrimaCommunicationHelper", "Helper", "Device communication")
    }
    
    Container_Boundary(wrapper_layer, "Wrapper Layer") {
        Component(cc_wrapper, "CommonComponent", "Wrapper", "TOMEs abstraction")
        Component(fk_helper, "FeatureKeyHelper", "Helper", "FeatureKey utilities")
    }
    
    Container_Boundary(core_layer, "Core Layer") {
        Component(api_factory, "ApiFactory", "Factory", "Component creation")
        Component(tdm_core, "TrimaDeviceManager", "Core", "Device management")
        Component(fk_core, "FeatureKey", "Core", "Feature system")
    }
    
    Container_Boundary(global_state, "Global State") {
        Component(confirmation_code, "GlobalConfirmationCode", "Static", "Feature state")
    }
    
    Rel(settings_dao, db, "CRUD")
    Rel(device_mgr, settings_dao, "Settings")
    Rel(validation, fk_helper, "Validation")
    Rel(device_mgr, cc_wrapper, "Operations")
    Rel(cc_wrapper, api_factory, "Creation")
    Rel(api_factory, tdm_core, "Creates")
    Rel(api_factory, fk_core, "Validates")
    Rel(fk_helper, fk_core, "Core operations")
    Rel(fk_core, confirmation_code, "Sets state")
    Rel(tdm_core, confirmation_code, "Sets state")
```

## Summary Architecture

```mermaid
C4Context
    title TOMEs Common Component Integration Summary

    System_Boundary(tomes_system, "TOMEs System") {
        System(wsa, "WSA Layer", "Web interface, FeatureKey management")
        System(daa, "DAA Layer", "Device communication, event handling")
        System(wrapper, "CommonComponent Wrapper", "TOMEs-specific abstractions")
        System(core, "BCT Common Component", "Core device management")
    }
    
    SystemDb(db, "TOMEs Database", "Settings, configurations, FeatureKeys")
    System_Ext(devices, "Trima Devices", "Medical devices")
    System_Ext(broker, "Communications Broker", "Message routing")
    
    Rel(wsa, daa, "Device operations", "WCF")
    Rel(daa, wrapper, "Device management", "Direct")
    Rel(wrapper, core, "Core operations", "Direct")
    Rel(core, broker, "Communication", "WebSocket")
    Rel(broker, devices, "Device protocol", "TCP/IP")
    Rel(wsa, db, "Settings", "SQL")
    Rel(daa, db, "Device data", "SQL")
    
    UpdateLayoutConfig($c4ShapeInRow="2", $c4BoundaryInRow="1")
```