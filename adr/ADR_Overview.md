## ADR Timeline of Decisions

*   2020-04-01 – Common – Device and Application Authentication Integration – Accepted
*   2020-06-03 – Common – Dapper, Dapper.Plus & Dapper.Contrib – Accepted
*   2020-06-03 – Infrastructure – Deployment of 3rd Party Services for Atlas – Proposed
*   2020-07-17 – Infrastructure – MQTT Broker Selection – Accepted
*   2020-08-24 – L_A – Device File Transfer – Proposed
*   2020-11-10 – Common – NServiceBus delayed retry policy for TOME 8.0 – Proposed
*   2020-12-28 – Common – Column Type for identifier – Proposed
*   2021-03-02 – Reveos2 – Encryption Algorithm for Protocol Management – Accepted
*   2021-03-11 – Common – Projections for Enterprise platform - Module installation/uninstallation – Proposed
*   2021-05-25 – Common – Message Translation ICD and approach – Accepted
*   2021-06-02 – Common – Rika Connectivity – Accepted
*   2021-07-14 – Common – APM Data Platform – Event Hub Selection – Accepted
*   2021-10-28 – L_A – Tenant Aware Code – multitenancy separation – Accepted
*   2021-11-08 – Common – Id generation – Approved
*   2021-11-22 – Infrastructure – MQTT Security - Enterprise Platform & Tomes 8.1 – Accepted
*   2021-12-11 – Common – Application Localization Library – Accepted
*   2022-01-12 – Common – Projections for Enterprise platform - Deployment Strategy – Accepted
*   2022-01-19 – Common – NServiceBus routing topology for Enterprise platform – Accepted
*   2022-01-19 – Enterprise Platform – NServiceBus routing topology for Enterprise platform – Accepted
*   2022-01-20 – Common – EP Token structure – Accepted
*   2022-01-31 – Common – Strategy for Branching and Releasing a Patch – Accepted
*   2022-04-13 – Common – Common token structure approach for Enterprise platform – Accepted
*   2022-05-16 – Infrastructure – Api Gateway and Authorization approach for Enterprise platform – Accepted
*   2022-06-27 – Common – How should/could Handlers return error code instead of throwing exception – Accepted
*   2022-07-12 – L_A_Rika – Token sharing from GUI shell – Approved
*   2022-07-28 – Common – +TOMEs & EP Token Use – Accepted
*   2022-08-04 – Common – Logging template – Approved
*   2023-03-13 – L_A_Rika – Reuse of Common GUI Shell in Atlas – Accepted
*   2023-06-14 – Common – Semantic Versioning 2.0.0 – Proposed
*   2023-08-02 – Common – R1 and R2 device compatibility – Approved
*   2023-10-04 – Acorn – Optia EOR Data Database Schema – Accepted
*   2023-10-24 – Acorn – Database Encryption – Accepted
*   2024-04-29 – Common – Single lead device across two processors – Approved
*   Unknown – A – Approach for Rika Devices - Device Type and Device Type Version – New
*   Unknown – Common – Atlas Reporting Support – New
*   Unknown – Common – CLAW & QA Naming Conventions – Accepted
*   Unknown – Common – CLAW File Location and Structure – Accepted
*   Unknown – Common – Data Access tool and patterns – Draft
*   Unknown – Common – Device Security - Authentication – New
*   Unknown – Common – Device Security - Communication Encryption – New
*   Unknown – Common – Device Software Update - Database Support – New
*   Unknown – Common – Investigate NServiceBus Unit of Work – New
*   Unknown – Common – Multiple Database Support for Services – New
*   Unknown – Common – Saga usage for Enterprise platform – Unknown
*   Unknown – Drafts – Embedded Device Software and Software Application Messaging (MQTT) contract management and integration plan – Draft
*   Unknown – Drafts – License Provisioning Tool Selection – Draft
*   Unknown – Drafts – Software Application WebAPIs: using OpenAPI 3.0 to define REST webapis – Draft
*   Unknown – L_A – DLog Gathering - Send To Cloud – New
*   Unknown – L_A – Tenant Integration, UserId, Ocelot – Unknown
*   Unknown – Rika – Fleet Inventory Service - Database Support – New
*   Unknown – Security – Certificate Management – Draft
*   Unknown – UI Modularization Proposal – Tenant Integration, UserId, Ocelot – Unknown
*   Not Applicable – General/Template – ADR Template – Template
*   Not Applicable – Infrastructure – Enterprise platform API Gateway investigation: current Ocelot usage – Informational
*   Not Applicable – UI Modularization Proposal – Angular UI Modularization Approaches – Informational

## ADRs

### Acorn

### Database Encryption — Acorn

