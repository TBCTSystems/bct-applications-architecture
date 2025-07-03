# BCT.CommonComponent Interface Control Document (ICD)

## Table of Contents
1. [Overview](#overview)
2. [System Architecture](#system-architecture)
3. [API Interfaces](#api-interfaces)
4. [Message Categories](#message-categories)
5. [Message Definitions](#message-definitions)
6. [Logging Definitions](#logging-definitions)
7. [Data Types and Enumerations](#data-types-and-enumerations)
8. [Connection Properties](#connection-properties)
9. [Error Handling](#error-handling)
10. [Feature Keys](#feature-keys)

## 1. Overview

The BCT Common Component ecosystem provides a comprehensive communication framework for medical device integration. This ICD documents the complete message architecture from the foundational Terminal components through to device-specific implementations like Trima V7.

### Architecture Layers

#### 1.1 Foundation Layer (Terminal)
- **BCT.CommonComponent.Terminal**: Core terminal and client management
- **BCT.CommonComponent.CommunicationAPI**: Base API interfaces and message framework
- **BCT.CommonComponent.CommunicationAPI.Messages**: Foundational message definitions
- **BCT.CommonComponent.MessagingBase**: Core messaging infrastructure
- **BCT.CommonComponent.CommunicationsBroker**: Message routing and broker services

#### 1.2 Device Controller Layer (Trima)
- **BCT.CommonComponent.DeviceControllers.Trima**: Trima-specific API implementations
- **BCT.CommonComponent.DeviceControllers.Trima.Messages**: Trima message definitions and payloads
- **BCT.CommonComponent.DeviceControllers.Trima.FeatureKey**: Feature authorization and configuration
- **BCT.CommonComponent.DeviceControllers.TrimaManager**: Device management and connection handling

### Message Hierarchy
```
BaseMessage (Terminal)
├── BaseUserMessage (Terminal)
│   ├── TrimaAlarmEventMessage (Trima)
│   ├── TrimaPPLRequestMessage (Trima)
│   └── [Other Trima Messages]
├── BaseUserResponseMessage (Terminal)
│   ├── TrimaPPLResponseMessage (Trima)
│   └── [Other Trima Response Messages]
└── [Other Base Message Types]
```

## 2. System Architecture

### Communication Flow
```
TOMEs 7+ ←→ Communications Broker ←→ Trima V7 Device
```

### Primary Interfaces
1. **ITrimaDeviceControllerApi**: Used by TOMEs to communicate with Trima devices
2. **ITrimaDeviceApi**: Used by simulators and device-side implementations
3. **ITrimaDeviceManager**: Manages multiple Trima device connections

## 3. API Interfaces

### 3.1 ITrimaDeviceControllerApi
**Purpose**: Primary interface for TOMEs to interact with Trima devices

**Key Methods**:
- `Connect()`: Establish connection to Communications Broker
- `SendDeviceCatalogInfoToDevice()`: Download catalog information (VISTA)
- `SendProcedureListToDevice()`: Download procedure list (VISTA)
- `SendInitialFlowCapsToDevice()`: Configure initial flow caps
- `SendScalingFactorsToDevice()`: Send scaling factors
- `SendRegionalizationFeatureToDevice()`: Set regionalization features
- `SendTrimaConfigurationToDevice()`: Configure Trima settings
- `SendDonorToDevice()`: Download donor information (VISTA only)
- `GetRegionalizationConstantFromDevice()`: Retrieve regionalization constants
- `GetRegionalizationConfirmationCodeFromDevice()`: Get confirmation codes
- `GetRegionalizationFeatureIdFromDevice()`: Get feature IDs

### 3.2 ITrimaDeviceApi
**Purpose**: Interface for device-side implementations and simulators

**Key Methods**:
- `Connect()`: Connect to Communications Broker
- `Disconnect()`: Disconnect from Communications Broker
- `SendAlarmEvent()`: Send alarm notifications
- `SendOperatorAlarmAcknowledgementEvent()`: Send alarm acknowledgements
- `SendProcedureAdjustmentEvent()`: Send procedure adjustments
- `SendEndOfRunSummaryEvent()`: Send end-of-run summaries
- `SendDonorUpdatedEvent()`: Send donor updates
- `SendProcedureStatusNotification()`: Send procedure status
- `SendMachineStatusNotification()`: Send machine status
- `SendClientStatusNotification()`: Send client status
- `SendTrimaPPLRequestMessage()`: Request Procedure Priority Lists
- `SendBarcodeLookupRequestMessage()`: Request barcode lookups
- `SendBbisInputRequestMessage()`: Send BBIS input requests

## 4. Message Categories

### 4.1 Event Messages
Messages sent to notify of device events and state changes.

### 4.2 Request Messages
Messages requesting information or actions from the receiving system.

### 4.3 Response Messages
Messages responding to previous requests.

### 4.4 Configuration Messages
Messages for configuring device settings and parameters.

### 4.5 Status Notification Messages
Messages providing periodic status updates.

### 4.6 Logging Messages
Messages for audit trail and logging purposes.

## 5. Message Definitions

### 5.1 Foundation Messages (Terminal Layer)

#### 5.1.1 Base Message Types

##### BaseMessage
**Purpose**: Root base class for all messages in the system  
**Namespace**: BCT.CommonComponent.MessagingBase  

**Core Properties**:
- Message routing and identification
- Serialization support
- Version management
- Timestamp handling

##### BaseUserMessage
**Type**: User, Request  
**Purpose**: Base class for all user-initiated messages  
**Derives From**: BaseMessage  
**Namespace**: BCT.CommonComponent.CommunicationAPI.Messages  

**Characteristics**:
- Abstract class - cannot be instantiated directly
- Public serialization enabled
- Supports all destination types

##### BaseUserResponseMessage
**Type**: User, Response  
**Purpose**: Base class for all user response messages  
**Derives From**: BaseResponseMessage  
**Namespace**: BCT.CommonComponent.CommunicationAPI.Messages  

**Characteristics**:
- Abstract class for response messages
- Inherits response handling capabilities
- Public serialization enabled

#### 5.1.2 Connection and Handshake Messages

##### ClientHandshakeEventMessage
**Type**: Internal, Event  
**Direction**: Communications Broker → Client  
**Purpose**: Notification when another client completes handshake  

**Fields**:
- `Info` (ClientHandshakePayload): Handshake information payload

##### ConnectionHandshakeMessage
**Type**: Internal, Request  
**Purpose**: Initial connection handshake between client and broker

##### ConnectionHandshakeResponseMessage
**Type**: Internal, Response  
**Purpose**: Response to connection handshake

#### 5.1.3 Application Initialization Messages

##### ApplicationInitializationMessage
**Type**: User, Request  
**Direction**: TOMEs → Device  
**Purpose**: Initialize application connection with device  
**Derives From**: BaseUserMessage  

**Fields**:
- `Payload` (ApplicationInitializationPayload): Initialization parameters

##### ApplicationInitializationResponseMessage
**Type**: User, Response  
**Direction**: Device → TOMEs  
**Purpose**: Response to application initialization  

##### UpdateGlobalUserListMessage
**Type**: User, Request  
**Purpose**: Update device with global user list  

**Fields**:
- `Payload` (UpdateGlobalUserListPayload): User list data

##### UpdateGlobalUserListResponseMessage
**Type**: User, Response  
**Purpose**: Confirmation of user list update

#### 5.1.4 Configuration Messages

##### ConfigurationBlocksDownloadMessage
**Type**: Request, User  
**Purpose**: Download configuration blocks to device  
**Derives From**: BaseUserMessage  

**Fields**:
- `Blocks` (Array of ConfigurationBlockPayload): Configuration blocks to download

##### ConfigurationBlocksDownloadRequestResponseMessage
**Type**: Request, Response  
**Purpose**: Response to configuration download request

##### RequestConfigurationBlocksMessage
**Type**: User, Request  
**Purpose**: Request configuration blocks from device

##### RequestConfigurationBlocksResponseMessage
**Type**: User, Response  
**Purpose**: Response with requested configuration blocks

#### 5.1.5 Access Level and Transaction Messages

##### RequestAccessLevelMessage
**Type**: User, Request  
**Purpose**: Request specific access level on device

##### RequestAccessLevelResponseMessage
**Type**: User, Response  
**Purpose**: Response to access level request

##### ReleaseAccessLevelMessage
**Type**: User, Request  
**Purpose**: Release previously acquired access level

##### ReleaseAccessLevelResponseMessage
**Type**: User, Response  
**Purpose**: Confirmation of access level release

##### BeginTransactionMessage
**Type**: User, Request  
**Purpose**: Start a transactional operation

##### BeginTransactionResponseMessage
**Type**: User, Response  
**Purpose**: Confirmation of transaction start

##### CommitTransactionMessage
**Type**: User, Request  
**Purpose**: Commit a transactional operation

##### CommitTransactionResponseMessage
**Type**: User, Response  
**Purpose**: Confirmation of transaction commit

##### RollbackTransactionMessage
**Type**: User, Request  
**Purpose**: Rollback a transactional operation

##### RollbackTransactionResponseMessage
**Type**: User, Response  
**Purpose**: Confirmation of transaction rollback

#### 5.1.6 Status and Notification Messages

##### StatusNotificationMessage
**Type**: Status, User  
**Purpose**: Base class for status notifications  
**Derives From**: BaseUserMessage  

**Fields**:
- `Payload` (StatusNotificationBasePayload): Status notification data

##### StatusRequestMessage
**Type**: User, Request  
**Purpose**: Request status notifications from device

##### StatusRequestResponseMessage
**Type**: User, Response  
**Purpose**: Response to status request

#### 5.1.7 Donor Management Messages

##### DonorDownloadMessage
**Type**: User, Request  
**Purpose**: Download donor information to device

##### DonorDownloadRequestMessage
**Type**: User, Request  
**Purpose**: Request donor download

##### DonorDownloadRequestResponseMessage
**Type**: User, Response  
**Purpose**: Response to donor download request

##### DonorDownloadResponseMessage
**Type**: User, Response  
**Purpose**: Confirmation of donor download

##### DonorCommitEventMessage
**Type**: User, Event  
**Purpose**: Notification of donor commit

##### DonorRejectedEventMessage
**Type**: User, Event  
**Purpose**: Notification of donor rejection

##### DonorUpdatedEventMessage
**Type**: User, Event  
**Purpose**: Notification of donor information update

#### 5.1.8 Device Event Messages

##### ButtonPushEventMessage
**Type**: User, Event  
**Purpose**: Notification of button press on device

##### StartOfRunEventMessage
**Type**: User, Event  
**Purpose**: Notification of procedure start

##### EndOfRunEventMessage
**Type**: User, Event  
**Purpose**: Notification of procedure end

##### EndOfRunSummaryEventMessage
**Type**: User, Event  
**Purpose**: End of run summary information

##### AlarmEventMessage
**Type**: User, Event  
**Purpose**: Alarm notification from device

#### 5.1.9 File Transfer Messages

##### FileTransferRequestMessage
**Type**: User, Request  
**Purpose**: Request file transfer

##### FileTransferResponseMessage
**Type**: User, Response  
**Purpose**: Response to file transfer request

##### RequestFileListMessage
**Type**: User, Request  
**Purpose**: Request list of files

##### RequestFileListResponseMessage
**Type**: User, Response  
**Purpose**: Response with file list

##### RequestFileListBySequenceNumberMessage
**Type**: User, Request  
**Purpose**: Request files by sequence number

##### RequestFileListBySequenceNumberResponseMessage
**Type**: User, Response  
**Purpose**: Response with files by sequence number

#### 5.1.10 Language and Localization Messages

##### SetActiveLanguageMessage
**Type**: User, Request  
**Purpose**: Set active language on device

##### SetActiveLanguageResponseMessage
**Type**: User, Response  
**Purpose**: Confirmation of language change

#### 5.1.11 Utility Messages

##### WriteToLogRequestMessage
**Type**: User, Request  
**Purpose**: Request to write entry to device log

##### SetTimeMessage
**Type**: User, Request  
**Purpose**: Set time on device

##### BroadcastMessage
**Type**: User, Broadcast  
**Purpose**: Broadcast message to multiple clients

##### BroadCastResponseMessage
**Type**: User, Response  
**Purpose**: Response to broadcast message

#### 5.1.12 Metrics and Monitoring Messages

##### QueryMetricsMessage
**Type**: User, Request  
**Purpose**: Request system metrics

##### MetricsResponseMessage
**Type**: User, Response  
**Purpose**: Response with system metrics

##### LatencyTestRequestMessage
**Type**: User, Request  
**Purpose**: Request latency test

##### LatencyTestRequestMessageResponse
**Type**: User, Response  
**Purpose**: Response to latency test

#### 5.1.13 Foundation Data Types

##### DonorInfoBasePayload
**Purpose**: Base donor information structure

**Fields**:
- `DonorName` (string): Donor name (max 129 chars)
- `DonorDOB` (int64): Date of birth (Unix epoch time)
- `Gender` (Gender): Donor gender
- `DonorBloodType` (BloodTypes): Blood type

##### StatusNotificationBasePayload
**Purpose**: Base status notification structure (abstract)

**Fields**:
- `ClientId` (TerminalClientId): Terminal client identifier

##### ConfigurationBlockPayload
**Purpose**: Configuration block data structure

##### ApplicationInitializationPayload
**Purpose**: Application initialization parameters

##### ClientHandshakePayload
**Purpose**: Client handshake information

##### EndOfRunSummaryPayload
**Purpose**: End of run summary data

##### DonorUpdatedPayload
**Purpose**: Updated donor information

### 5.2 Trima-Specific Messages (Device Layer)

#### 5.2.1 Alarm and Event Messages

#### TrimaAlarmEventMessage
**Type**: User, Event  
**Direction**: Device → TOMEs  
**Purpose**: Notification when an alarm is triggered  

**Fields**:
- `Number` (int): The alarm number

#### TrimaOperatorAlarmAcknowledgementEventMessage
**Type**: User, Event  
**Direction**: Device → TOMEs  
**Purpose**: Notification of alarm acknowledgement  

**Payload**: TrimaOperatorAlarmAcknowledgementPayload

#### TrimaProcedureAdjustmentEventMessage
**Type**: User, Event  
**Direction**: Device → TOMEs  
**Purpose**: Notification of procedure adjustments  

**Payload**: TrimaProcedureAdjustmentBasePayload

### 5.2 Request/Response Messages

#### TrimaPPLRequestMessage
**Type**: User, Request  
**Direction**: Device → TOMEs  
**Purpose**: Request for Procedure Priority List  

**Fields**:
- `PPLName` (string): Name of requested PPL

#### TrimaPPLResponseMessage
**Type**: User, Response  
**Direction**: TOMEs → Device  
**Purpose**: Response to PPL request  

#### TrimaRegionalizationConstantMessage
**Type**: User, Request  
**Direction**: TOMEs → Device  
**Purpose**: Request regionalization constant  

#### TrimaRegionalizationConstantResponseMessage
**Type**: User, Response, Request  
**Direction**: Device → TOMEs  
**Purpose**: Response with regionalization constant  

#### TrimaRegionalizationConfirmationCodeMessage
**Type**: User, Request  
**Direction**: TOMEs → Device  
**Purpose**: Request confirmation code  

#### TrimaRegionalizationConfirmationCodeResponseMessage
**Type**: User, Response, Request  
**Direction**: Device → TOMEs  
**Purpose**: Response with confirmation code  

#### TrimaRegionalizationFeatureIDMessage
**Type**: User, Request  
**Direction**: TOMEs → Device  
**Purpose**: Request feature ID information  

#### TrimaRegionalizationFeatureIDResponseMessage
**Type**: User, Response, Request  
**Direction**: Device → TOMEs  
**Purpose**: Response with feature ID information  

### 5.3 Configuration Payloads

#### TrimaConfigurationPayload
**Purpose**: Configure Trima device settings  

**Key Fields**:
- `OneTimeConfig` (bool): Temporary vs permanent configuration
- `HeightUnits` (HeightUnitsType): Height measurement units
- `WeightUnits` (WeightUnitsType): Weight measurement units
- `DateFormat` (TrimaDateFormatType): Date display format
- `TimeFormat` (TimeFormatType): Time display format
- `DecimalDelimiter` (DecimalDelimiterType): Decimal point delimiter
- `RBCMeasurement` (RbcMeasurementType): RBC measurement type
- `AudioLevel` (TrimaAudioLevelType): Speaker audio level
- `ReturnPressureHighLimit` (double): Maximum return pressure (230-310)
- `DrawPressureLowLimit` (double): Maximum draw pressure (-250 to -100)
- `PlateletACRatio` (double): Inlet AC ratio for platelets (6.0-13.7)
- `PlasmaACRatio` (double): AC ratio for plasma (6.0-13.7)
- `PostHematocrit` (double): Minimum post hematocrit (30.0-55.0)
- `TBVPercentage` (int): TBV removal percentage (1-15)
- `WeightSetting` (double): Weight threshold for TBV (40-226 kg)
- `PostProcedurePlateletCount` (double): Min post-procedure platelet count
- `MaximumProcedureDuration` (int): Max procedure duration (10-150 min)
- `MaximumQualificationDuration` (int): Max qualification duration (10-150 min)
- `ACRate` (int): AC infusion curve setting (1-6)
- `VolumeRemovalStrategy` (TrimaVolumeRemovalTypes): Volume removal strategy
- `MaxDrawFlow` (TrimaMaxDrawFlowType): Inlet flow limit
- `MinimumReplacementVolume` (int): Replacement fluid threshold (0-1000 ml)
- `DRBCSplitNotification` (bool): DRBC split alert
- `DRBCThreshold` (int): DRBC dose definition (150-450 ml)
- `PlasmaRinseback` (bool): Plasma rinseback protocol
- `SalineRinseback` (bool): Saline rinseback protocol
- `ProductBagAirRemoval` (bool): Air removal during testing
- `AutoFlow` (bool): Enable/disable autoflow
- `FlowRateEntry` (bool): Flow rate entry capability
- `AutoFlowDelta` (TrimaAutoFlowDeltaType): Auto flow rate delta
- `CollectPlateletsInOneBag` (bool): Single bag platelet collection
- `DefaultPlateletCount` (int): Default platelet count (50-600)
- `RbcACRatio` (TrimaRbcACRatioType): Inlet/AC ratio for RBC
- `ReplacementSolution` (bool): Use replacement fluid
- `ReplacementSolutionPercent` (double): Fluid balance percentage (80-120)
- `AMAPPlasmaMinimum` (int): Min plasma volume for AMAP (0-1000 ml)
- `AMAPPlasmaMaximum` (int): Max plasma volume for AMAP (0-1000 ml)
- `InletManagement` (int): Inlet flow setting (1-6)
- `ReturnManagement` (int): Return management setting (1-6)
- `FFPVolume` (int): FFP collection volume (0-1000 ml)

#### TrimaDonorPayload
**Purpose**: Donor information for procedures  
**Derives From**: DonorInfoBasePayload

**Fields**:
- `Height` (double): Height in cm (121.92-243.84)
- `Weight` (double): Weight in kg (22.68-226.76)
- `Hematocrit` (double): Hematocrit percentage (30.0-55.4)
- `PreCount` (double): Pre-count in 10³/μl (50.0-600.0)
- `SampleVolume` (double): Blood sample volume in ml (0.0-100.0)
- `Picture` (string): Base64 encoded donor picture (max 53726 chars)
- `PictureCRC` (uint): CRC of picture byte array

#### TrimaDonorUpdatedPayload
**Purpose**: Updated donor information  
**Derives From**: DonorUpdatedPayload

#### TrimaEndOfRunSummaryPayload
**Purpose**: End-of-run procedure summary  
**Derives From**: EndOfRunSummaryPayload

### 5.4 Status Notification Payloads

#### TrimaProcedureStatusNotificationPayload
**Purpose**: Real-time procedure status updates  
**Derives From**: StatusNotificationBasePayload

**Key Fields**:
- `ProcedureNumber` (uint): Current procedure number
- `TargetProcedureTime` (float): Target time in minutes (0-300)
- `CurrentProcedureTime` (float): Current time in minutes (0-300)
- `RemainingProcedureTime` (float): Remaining time in minutes (0-300)
- `SolutionAdditionTime` (float): Solution addition elapsed time (0-300)
- `TargetPlateletYield` (int): Target platelet yield in 10¹¹ units (0-150)
- `CurrentPlateletYield` (int): Current platelet yield in 10¹¹ units (0-150)
- `TargetPlasmaVolume` (int): Target plasma volume in ml (0-1000)
- `CurrentPlasmaVolume` (int): Current plasma volume in ml (0-1000)
- `TargetRBCVolume` (int): Target RBC volume in ml (0-1000)
- `CurrentRBCVolume` (int): Current RBC volume in ml (0-1000)
- `TargetRBCCollectHematocrit` (float): Target hematocrit (0.0-1.0)
- `CurrentRBCCollectHematocrit` (float): Current hematocrit (0.0-1.0)
- `TargetPlateletVolume` (int): Target platelet volume in ml (0-1200)
- `CurrentPlateletVolume` (int): Current platelet volume in ml (0-1200)
- `TargetPCO` (float): Target plasma carryover percentage (0.0-1.0)
- `TargetPASvolume` (int): Target PAS volume in ml (0-1200)
- `CurrentPASvolume` (int): Current PAS volume in ml (0-1200)
- `TargetRAS1Volume` (int): Target RAS #1 volume in ml (0-500)
- `CurrentRAS1Volume` (int): Current RAS #1 volume in ml (0-500)
- `TargetRAS2Volume` (int): Target RAS #2 volume in ml (0-500)
- `CurrentRAS2Volume` (int): Current RAS #2 volume in ml (0-500)
- `CurrentPlateletACVolume` (int): Current AC in platelet bag (0-1200 ml)
- `CurrentPlasmaACVolume` (int): Current AC in plasma bag (0-1200 ml)
- `CurrentRBC1ACVolume` (int): Current AC in RBC #1 (0-1200 ml)
- `CurrentRBC2ACVolume` (int): Current AC in RBC #2 (0-1200 ml)
- `TotalBloodProcessed` (int): Total blood processed in ml (0-65535)
- `DonorTBV` (int): Donor total blood volume in ml (0-13000)
- `Substate` (string): Current executing substate (max 36 chars)
- `RecoveryState` (string): Current recovery state (max 36 chars)
- `AlarmState` (string): Alarm text for status screen (max 500 chars)
- `CurrentLogName` (string): Current log file name (max 500 chars)
- `SystemStateFlow` (TrimaSystemStateType): Current system state

#### TrimaMachineStatusNotificationPayload
**Purpose**: Machine status updates  
**Derives From**: StatusNotificationBasePayload

#### TrimaClientStatusNotificationPayload
**Purpose**: Client status updates  
**Derives From**: StatusNotificationBasePayload

### 5.5 Program Configuration Messages

#### TrimaCatalogInfo
**Purpose**: Device catalog information for VISTA

#### TrimaProcedureListPayload
**Purpose**: Available procedures list for VISTA

#### TrimaInitialFlowCapsPayload
**Purpose**: Initial flow rate capabilities configuration

#### TrimaProductScalingFactorsPayload
**Purpose**: Product scaling factors for calculations

#### TrimaRegionalizationFeaturePayload
**Purpose**: Regionalization feature settings

#### TrimaPPLConfigPayload
**Purpose**: Procedure Priority List configuration

### 5.6 Operator Action Messages

#### TrimaOperatorActionBasePayload
**Purpose**: Base payload for operator actions

**Fields**:
- `Timestamp` (int64): Action timestamp

#### TrimaProcedureAdjustmentBasePayload
**Purpose**: Procedure adjustment actions  
**Derives From**: TrimaOperatorActionBasePayload

#### TrimaOperatorAlarmAcknowledgementPayload
**Purpose**: Alarm acknowledgement actions

### 5.7 Connection and Critical Data

#### TrimaConnectionPropertiesPayload
**Purpose**: Connection configuration properties

#### TrimaCriticalDataFieldPayload
**Purpose**: Critical data field definitions

#### TrimaTubingInfo
**Purpose**: Tubing set information

## 6. Logging Definitions

### 6.1 AlarmLogEntry
**Purpose**: Audit trail for alarms, advisories, and alerts

**Fields**:
- `ReferenceID` (uint): Unique ID for linking related entries
- `Timestamp` (int64): Alarm timestamp
- `Name` (string): Alarm message text
- `Type` (AlarmType): Alarm type (A1, A2, R1, R2, W)
- `Enum` (int): Alarm enumeration for troubleshooting

### 6.2 OperatorActionLogEntry
**Purpose**: Audit trail for operator actions

**Fields**:
- `ReferenceID` (uint): Unique reference ID for event linking
- `ActionType` (TrimaOperatorActionType): Type of action performed
- `ActionTime` (int64): Time action was taken
- `ConfigSignatureType` (AuthenticateByType): Required authentication type
- `OperatorActionPayload` (TrimaOperatorActionBasePayload): Action details

### 6.3 ProcedureOfferedLogEntry
**Purpose**: Log of procedures offered to operators

**Fields**:
- `ProcedurePayload` (ProcedurePayload): Procedure details

### 6.4 ProcedurePriorityListLogEntry
**Purpose**: Log of PPL operations

### 6.5 ProgramConfigurationReceivedLogEntry
**Purpose**: Log of program configuration updates

## 7. Data Types and Enumerations

### 7.1 System State Types
- `TrimaSystemStateType`: Device system states
- `TrimaSystemEventType`: System event types

### 7.2 Configuration Types
- `TrimaDateFormatType`: Date format options
- `TrimaAudioLevelType`: Audio level settings
- `TrimaMaxDrawFlowType`: Maximum draw flow settings
- `TrimaAutoFlowDeltaType`: Auto flow delta options
- `TrimaVolumeRemovalTypes`: Volume removal strategies
- `TrimaRbcACRatioType`: RBC AC ratio options

### 7.3 Operator and Access Types
- `TrimaOperatorActionType`: Operator action categories
- `TrimaAccessLevelTypes`: Access level definitions
- `TrimaAlarmResponseType`: Alarm response options

### 7.4 Procedure Types
- `TrimaProcedureAdjustmentType`: Procedure adjustment types
- `TrimaProcedureAdjustmentSourceType`: Adjustment source types
- `TrimaVolumeReasonCodeType`: Volume reason codes

### 7.5 Product Types
- `PCXType`: PCX-related types
- `PlateletGenderType`: Platelet gender specifications
- `TrimaControlIdType`: Control ID types

### 7.6 Program Types
- `TrimaProgramVersionType`: Program version information
- `ApplicationInitializationResultType`: Initialization results
- `ReceiveConfigurationResultType`: Configuration receive results
- `SendConfigurationResultType`: Configuration send results

### 7.7 Lookup Types
- `PplLookupOptionType`: PPL lookup options

## 8. Connection Properties

### 8.1 ITrimaDeviceControllerApiConnectionProperties
**Purpose**: Connection configuration for TOMEs

### 8.2 ITrimaDeviceApiConnectionProperties
**Purpose**: Connection configuration for devices

**Key Properties**:
- Client ID and identification
- Software and marketing versions
- Language settings
- Component information
- Client start time

## 9. Error Handling

### 9.1 Connection Errors
- WebSocket connection failures
- Handshake timeout errors
- Authentication failures

### 9.2 Message Errors
- Serialization/deserialization errors
- Invalid message format
- Missing required fields
- Field validation errors

### 9.3 Device Errors
- Device not responding
- Invalid device state
- Configuration conflicts

## 10. Feature Keys

### 10.1 Boolean Features
The system supports various boolean feature flags that control device behavior:

- `TrimaBooleanFeature.JapanFeatures`: Japan-specific features
- `TrimaBooleanFeature.AiroutMitigation`: Air removal mitigation
- `TrimaBooleanFeature.AllowAdjustFlowRatesOnProcedureSelect`: Flow rate adjustment

### 10.2 Value Features
Configurable value-based features for device customization.

### 10.3 Feature Authorization
- Feature key validation
- Authorization levels
- Feature group management

## Appendices

### A. Message Flow Diagrams

#### A.1 Device Connection and Initialization Flow

```mermaid
sequenceDiagram
    participant TOMEs as TOMEs 7+
    participant TDM as TrimaDeviceManager
    participant CB as Communications Broker
    participant Trima as Trima V7 Device

    Note over TOMEs, Trima: 1. Initial Connection Setup
    TOMEs->>TDM: ConnectToCommunicationBroker()
    TDM->>CB: WebSocket Connection
    CB-->>TDM: Connection Established
    TDM-->>TOMEs: Connection Success

    Note over TOMEs, Trima: 2. Device Handshake
    Trima->>CB: ClientHandshakeEventMessage
    CB->>TDM: ClientHandshakeEventReceivedCB()
    TDM->>TDM: ProcessConnectedClient()
    TDM->>TOMEs: OnTrimaDeviceConnectEvent()

    Note over TOMEs, Trima: 3. Application Initialization
    TOMEs->>TDM: DoApplicationInitialization()
    TDM->>CB: ApplicationInitializationMessage
    CB->>Trima: ApplicationInitializationMessage
    Trima-->>CB: ApplicationInitializationResponseMessage
    CB-->>TDM: ApplicationInitializationResponseCB()
    TDM-->>TOMEs: ApplicationInitializationResultType

    Note over TOMEs, Trima: 4. Global User List Exchange
    TDM->>CB: UpdateGlobalUserListMessage
    CB->>Trima: UpdateGlobalUserListMessage
    Trima-->>CB: UpdateGlobalUserListResponseMessage
    CB-->>TDM: UpdateGlobalUserListResponseCB()

    Note over TOMEs, Trima: 5. Status Subscription
    TDM->>CB: StatusRequestMessage
    CB->>Trima: StatusRequestMessage
    Trima-->>CB: StatusRequestResponseMessage
    CB-->>TDM: StatusRequestResponseMessageReceivedCB()
```

#### A.2 Configuration Download Flow (VISTA)

```mermaid
sequenceDiagram
    participant TOMEs as TOMEs 7+
    participant TDM as TrimaDeviceManager
    participant CB as Communications Broker
    participant Trima as Trima V7 Device

    Note over TOMEs, Trima: Configuration Block Download Process

    TOMEs->>TDM: SendTrimaConfigurationToDevice()
    TDM->>CB: ConfigurationBlocksDownloadRequestMessage
    CB->>Trima: ConfigurationBlocksDownloadRequestMessage
    
    Note over Trima: Process Configuration
    Trima-->>CB: ConfigurationBlocksDownloadRequestResponseMessage
    CB-->>TDM: ConfigurationBlocksDownloadRequestResponseMessageReceivedCB()
    
    alt Configuration Accepted
        Trima-->>CB: ConfigurationBlocksDownloadResponseMessage
        CB-->>TDM: ConfigurationBlocksDownloadResponseMessageReceivedCB()
        TDM-->>TOMEs: OnConfigBlockDownloadResponse()
    else Configuration Rejected
        TDM-->>TOMEs: Download Failed
    end

    Note over TOMEs, Trima: Other Configuration Messages
    TOMEs->>TDM: SendDeviceCatalogInfoToDevice()
    TOMEs->>TDM: SendProcedureListToDevice()
    TOMEs->>TDM: SendInitialFlowCapsToDevice()
    TOMEs->>TDM: SendScalingFactorsToDevice()
    TOMEs->>TDM: SendRegionalizationFeatureToDevice()
```

#### A.3 Program Download Flow

```mermaid
sequenceDiagram
    participant TOMEs as TOMEs 7+
    participant TDM as TrimaDeviceManager
    participant CB as Communications Broker
    participant Trima as Trima V7 Device

    Note over TOMEs, Trima: Trima Program Download

    TOMEs->>TDM: DoSendProgramToDevice()
    TDM->>TDM: RequestAccessLevel(ExclusiveConfigure)
    TDM->>CB: RequestAccessLevelMessage
    CB->>Trima: RequestAccessLevelMessage
    Trima-->>CB: RequestAccessLevelResponseMessage
    CB-->>TDM: RequestAccessLevelResponseMessageReceivedCB()

    alt Access Level Granted
        TDM->>CB: BeginTransactionMessage
        CB->>Trima: BeginTransactionMessage
        Trima-->>CB: BeginTransactionResponseMessage
        CB-->>TDM: BeginTransactionResponseMessageReceivedCB()

        TDM->>CB: ConfigurationBlocksDownloadRequestMessage(TrimaProgram)
        CB->>Trima: ConfigurationBlocksDownloadRequestMessage
        Trima-->>CB: ConfigurationBlocksDownloadRequestResponseMessage
        CB-->>TDM: ConfigurationBlocksDownloadRequestResponseMessageReceivedCB()

        TDM->>CB: CommitTransactionMessage
        CB->>Trima: CommitTransactionMessage
        Trima-->>CB: CommitTransactionResponseMessage
        CB-->>TDM: CommitTransactionResponseMessageReceivedCB()

        TDM->>CB: ReleaseAccessLevelMessage
        CB->>Trima: ReleaseAccessLevelMessage
        Trima-->>CB: ReleaseAccessLevelResponseMessage
        CB-->>TDM: ReleaseAccessLevelResponseMessageReceivedCB()

        TDM-->>TOMEs: SendConfigurationResultType.Success
    else Access Denied or Transaction Failed
        TDM->>CB: RollbackTransactionMessage (if needed)
        TDM-->>TOMEs: SendConfigurationResultType.Failed
    end
```

#### A.4 Donor Information Flow

```mermaid
sequenceDiagram
    participant TOMEs as TOMEs 7+
    participant TDM as TrimaDeviceManager
    participant CB as Communications Broker
    participant Trima as Trima V7 Device

    Note over TOMEs, Trima: Donor Information Exchange

    TOMEs->>TDM: SendDonorToDevice(TrimaDonorPayload)
    TDM->>CB: ConfigurationBlocksDownloadRequestMessage(Donor)
    CB->>Trima: ConfigurationBlocksDownloadRequestMessage
    
    Note over Trima: Validate Donor Info
    Trima-->>CB: ConfigurationBlocksDownloadRequestResponseMessage
    CB-->>TDM: ConfigurationBlocksDownloadRequestResponseMessageReceivedCB()

    Note over TOMEs, Trima: Donor Updates from Device
    Trima->>CB: TrimaDonorUpdatedEventMessage
    CB->>TDM: Event Received
    TDM->>TOMEs: OnDonorUpdatedEvent()
```

#### A.5 Status Notification Flow

```mermaid
sequenceDiagram
    participant TOMEs as TOMEs 7+
    participant TDM as TrimaDeviceManager
    participant CB as Communications Broker
    participant Trima as Trima V7 Device

    Note over TOMEs, Trima: Continuous Status Updates

    loop Periodic Status Updates
        Trima->>CB: TrimaClientStatusNotificationMessage
        CB->>TDM: ClientStatusNotificationMessageReceivedCB()
        TDM->>TOMEs: OnTrimaDeviceStateChange()

        Trima->>CB: TrimaProcedureStatusNotificationMessage
        CB->>TDM: CurrentProcedureStatusNotificationMessageReceivedCB()
        TDM->>TOMEs: OnTrimaDeviceProcedureStatusUpdate()

        Trima->>CB: TrimaMachineStatusNotificationMessage
        CB->>TDM: MachineStatusNotificationMessageReceivedCB()
        TDM->>TOMEs: OnTrimaDeviceMachineStatusUpdate()
    end
```

#### A.6 Request/Response Flow (PPL, Barcode, BBIS)

```mermaid
sequenceDiagram
    participant TOMEs as TOMEs 7+
    participant TDM as TrimaDeviceManager
    participant CB as Communications Broker
    participant Trima as Trima V7 Device

    Note over TOMEs, Trima: Procedure Priority List Request
    Trima->>CB: TrimaPPLRequestMessage
    CB->>TDM: ProcedurePriorityListRequestReceivedCB()
    TDM->>TOMEs: OnTrimaProcedurePriorityListRequest()
    TOMEs-->>TDM: TrimaProgramProcedurePriorityList
    TDM-->>CB: TrimaPPLResponseMessage
    CB-->>Trima: TrimaPPLResponseMessage

    Note over TOMEs, Trima: Barcode Lookup Request
    Trima->>CB: BarcodeLookupRequestMessage
    CB->>TDM: BarcodeLookupMessageReceivedCB()
    TDM->>TOMEs: OnBarcodeLookup()
    TOMEs-->>TDM: BarcodeLookupResponsePayload
    TDM-->>CB: BarcodeLookupResponseMessage
    CB-->>Trima: BarcodeLookupResponseMessage

    Note over TOMEs, Trima: BBIS Input Request
    Trima->>CB: BbisInputRequestMessage
    CB->>TDM: BbisInputRequestMessageReceivedCB()
    TDM->>TOMEs: OnBbisInputRequest()
    TOMEs-->>TDM: BbisInputResponsePayload
    TDM-->>CB: BbisInputResponseMessage
    CB-->>Trima: BbisInputResponseMessage
```

#### A.7 Alarm and Event Flow

```mermaid
sequenceDiagram
    participant TOMEs as TOMEs 7+
    participant TDM as TrimaDeviceManager
    participant CB as Communications Broker
    participant Trima as Trima V7 Device

    Note over TOMEs, Trima: Alarm Events
    Trima->>CB: TrimaAlarmEventMessage
    CB->>TDM: Event Received
    TDM->>TOMEs: OnAlarmEvent()

    Note over TOMEs, Trima: Operator Actions
    Trima->>CB: TrimaOperatorAlarmAcknowledgementEventMessage
    CB->>TDM: Event Received
    TDM->>TOMEs: OnOperatorAction()

    Note over TOMEs, Trima: Procedure Adjustments
    Trima->>CB: TrimaProcedureAdjustmentEventMessage
    CB->>TDM: Event Received
    TDM->>TOMEs: OnProcedureAdjustment()

    Note over TOMEs, Trima: End of Run Summary
    Trima->>CB: TrimaEndOfRunSummaryEventMessage
    CB->>TDM: Event Received
    TDM->>TOMEs: OnEndOfRunSummary()
```

#### A.8 Regionalization Flow

```mermaid
sequenceDiagram
    participant TOMEs as TOMEs 7+
    participant TDM as TrimaDeviceManager
    participant CB as Communications Broker
    participant Trima as Trima V7 Device

    Note over TOMEs, Trima: Regionalization Feature Setup
    TOMEs->>TDM: SendRegionalizationFeatureToDevice()
    TDM->>CB: ConfigurationBlocksDownloadRequestMessage(RegionalizationFeature)
    CB->>Trima: ConfigurationBlocksDownloadRequestMessage
    Trima-->>CB: ConfigurationBlocksDownloadRequestResponseMessage
    CB-->>TDM: Response Received

    Note over TOMEs, Trima: Regionalization Constant Retrieval
    TOMEs->>TDM: GetRegionalizationConstantFromDevice()
    TDM->>CB: TrimaRegionalizationConstantMessage
    CB->>Trima: TrimaRegionalizationConstantMessage
    Trima-->>CB: TrimaRegionalizationConstantResponseMessage
    CB-->>TDM: Response Received
    TDM-->>TOMEs: Regionalization Constant

    Note over TOMEs, Trima: Confirmation Code Retrieval
    TOMEs->>TDM: GetRegionalizationConfirmationCodeFromDevice()
    TDM->>CB: TrimaRegionalizationConfirmationCodeMessage
    CB->>Trima: TrimaRegionalizationConfirmationCodeMessage
    Trima-->>CB: TrimaRegionalizationConfirmationCodeResponseMessage
    CB-->>TDM: Response Received
    TDM-->>TOMEs: Confirmation Code

    Note over TOMEs, Trima: Feature ID Retrieval
    TOMEs->>TDM: GetRegionalizationFeatureIdFromDevice()
    TDM->>CB: TrimaRegionalizationFeatureIDMessage
    CB->>Trima: TrimaRegionalizationFeatureIDMessage
    Trima-->>CB: TrimaRegionalizationFeatureIDResponseMessage
    CB-->>TDM: Response Received
    TDM-->>TOMEs: Feature ID Information
```

#### A.9 Disconnection Flow

```mermaid
sequenceDiagram
    participant TOMEs as TOMEs 7+
    participant TDM as TrimaDeviceManager
    participant CB as Communications Broker
    participant Trima as Trima V7 Device

    Note over TOMEs, Trima: Normal Disconnection
    TOMEs->>TDM: DisconnectFromCommunicationBroker()
    TDM->>CB: Close WebSocket Connection
    CB->>Trima: Connection Closed
    TDM->>TOMEs: OnCommBrokerDisconnect()

    Note over TOMEs, Trima: Device Disconnection
    Trima->>CB: Connection Lost/Closed
    CB->>TDM: ClientClosedCB()
    TDM->>TDM: StartTrimaDeviceDisconnectTask()
    TDM->>TOMEs: OnTrimaDeviceDisconnectEvent()

    Note over TOMEs, Trima: Reconnection Scenario
    Trima->>CB: Reconnect & Handshake
    CB->>TDM: ClientHandshakeEventReceivedCB()
    TDM->>TDM: ProcessConnectedClient()
    TDM->>TOMEs: OnTrimaDeviceReconnectEvent()
```

#### A.10 Error Handling Flow

```mermaid
sequenceDiagram
    participant TOMEs as TOMEs 7+
    participant TDM as TrimaDeviceManager
    participant CB as Communications Broker
    participant Trima as Trima V7 Device

    Note over TOMEs, Trima: Handshake Failure
    Trima->>CB: ClientHandshakeEventMessage (Failed)
    CB->>TDM: ClientHandshakeEventReceivedCB()
    TDM->>TDM: Log Error & Reject Connection
    
    Note over TOMEs, Trima: Access Level Denied
    TDM->>CB: RequestAccessLevelMessage
    CB->>Trima: RequestAccessLevelMessage
    Trima-->>CB: RequestAccessLevelResponseMessage (Denied)
    CB-->>TDM: RequestAccessLevelResponseMessageReceivedCB()
    TDM-->>TOMEs: Operation Failed

    Note over TOMEs, Trima: Transaction Rollback
    TDM->>CB: RollbackTransactionMessage
    CB->>Trima: RollbackTransactionMessage
    Trima-->>CB: RollbackTransactionResponseMessage
    CB-->>TDM: RollbackTransactionResponseMessageReceivedCB()

    Note over TOMEs, Trima: Communication Timeout
    TDM->>CB: Message with Timeout
    Note over CB, Trima: No Response
    TDM->>TDM: Timeout Handler
    TDM->>TOMEs: Operation Timeout Error
```