• Path: [\`Architectural Decision Records/Acorn/ADR - Database Encryption.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Acorn/ADR%20-%20Database%20Encryption.docx)
• Date: 2023-10-24
• Status: Accepted
• Context: Decide how to secure sensitive Optia EOR data in Acorn's database, covering table data and file security.
• Decision: Phase 1: Transparent Data Encryption (TDE). Phase 2: TDE + Always Encrypted for specific needs.
• Impact: TDE: SQL config changes, customer performable. Always Encrypted: Requires enabled driver, query limitations, encrypted views, potential TOMEs code change for views.

### Optia EOR Data Database Schema — Acorn

• Path: [\`Architectural Decision Records/Acorn/ADR - Optia EOR Data Database Schema.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Acorn/ADR%20-%20Optia%20EOR%20Data%20Database%20Schema.docx)
• Date: 2023-10-04
• Status: Accepted
• Context: Decide on the best way to store Optia Data Export XML file to the database.
• Decision: Decided on Hybrid approach (#2) and storing payload in Json format.
• Impact: Need to convert data from XML to JSON.

### A

### Approach for Rika Devices - Device Type and Device Type Version — A

• Path: [\`Architectural Decision Records/bct-data-import-export [A]/ADR - Approach for Rika Devices - Device Type and Device Type Version.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/bct-data-import-export%20%5BA%5D/ADR%20-%20Approach%20for%20Rika%20Devices%20-%20Device%20Type%20and%20Device%20Type%20Version.docx)
• Date: Unknown
• Status: New
• Context: Define approach to get DeviceType and DeviceTypeVersion values during bulk import of Devices/Groups into D&G subsystem from Data Import Export subsystem. These fields are required.
• Decision: Unknown (Decision not yet documented in this ADR)
• Impact: Unknown (Impact not yet documented in this ADR)

### Common

### Single lead device across two processors — Common

• Path: [\`Architectural Decision Records/Common/ADR- Single lead device across two processors.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR-%20Single%20lead%20device%20across%20two%20processors.docx)
• Date: 2024-04-29
• Status: Approved
• Context: Existing implementation creates two lead devices (R1, R2) for facility-level software updates with mixed devices due to separate sagas.
• Decision: Approach 1: Create common saga across R1 and R2 processors to ensure a single lead device for facility-level events, regardless of R1/R2 mix.
• Impact: Software Update subsystem updates. Custom NServiceBus changes for shared tables. Some messages impacted by absence of lead device in one processor.

### Semantic Versioning 2.0.0 — Common

• Path: [\`Architectural Decision Records/Common/ADR - TerumoBCT Semantic Versioning 2.0.0 Implementation Guidance.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20TerumoBCT%20Semantic%20Versioning%202.0.0%20Implementation%20Guidance.docx)
• Date: 2023-06-14
• Status: Proposed
• Context: Software organization software build numbering is currently inconsistent. Proposing use of an open standard for versioning and release management for transparency and clarity.
• Decision: All build processes to follow Semantic Versioning 2.0.0 guidance. Internal build numbering independent of commercial numbering. Effective for all active/future projects.
• Impact: Tasks added to backlogs of active projects to correct build processes/numbering. Inactive projects will adopt this when they become active.

### R1 and R2 device compatibility — Common

• Path: [\`Architectural Decision Records/Common/ADR - ICD Message compatibility and handling.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20ICD%20Message%20compatibility%20and%20handling.docx)
• Date: 2023-08-02
• Status: Approved
• Context: Kinari 2.0 needs to support Rika 1.0 & Rika 2.0 device messages. `BCT.Common.Workflow.Aggregates.CSLib` design changes affect serialization. Hosting R1 & R2 ICDs on same processor causes common library override issues.
• Decision: Separate host process for R1 messages (named with "R1"). Generic named host for R2 and future versions. Pattern for other projects. Messages same version backward compatible; new version if breaking.
• Impact: Software Update, Fleet Inventory, Dlog Management subsystems need updates.

### Logging template — Common

• Path: [\`Architectural Decision Records/Common/ADR - Logging template.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Logging%20template.docx)
• Date: 2022-08-04
• Status: Approved
• Context: Logs often miss necessary info: EventId empty, local datetime used, console logs lack full date, common properties (TenantId, UserId, DeviceSerialNumber) missing.
• Decision: Fix EventId. Use custom Serilog enricher for UTC timestamp. Log service timezone. Add `p:{Properties}`, remove `EventId` from template, add full date. Extend subsystems with properties.
• Impact: `Bct.Common.Business` extended for AMQP handlers (TenantId/UserId). MQTT handlers in each service need individual logic for DeviceSerialNumber/TenantId.

### +TOMEs & EP Token Use — Common

• Path: [\`Architectural Decision Records/Common/ADR - Token Use for TOMEs and EP.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Token%20Use%20for%20TOMEs%20and%20EP.docx)
• Date: 2022-07-28
• Status: Accepted
• Context: EP & TOMEs to share common IDP login and JWT. Need common functionality despite different tech stacks. EP uses Angular JWT security (Auth Guards/Interceptors, Redux for token).
• Decision: Approach 1: EP adds user model & permission validation to GUI Shell (extendable to MFEs). EP token timeout/refresh tested. TOMEs implements token update/refresh/logout against shared Redux token.
• Impact: EP: User model and permission validation method (using enum) to be added. TOMEs: Implement local Redux storage and token refresh/cleanup.

### How should/could Handlers return error code instead of throwing exception — Common

• Path: [\`Architectural Decision Records/Common/ADR - How should-could Handlers return error code instead of throwing exception.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20How%20should-could%20Handlers%20return%20error%20code%20instead%20of%20throwing%20exception.docx)
• Date: 2022-06-27
• Status: Accepted
• Context: How should/could Handlers return error code instead of throwing exception. Currently, no errors from request/response are handled.
• Decision: Approach 2: Using BaseResponse class. Generic `BaseResponse` (with `Errors`, `IsSuccess` properties) consumed by contract class. Errors handled in catch block, properties set.
• Impact: Need to add `BaseResponse` class in every contract repository (e.g., import-export-contract, fleet-inventory-contract) and handle errors in Handler, setting `BaseResponse` properties.

### Common token structure approach for Enterprise platform — Common

• Path: [\`Architectural Decision Records/Common/ADR - Common token structure.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Common%20token%20structure.docx)

• Date: 2022-04-13
• Status: Accepted
• Context: Permissions array in current Security services token needs modification for Enterprise Platform modules. Permission string refactoring needed for easier parsing and less error-proneness.
• Decision: Approach 2: Common token structure across all modules (Keep same structure as Atlas application). Add "tenant_id" key from TOMEs to this common structure.
• Impact: No changes required in Atlas. Some changes required in TOMEs and Ocelot.

### Strategy for Branching and Releasing a Patch — Common

• Path: [\`Architectural Decision Records/Common/ADR - Strategy for Branching and Releasing a Patch.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Strategy%20for%20Branching%20and%20Releasing%20a%20Patch.docx)
• Date: 2022-01-31
• Status: Accepted
• Context: Need to define a strategy for branching and releasing a patch.
• Decision: Use Approach #1: Defines `master`, `develop`, `feature`, `bugfix`, `hotfix`, `archive` branches and their merge workflows. Feature branches: `feature/initials/<featurename>`. Bugfix: `bugfix/initials/<bugfixname>`.
• Impact: N/A

### Projections for Enterprise platform - Deployment Strategy — Common

• Path: [\`Architectural Decision Records/Common/ADR - Projections Approach (Deployment strategy).docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Projections%20Approach%20(Deployment%20strategy).docx)
• Date: 2022-01-12
• Status: Accepted
• Context: Need to choose a deployment strategy for the Projections Service.
• Decision: Databases: Each service has its own DB, using 'projections' schema. Services: Each service stores its own required projections (single deployment model).
• Impact: AuditingService stores Tenant projections. ProgramsService stores device, protocol, event, user, role projections in `bct-programs` DB.

### NServiceBus routing topology for Enterprise platform — Common

• Path: [\`Architectural Decision Records/Common/ADR - NServiceBus routing topology1.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20NServiceBus%20routing%20topology1.docx)
• Date: 2022-01-19
• Status: Accepted
• Context: Need to support deployment of multiple device modules with same common services, ensuring device modules only receive their own/common events, while common modules receive events from all device modules.
• Decision: Use approach #3 (Custom conventional routing). Module events: `Bct.Common.Event:ModuleName:EventName`. Base module events: `Bct.Common.Device:Base:DeviceName`.
• Impact: Update `Bct.Common.NServiceBus` for custom topology. Integrate latest version in all services and TOMEs legacy app, specifying routing keys.

### EP Token structure — Common

• Path: [\`Architectural Decision Records/Common/ADR - EP Token structure.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20EP%20Token%20structure.docx)
• Date: 2022-01-20
• Status: Accepted
• Context: Permissions array in current Security services token needs modification for Enterprise Platform modules. Permission string refactoring needed for easier parsing and less error-proneness.
• Decision: Approach 4: Common Token structure across all modules (Keep same structure as TOMEs application) for 510k release.
• Impact: No changes required in TOMEs and Ocelot for 510k. Security service reviews TOMEs token. GUI Shell uses config for modules/endpoints. Post-510k, standardization can be revisited.

### Application Localization Library — Common

• Path: [\`Architectural Decision Records/Common/ADR - Application Localization.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Application%20Localization.docx)
• Date: 2021-12-11
• Status: Accepted
• Context: Need a common localization component/library/service for Enterprise Platform and integrated application modules.
• Decision: CLAW 2.0 will be used as the localization component for EP and other linked application modules.
• Impact: No impact on other programs currently.

### Id generation — Common

• Path: [\`Architectural Decision Records/Common/ADR - Id generation.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Id%20generation.docx)
• Date: 2021-11-08
• Status: Approved
• Context: Choose approach for generating primary key values for Enterprise Platform, considering future needs like distributed DBs, scaling, and data merging, requiring unique IDs.
• Decision: Use GUIDs (DB- or client-generated) if merging data from different platforms. Otherwise, `bigint` (DB-generated generally, client-generated if special needs). IdGen not used due to complexity.
• Impact: Any option requires refactoring existing approaches (code/DB schemes). Data migration could be significant/complex for some approaches.

### APM Data Platform – Event Hub Selection — Common

• Path: [\`Architectural Decision Records/Common/ADR - Data Platform - Event Hub Selection.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Data%20Platform%20-%20Event%20Hub%20Selection.docx)
• Date: 2021-07-14
• Status: Accepted
• Context: Need mechanism in Azure Cloud for Azure functions to communicate: producer function raises event when file is available for consumer function to process.
• Decision: Azure Event Hub will be used as event sourcing mechanism in APM Data Platform project.
• Impact: No impact on other programs/products currently.

### Rika Connectivity — Common

• Path: [\`Architectural Decision Records/Common/ADR - Rika Connectivity.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Rika%20Connectivity.docx)
• Date: 2021-06-02
• Status: Accepted
• Context: Need to get information from Donor Management System (DMS) to Rika device and from device to DMS. Decide best path for this connection.
• Decision: Take Approach #3: Atlas/Orion App as Middleware. Rika connects to Atlas/Orion via MQTT. Atlas/Orion intermediates with customer systems (DMS, Inventory, Identity).
• Impact: N/A

### Message Translation ICD and approach — Common

• Path: [\`Architectural Decision Records/Common/ADR - Message Translation ICD.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Message%20Translation%20ICD.docx)
• Date: 2021-05-25
• Status: Accepted
• Context: Should automatic message translation be built into Orion R1 devices and Atlas R1 apps? If so, how much support in R1?
• Decision: Implement bare minimum for automatic message translation in R2. R1 Orion devices & Atlas apps publish `RegisterMessageCapabilities` message on startup (Scenario 2.2).
• Impact: Agnostic automatic message translation can be adopted by other devices/apps. Technical debt if not fully implemented, requiring apps to support multiple ICD versions.

### Projections for Enterprise platform - Module installation/uninstallation — Common

• Path: [\`Architectural Decision Records/Common/ADR - Projections Approach (Service registry).docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Projections%20Approach%20(Service%20registry).docx)
• Date: 2021-03-11
• Status: Proposed
• Context: Need to populate projection tables when a new module is registered and decide how to handle data when a module is unregistered and then re-registered.
• Decision: Approach #1 for now: Populate DB without syncing existing data (projections continue saving if module disabled). Can use Approach #2 (data sync) later if needed.
• Impact: Easy to implement initially. Does not support data synchronization if a module is unregistered and then re-registered with intervening changes.

### NServiceBus delayed retry policy for TOME 8.0 — Common

• Path: [\`Architectural Decision Records/Common/ADR - NserviceBus Recoverability Approach.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20NserviceBus%20Recoverability%20Approach.docx)
• Date: 2020-11-10
• Status: Proposed
• Context: NServiceBus default aggressive delayed retry policy causes messages to quickly go to error queue if a service is briefly down, problematic for services needing guaranteed processing.
• Decision: Use Approach 1 (Override NServiceBus immediate/delayed retry policies at startup) for services requiring message delivery guarantee. Number of retries chosen carefully; `Int32.Max` for Auditing.
• Impact: Low cost of ownership. Strategy proposed for `Bct.Common.MessageBus` library used by TOMEs 8.0. No impact on other programs yet.

### Dapper, Dapper.Plus & Dapper.Contrib — Common

• Path: [\`Architectural Decision Records/Common/ADR - Dapper, Dapper.Plus & Dapper.Contrib.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Dapper%2C%20Dapper.Plus%20%26%20Dapper.Contrib.docx)
• Date: 2020-06-03
• Status: Accepted
• Context: Provide common way to map object-oriented domain model to traditional database, relieving developers from relational data persistence programming tasks.
• Decision: Dapper, Dapper.Contrib and Dapper.Plus will be used as the Micro-ORM package for .NET applications.
• Impact: New .NET development uses these libraries for DB access. Existing code recommended for conversion. Supporting multiple DBs requires extra dev work.

### Device and Application Authentication Integration — Common

• Path: [\`Architectural Decision Records/Common/ADR - Device and Application Authentication Integration.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Device%20and%20Application%20Authentication%20Integration.docx)
• Date: 2020-04-01
• Status: Accepted
• Context: Decision needed for authentication implementation for Orion Atlas applications (Phase 1) and Orion device (Phase 2).
• Decision: Support OIDC for Application Authentication. Support API Middleware for Device Authentication (Badge/Pin).
• Impact: Two auth mechanisms (device/app). TOMEs/other apps need to extend Security/Identity for LDAP/AD for backward compatibility. Device auth optimized for "always connected".

### Column Type for identifier — Common

• Path: [\`Architectural Decision Records/Common/ADR - Column type for identifier.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Column%20type%20for%20identifier.docx)
• Date: 2020-12-28
• Status: Proposed
• Context: Need to choose a type for Id columns in service databases, contracts, and external service databases storing projections.
• Decision: MS-SQL: `BigInt` for DB IDs. C# Contracts: `String` (max 32 chars). Internal C# models: `long`. Projection DBs (MS-SQL): `nvarchar(32)`. PostgreSQL TBD.
• Impact: Consumers storing projections must use `nvarchar(32)` for Id columns in MS-SQL, converted from contract string.

### Atlas Reporting Support — Common

• Path: [\`Architectural Decision Records/Common/ADR - Atlas - Atlas Reporting Support.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Atlas%20-%20Atlas%20Reporting%20Support.docx)
• Date: Unknown
• Status: New
• Context: Find best compromise for customer reporting needs (direct DB access requested) without compromising application integrity/delivery. Direct DB access has performance/versioning risks.
• Decision: Unknown (Database Replication Approach is recommended)
• Impact: Sets a precedent different from TOMES. Additional features for DB schema documentation needed in Atlas backlog.

### CLAW & QA Naming Conventions — Common

• Path: [\`Architectural Decision Records/Common/ADR - Localization and QA Naming Conventions for UI.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Localization%20and%20QA%20Naming%20Conventions%20for%20UI.docx)
• Date: Unknown
• Status: Accepted
• Context: Enterprise Platform & Reveos 2 use CLAW. Single CLAW file per sub-system/module requires clear, conflict-free key naming. UI projects need same naming for QA `data-cy` tags.
• Decision: CLAW localization key format: `<Repo - using dots>.<UI/device/other Project>.<page>.<Element ID>`. Example: `Bct.common.auditing.host.home.lblsearch`.
• Impact: Standardizes CLAW key naming and QA `data-cy` tags across specified repositories/projects, improving clarity for translation and development.

### CLAW File Location and Structure — Common

• Path: [\`Architectural Decision Records/Common/ADR - CLAW Files.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20CLAW%20Files.docx)
• Date: Unknown
• Status: Accepted
• Context: Olympus CLAW uses Min.IO but centralizes strings per module, hindering reusability. Manual TechCom process is time-consuming. Need to streamline and improve reusability.
• Decision: Option 1: Maintain JSON CLAW files in `bct-common-olympus-claw-resources`, split by bounded context (repo/MFE). CI pipeline builds versioned artifacts. TechCom uses Excel, converts to/from JSON.
• Impact: Local dev copies CLAW JSON to Min.IO. Tenant-specific content uses `/Tenants/[Tenant-Id]/[ModuleName]/[Subsystem]` Min.IO structure.

### Data Access tool and patterns — Common

• Path: [\`Architectural Decision Records/Common/ADR - DataAccess Tool and Patterns.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20DataAccess%20Tool%20and%20Patterns.docx)
• Date: Unknown
• Status: Draft
• Context: Provide common data access layer approach. Decide on tool for object-oriented domain model to traditional database mapping and data access layer pattern.
• Decision: Unknown (Approach 1 - using common libraries for Dapper via `Bct.Common.DataAccess` - is recommended)
• Impact: Unknown

### Device Security - Authentication — Common

• Path: [\`Architectural Decision Records/Common/ADR - Device Security - Authentication.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Device%20Security%20-%20Authentication.docx)
• Date: Unknown
• Status: New
• Context: A device connecting to an application via MQTT Broker needs to identify itself. This ADR decides how devices authenticate with applications using MQTT.
• Decision: Unknown (Barcode Scan to fully configure authentication settings is recommended)
• Impact: Unknown

### Device Security - Communication Encryption — Common

• Path: [\`Architectural Decision Records/Common/ADR - Device Security - Communication Encryption.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Device%20Security%20-%20Communication%20Encryption.docx)
• Date: Unknown
• Status: New
• Context: Decide what mechanism, if any, will encrypt data in transport between a device and an MQTT Broker when the device connects to an application.
• Decision: Unknown (Encrypt via TLS with full configuration via Barcode Scan is recommended)
• Impact: TOMES could make a tighter integration to the broker, and make the workflow of adding a device easier.

### Device Software Update - Database Support — Common

• Path: [\`Architectural Decision Records/Common/ADR - Device Software Update - Database Support.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Device%20Software%20Update%20-%20Database%20Support.docx)
• Date: Unknown
• Status: New
• Context: Does Device Software Update need to support PostgreSQL and SQL Server? Service handles scheduled staging/remote installation of device software, including p2p network for updates.
• Decision: Minimalist Approach (PostgreSQL only initially) recommended. Future support for other DBs requires adding scaffolding and provider implementation.
• Impact: Next program/application needing the service must reopen it to add multi-DB scaffolding and support its own DB provider.

### Investigate NServiceBus Unit of Work — Common

• Path: [\`Architectural Decision Records/Common/ADR - Investigate NServiceBus Unit of Work.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Investigate%20NServiceBus%20Unit%20of%20Work.docx)
• Date: Unknown
• Status: New
• Context: NServiceBus unit of work allows wrapping handler calls for custom code before/after, and error handling for multi-handler requests to prevent partial updates.
• Decision: Unknown (`IBehavior` interface implementation is recommended)
• Impact: Code change required for Import Export / Software Update / Fleet Inventory microservices.

### Multiple Database Support for Services — Common

• Path: [\`Architectural Decision Records/Common/ADR - Multiple Database Support for Services.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Multiple%20Database%20Support%20for%20Services.docx)
• Date: Unknown
• Status: New
• Context: What level of effort should new services put into supporting both PostgreSQL (Atlas) and SQL Server (TOMES)?
• Decision: Unknown ("Case by Case Approach" is recommended)
• Impact: Individuals from other products need to be part of the evaluation process to determine if services should support multiple databases.

### Saga usage for Enterprise platform — Common

• Path: [\`Architectural Decision Records/Common/ADR - Saga usage.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Saga%20usage.docx)
• Date: Unknown
• Status: Unknown
• Context: Identify cases needing a sequence of actions in several microservices after one UI user action. For each, consider options (Saga, Soft Deletion) and decide if sagas are needed.
• Decision: Unknown (Document outlines issues and options but records no final decision)
• Impact: Unknown

### Drafts

### License Provisioning Tool Selection — Drafts

• Path: [\`Architectural Decision Records/Drafts/ADR - License Provisioning Tool.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Drafts/ADR%20-%20License%20Provisioning%20Tool.docx)
• Date: Unknown
• Status: Draft
• Context: Terumo BCT uses an in-house tool for TOMEs licenses. Olympus, using SoftwareKey's new model (token/feature licenses), needs a similar tool. This ADR explores approaches.
• Decision: No decision has been made yet.
• Impact: Unknown

### Software Application WebAPIs: using OpenAPI 3.0 to define REST webapis — Drafts

• Path: [\`Architectural Decision Records/Drafts/ADR - Software Application Subsystems WebAPIs Patterns (DRAFT).docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Drafts/ADR%20-%20Software%20Application%20Subsystems%20WebAPIs%20Patterns%20(DRAFT).docx)
• Date: Unknown
• Status: Draft
• Context: Implied: Defining how Software Application Subsystem WebAPIs should be created.
• Decision: Use OpenAPI 3.0 as is (no extensions). All WebAPIs generated from YAML file.
• Impact: Unknown

### Embedded Device Software and Software Application Messaging (MQTT) contract management and integration plan — Drafts

• Path: [\`Architectural Decision Records/Drafts/ADR- SW - Messaging (MQTT) contract management and integration plan.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Drafts/ADR-%20SW%20-%20Messaging%20(MQTT)%20contract%20management%20and%20integration%20plan.docx)
• Date: Unknown
• Status: Draft
• Context: Plan for managing MQTT message contracts between embedded device software and software applications.
• Decision: Device side owns MQTT message repos. Standard messages repo with "slices" per message type (NuGet packages). Device/App mono-repos sync message versions from "Release" builds.
• Impact: Standard messages repo refactoring. `dlog-management`/`software-upgrade` messages merge. App side infrastructure work and move to mono-repo.

### Enterprise Platform

### NServiceBus routing topology for Enterprise platform — Enterprise Platform

• Path: [\`Architectural Decision Records/ADR - NServiceBus routing topology.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/ADR%20-%20NServiceBus%20routing%20topology.docx)
• Date: 2022-01-19
• Status: Accepted
• Context: Need to support deployment of multiple device modules with same common services, ensuring device modules only receive their own/common events, while common modules receive events from all device modules.
• Decision: Use approach #3 (Custom conventional routing). Module events: `Bct.Common.Event:ModuleName:EventName`. Base module events: `Bct.Common.Device:Base:DeviceName`.
• Impact: Update `Bct.Common.NServiceBus` for custom topology. Integrate latest version in all services and TOMEs legacy app, specifying routing keys.

### General/Template

### ADR Template — General/Template

• Path: [\`Architectural Decision Records/ADR Template.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/ADR%20Template.docx)
• Date: Not Applicable
• Status: Template
• Context: Not Applicable (This is a template document for ADRs)
• Decision: Not Applicable (This is a template document for ADRs)
• Impact: Not Applicable (This is a template document for ADRs)

### Infrastructure

### Api Gateway and Authorization approach for Enterprise platform — Infrastructure

• Path: [\`Architectural Decision Records/Infrastructure/ADR - Api Gateway.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Infrastructure/ADR%20-%20Api%20Gateway.docx)
• Date: 2022-05-16
• Status: Accepted
• Context: Need to choose an approach for authorization of endpoints for the Enterprise platform.
• Decision: Approach #1: Ocelot as API Gateway for authentication/routing (JWT tokens) and claims-based authorization. Services behind firewall.
• Impact: "Bct Api Gateway" must be .NET. Atlas (Kinari) & Orion (Rika) microservices need updates/retesting. Works for TOMEs, CPA; Atlas needs changes.

### MQTT Security - Enterprise Platform & Tomes 8.1 — Infrastructure

• Path: [\`Architectural Decision Records/Infrastructure/ADR - Olympus- MQTT Security.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Infrastructure/ADR%20-%20Olympus-%20MQTT%20Security.docx)
• Date: 2021-11-22
• Status: Accepted
• Context: MQTT requires a secure TLS channel. This document describes transport encryption and certificate requirements for Tomes 8.1 (2022) and Enterprise Platform (2022+).
• Decision: Digicert or customer's trusted CA certificate on MQTT Broker. Root CA cert on MQTT clients (server platform, medical devices). Recommend 3-year cert expiration.
• Impact: MQTT connection fails if server or root CA cert expires; devices should be deactivated.

### MQTT Broker Selection — Infrastructure

• Path: [\`Architectural Decision Records/Infrastructure/ADR - MQTT Broker Selection.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Infrastructure/ADR%20-%20MQTT%20Broker%20Selection.docx)
• Date: 2020-07-17
• Status: Accepted
• Context: MQTT 5.0 selected for device-application communication, requiring a broker. RabbitMQ (preferred) doesn't support MQTT 5. Need to pick a broker for products needing MQTT.
• Decision: "Diverged OSS Solution, with Intention of Merging": Atlas uses VerneMQ (Linux/k8s); TOMES/CPA use Mosquitto (Windows). Plan to migrate to RabbitMQ later.
• Impact: TOMES and Atlas will use different brokers for an unknown period.

### Deployment of 3rd Party Services for Atlas — Infrastructure

• Path: [\`Architectural Decision Records/Infrastructure/ADR - Deployment of 3rd Party Services for Atlas.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Infrastructure/ADR%20-%20Deployment%20of%203rd%20Party%20Services%20for%20Atlas.docx)
• Date: 2020-06-03
• Status: Proposed
• Context: Atlas relies on multiple 3rd party services. Need to decide how these are installed on customer sites.
• Decision: Immediately "Decouple 3rd Party Services from Atlas Packaging," then move toward "Decouple ... AND Create A Means for Installing 3rd Party Software" over time.
• Impact: Atlas Helm Chart changes for config-based deployment. Prerequisites added to packaging. Existing ingested 3rd party charts/images removed.

### Enterprise platform API Gateway investigation: current Ocelot usage — Infrastructure

• Path: [\`Architectural Decision Records/Infrastructure/API Gateway - Ocelot usage on TOMEs.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Infrastructure/API%20Gateway%20-%20Ocelot%20usage%20on%20TOMEs.docx)
• Date: Not Applicable
• Status: Informational
• Context: Ocelot is a .NET API Gateway. TOMEs uses Ocelot. Document compares Ocelot and NGINX features.
• Decision: Not Applicable (This document describes current Ocelot usage and features, not a new decision.)
• Impact: Not Applicable

### L_A

### Tenant Aware Code – multitenancy separation — L_A

• Path: [\`Architectural Decision Records/bct-common-tenant [L_A]/ADR Tenant Aware Code.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/bct-common-tenant%20%5BL_A%5D/ADR%20Tenant%20Aware%20Code.docx)
• Date: 2021-10-28
• Status: Accepted
• Context: Tenants' data must be segregated; each tenant views only their data. This is crucial for multitenant deployments.
• Decision: Code must be tenant-aware (logical multitenancy) as physical separation isn't always guaranteed. Tenant ID to be SAP ID. Utilize physical separation when possible.
• Impact: Additional logic needs to be implemented in each microservice.

### Device File Transfer — L_A

• Path: [\`Architectural Decision Records/bct-common-dlog-management [L_A]/ADR - Device File Transfer.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/bct-common-dlog-management%20%5BL_A%5D/ADR%20-%20Device%20File%20Transfer.docx)
• Date: 2020-08-24
• Status: Proposed
• Context: Deployed devices need to transfer files (e.g., Dlogs) securely to/from servers. Legacy FTP/HTTP are insecure. New solution needs reliability, encryption, and bandwidth limiting.
• Decision: The device should use the CURL file transfer library.
• Impact: Impacts Cadence/legacy devices by changing dlog collection file transfer. Affects Cadence, Atlas application, and potentially STS for legacy devices.

### DLog Gathering - Send To Cloud — L_A

• Path: [\`Architectural Decision Records/bct-common-dlog-management [L_A]/ADR - DLog Gathering - Send To Cloud.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/bct-common-dlog-management%20%5BL_A%5D/ADR%20-%20DLog%20Gathering%20-%20Send%20To%20Cloud.docx)
• Date: Unknown
• Status: New
• Context: A build vs. buy decision is needed for transferring DLog files from applications (Atlas, CPA, TOMEs) to cloud storage, with Atlas being the first implementer.
• Decision: Unknown (Decision not yet documented in this ADR)
• Impact: Unknown (Impact not yet documented in this ADR)

### Tenant Integration, UserId, Ocelot — L_A

• Path: [\`Architectural Decision Records/bct-common-tenant [L_A]/ADR - Tenant Integration.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/bct-common-tenant%20%5BL_A%5D/ADR%20-%20Tenant%20Integration.docx)
• Date: Unknown
• Status: Unknown
• Context: For Tomes 8.1 Reveos 2+, need a way to authenticate/authorize users and pass user/tenant info to web APIs.
• Decision: Token parsed in Ocelot; claims (TenantId, UserId) passed as data to web APIs. Microservices run anonymously.
• Impact: Decouples auth from microservices, simpler testing. Security not at microservice level; firewall/API key needed. Config/code sync risk.

### L_A_Rika

### Reuse of Common GUI Shell in Atlas — L_A_Rika

• Path: [\`Architectural Decision Records/bct-common-gui-shell [L_A_Rika]/ADR - Atlas GUI Shell.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/bct-common-gui-shell%20%5BL_A_Rika%5D/ADR%20-%20Atlas%20GUI%20Shell.docx)
• Date: 2023-03-13
• Status: Accepted
• Context: Atlas uses MFE federation like Olympus but has different styles/layouts. Need to consolidate GUI shells into one common, themeable shell for Atlas/Olympus.
• Decision: Use a Standard or Common GUI Shell Approach. Upgrade current Olympus common GUI shell to support Atlas/Kinari differences via theming.
• Impact: Reduces maintenance for Angular/TypeScript. Common shell becomes more flexible, encouraging reuse. Better code reuse and lower cost for future products/styles.

### Token sharing from GUI shell — L_A_Rika

• Path: [\`Architectural Decision Records/bct-common-gui-shell [L_A_Rika]/ADR - Token sharing from GUI shell.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/bct-common-gui-shell%20%5BL_A_Rika%5D/ADR%20-%20Token%20sharing%20from%20GUI%20shell.docx)
• Date: 2022-07-12
• Status: Approved
• Context: How to securely store/share JWT. GUI shell stores decoded token in redux; MFEs need encoded token for API calls and a common access method.
• Decision: GUI shell adds encoded token to redux. New NPM library for MFE token access (encoded/decoded, permissions). Decoded token in redux store temporary. Library in `bct-common-olympus-gui-shell` repo.
• Impact: MFEs can get token once updated on redux store. Common library for token utilization.

### Reveos2

### Encryption Algorithm for Protocol Management — Reveos2

• Path: [\`Architectural Decision Records/bct-common-protocolmanagement [Reveos2]/ADR - Protocol Management Encryption Mechanism.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/bct-common-protocolmanagement%20%5BReveos2%5D/ADR%20-%20Protocol%20Management%20Encryption%20Mechanism.docx)
• Date: 2021-03-02
• Status: Accepted
• Context: An encryption mechanism must be chosen to encrypt sensitive data contained in .proto files for the Protocol Management subsystem.
• Decision: AES-256 and its derivatives will be used for encryption/decryption for Protocol Management.
• Impact: No impact. Other programs may benefit from already used code in `bct-common-security`.

### Rika

### Fleet Inventory Service - Database Support — Rika

• Path: [\`Architectural Decision Records/bct-fleet-inventory [Rika]/ADR - Fleet Inventory - Database Support.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/bct-fleet-inventory%20%5BRika%5D/ADR%20-%20Fleet%20Inventory%20-%20Database%20Support.docx)
• Date: Unknown
• Status: New
• Context: Does Fleet Inventory Service need to support PostgreSQL and SQL Server? The service views fleet state (connection, software version, scheduled upgrades).
• Decision: Unknown (Minimalist Approach - PostgreSQL only initially - is recommended)
• Impact: Next program/application needing the service must reopen it to add scaffolding for multiple DB providers and support its own DB provider.

### Security

### Certificate Management — Security

• Path: [\`Architectural Decision Records/Certificate Management.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Certificate%20Management.docx)
• Date: Unknown
• Status: Draft
• Context: Terumo BCT needs a unified solution to certificate management across applications and devices, usable in all customer environments and application deployment types.
• Decision: Unknown (Decision not yet documented in this ADR)
• Impact: Unknown (Impact not yet documented in this ADR)

### UI Modularization Proposal

### Tenant Integration, UserId, Ocelot — UI Modularization Proposal

• Path: [\`Architectural Decision Records/UI Modularization Proposal/ADR - Tenant Integration.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/UI%20Modularization%20Proposal/ADR%20-%20Tenant%20Integration.docx)
• Date: Unknown
• Status: Unknown
• Context: For Tomes 8.1 Reveos 2+, need a way to authenticate/authorize users and pass user/tenant info to web APIs.
• Decision: Token parsed in Ocelot; claims (TenantId, UserId) passed as data to web APIs. Microservices run anonymously.
• Impact: Decouples auth from microservices, simpler testing. Security not at microservice level; firewall/API key needed. Config/code sync risk.

### Angular UI Modularization Approaches — UI Modularization Proposal

• Path: [\`Architectural Decision Records/UI Modularization Proposal/Angular UI Modularization.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/UI%20Modularization%20Proposal/Angular%20UI%20Modularization.docx)
• Date: Not Applicable
• Status: Informational
• Context: To modularize an Angular application by feature, allowing individual feature modules (built separately) to be added to a main application at deployment without rebuilding the main app.
• Decision: Not Applicable (Document explores multiple approaches: Iframe, Angular Compiler, Angular Package/Library, Web Components/Angular Elements, without selecting one.)
• Impact: Not Applicable

## Open Questions / Gaps

*   **ADRs with Undetermined Dates**:
    *   [\`Architectural Decision Records/bct-data-import-export [A]/ADR - Approach for Rika Devices - Device Type and Device Type Version.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/bct-data-import-export%20%5BA%5D/ADR%20-%20Approach%20for%20Rika%20Devices%20-%20Device%20Type%20and%20Device%20Type%20Version.docx) (Status: New)
    *   [\`Architectural Decision Records/Common/ADR - Atlas - Atlas Reporting Support.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Atlas%20-%20Atlas%20Reporting%20Support.docx) (Status: New)
    *   [\`Architectural Decision Records/Common/ADR - CLAW & QA Naming Conventions.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Localization%20and%20QA%20Naming%20Conventions%20for%20UI.docx) (Status: Accepted)
    *   [\`Architectural Decision Records/Common/ADR - CLAW Files.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20CLAW%20Files.docx) (Status: Accepted)
    *   [\`Architectural Decision Records/Common/ADR - DataAccess Tool and Patterns.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20DataAccess%20Tool%20and%20Patterns.docx) (Status: Draft)
    *   [\`Architectural Decision Records/Common/ADR - Device Security - Authentication.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Device%20Security%20-%20Authentication.docx) (Status: New)
    *   [\`Architectural Decision Records/Common/ADR - Device Security - Communication Encryption.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Device%20Security%20-%20Communication%20Encryption.docx) (Status: New)
    *   [\`Architectural Decision Records/Common/ADR - Device Software Update - Database Support.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Device%20Software%20Update%20-%20Database%20Support.docx) (Status: New)
    *   [\`Architectural Decision Records/Common/ADR - Investigate NServiceBus Unit of Work.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Investigate%20NServiceBus%20Unit%20of%20Work.docx) (Status: New)
    *   [\`Architectural Decision Records/Common/ADR - Multiple Database Support for Services.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Multiple%20Database%20Support%20for%20Services.docx) (Status: New)
    *   [\`Architectural Decision Records/Common/ADR - Saga usage.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Saga%20usage.docx) (Status: Unknown)
    *   [\`Architectural Decision Records/Drafts/ADR - License Provisioning Tool.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Drafts/ADR%20-%20License%20Provisioning%20Tool.docx) (Status: Draft)
    *   [\`Architectural Decision Records/Drafts/ADR - Software Application Subsystems WebAPIs Patterns (DRAFT).docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Drafts/ADR%20-%20Software%20Application%20Subsystems%20WebAPIs%20Patterns%20(DRAFT).docx) (Status: Draft)
    *   [\`Architectural Decision Records/Drafts/ADR- SW - Messaging (MQTT) contract management and integration plan.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Drafts/ADR-%20SW%20-%20Messaging%20(MQTT)%20contract%20management%20and%20integration%20plan.docx) (Status: Draft)
    *   [\`Architectural Decision Records/bct-common-dlog-management [L_A]/ADR - DLog Gathering - Send To Cloud.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/bct-common-dlog-management%20%5BL_A%5D/ADR%20-%20DLog%20Gathering%20-%20Send%20To%20Cloud.docx) (Status: New)
    *   [\`Architectural Decision Records/bct-common-tenant [L_A]/ADR - Tenant Integration.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/bct-common-tenant%20%5BL_A%5D/ADR%20-%20Tenant%20Integration.docx) (Status: Unknown)
    *   [\`Architectural Decision Records/bct-fleet-inventory [Rika]/ADR - Fleet Inventory - Database Support.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/bct-fleet-inventory%20%5BRika%5D/ADR%20-%20Fleet%20Inventory%20-%20Database%20Support.docx) (Status: New)
    *   [\`Architectural Decision Records/Certificate Management.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Certificate%20Management.docx) (Status: Draft)
    *   [\`Architectural Decision Records/UI Modularization Proposal/ADR - Tenant Integration.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/UI%20Modularization%20Proposal/ADR%20-%20Tenant%20Integration.docx) (Status: Unknown)
*   **ADRs Not Finalized (Draft/New/Proposed/Unknown Status)**: (Many listed above, plus those with explicit non-Accepted status like "Proposed")
    *   See full list above under "ADRs with Undetermined Dates" as many overlap.
    *   Explicitly "Proposed":
        *   [\`Architectural Decision Records/Common/ADR - Column type for identifier.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Column%20type%20for%20identifier.docx)
        *   [\`Architectural Decision Records/Common/ADR - NserviceBus Recoverability Approach.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20NserviceBus%20Recoverability%20Approach.docx)
        *   [\`Architectural Decision Records/Common/ADR - Projections Approach (Service registry).docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20Projections%20Approach%20(Service%20registry).docx)
        *   [\`Architectural Decision Records/Common/ADR - TerumoBCT Semantic Versioning 2.0.0 Implementation Guidance.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Common/ADR%20-%20TerumoBCT%20Semantic%20Versioning%202.0.0%20Implementation%20Guidance.docx)
        *   [\`Architectural Decision Records/Infrastructure/ADR - Deployment of 3rd Party Services for Atlas.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/Infrastructure/ADR%20-%20Deployment%20of%203rd%20Party%20Services%20for%20Atlas.docx)
        *   [\`Architectural Decision Records/bct-common-dlog-management [L_A]/ADR - Device File Transfer.docx\`](https://terumobct.sharepoint.com/:w:/r/sites/rd/crossproductsoftware/Components/Architectural%20Decision%20Records/bct-common-dlog-management%20%5BL_A%5D/ADR%20-%20Device%20File%20Transfer.docx)