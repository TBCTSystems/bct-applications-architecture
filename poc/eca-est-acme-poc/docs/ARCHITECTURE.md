# ECA PoC System Architecture

## Overview

The Edge Certificate Agent (ECA) Proof of Concept demonstrates a complete, automated certificate lifecycle management system designed for containerized edge environments. This document provides a comprehensive architectural overview of the system, describing its components, communication patterns, data model, and security considerations.

### System Goals

The ECA PoC validates the feasibility of **zero-touch certificate management** for distributed edge deployments where manual intervention is impractical or impossible. The system addresses two critical use cases:

1. **Automated Server Certificate Management (ECA-ACME)**: Enables web servers and HTTPS endpoints to automatically obtain, renew, and install TLS certificates using the ACME (Automatic Certificate Management Environment) protocol, eliminating manual certificate operations and preventing service disruptions due to certificate expiry.

2. **Automated Client Certificate Management (ECA-EST)**: Enables devices, services, and applications requiring mutual TLS authentication to automatically enroll for client certificates and renew them before expiration using the EST (Enrollment over Secure Transport) protocol, supporting secure device identity management at scale.

By combining these two complementary agents with a modern PKI infrastructure, the ECA PoC delivers a complete certificate management ecosystem suitable for IoT deployments, edge computing platforms, and microservices architectures where certificate lifecycle automation is essential for operational efficiency and security.

### Approach

The ECA system implements autonomous certificate lifecycle management through **intelligent polling agents** that operate as sidecar containers alongside target services. These agents continuously monitor certificate expiry status, proactively initiate renewal workflows before certificates expire, and automatically install new certificates with zero-downtime service reloads.

Key architectural principles guiding the design:

- **Autonomy**: Agents operate independently without requiring central orchestration, making the system resilient to network partitions and suitable for edge environments with intermittent connectivity.

- **Separation of Concerns**: Certificate management logic is completely decoupled from target service business logic through the sidecar pattern, allowing existing services to gain automated certificate management without code modifications.

- **Protocol Standardization**: The system leverages industry-standard protocols (ACME RFC 8555, EST RFC 7030) ensuring interoperability with any compliant PKI infrastructure, not just the step-ca implementation used in this PoC.

- **Observability**: Comprehensive structured logging provides visibility into certificate lifecycle events, enabling monitoring, auditing, and troubleshooting without requiring direct container access.

- **Testability**: Modular component design with clear interfaces enables comprehensive unit testing and integration testing, ensuring reliability in production edge deployments.

The PoC is implemented as a self-contained Docker Compose environment, demonstrating the complete system on a single host while using architectural patterns that scale to distributed multi-host deployments.

## Architectural Style

The ECA system adopts a **hybrid architectural style** combining three complementary patterns:

### Event-Driven Architecture (Time-Based Events)

Certificate agents function as autonomous event processors where "events" are time-based triggers (polling intervals) and certificate lifecycle state transitions (near-expiry detection). Unlike traditional event-driven systems with message queues or event streams, this architecture uses **polling loops** as the event detection mechanism.

Each agent runs a continuous loop:
1. **Detect**: Check current certificate status (parse expiry date, calculate remaining validity)
2. **Decide**: Apply business rules to determine if action is needed (threshold-based renewal, force triggers)
3. **Act**: Execute renewal workflow if needed (protocol interaction, installation, service reload)
4. **Sleep**: Wait for next polling interval

This approach is optimal for edge environments because:
- **Simplicity**: No external scheduler or message broker dependencies reduce deployment complexity
- **Resilience**: Temporary failures (network issues, CA downtime) are automatically retried on the next polling cycle without requiring explicit retry logic
- **Resource Efficiency**: Sleep intervals prevent unnecessary CPU consumption while still providing timely renewals

### Microservices Pattern

Each certificate agent is an **independent, single-purpose service** with clear boundaries and minimal dependencies:

- **ECA-ACME Agent**: Exclusively responsible for server certificate lifecycle (ACME protocol)
- **ECA-EST Agent**: Exclusively responsible for client certificate lifecycle (EST protocol)
- **PKI Service (step-ca)**: Exclusively responsible for certificate issuance and validation
- **Target Services**: Exclusively responsible for their business logic (web serving, API calls)

Service independence provides critical benefits:
- **Fault Isolation**: If the ACME agent fails, the EST agent continues operating normally
- **Independent Scaling**: Each service requiring certificates gets its own agent instance
- **Technology Diversity**: Different agents can be implemented in different languages if needed (though this PoC uses PowerShell for all agents)
- **Testability**: Each service can be tested in isolation with mocked dependencies

### Sidecar Pattern

Certificate agents operate as **sidecar containers** deployed alongside target services they manage. The sidecar pattern provides:

- **Loose Coupling**: Target services remain unaware of certificate management implementation
- **Lifecycle Management**: Agent containers can be updated independently of target services
- **Resource Isolation**: Agent resource consumption (CPU, memory, network) is isolated from target service resources
- **Deployment Simplicity**: Adding certificate management to a new service requires only adding an agent container to the Docker Compose configuration

### Why This Hybrid Style Fits

The combination of these three patterns creates an architecture uniquely suited to edge certificate management:

1. **Autonomy**: Agents don't require external orchestration, making them deployable in disconnected or intermittently-connected environments
2. **Simplicity**: The polling-based event model eliminates complex event infrastructure while still providing timely lifecycle management
3. **Extensibility**: New agent types (e.g., for different protocols or certificate types) can be added without modifying existing components
4. **Operational Efficiency**: Zero-touch automation eliminates manual certificate operations, reducing operational overhead and eliminating human error

## Technology Stack

The following technologies were selected to balance PoC requirements (rapid development, comprehensive demonstration) with production readiness (industry standards, proven reliability):

| **Category** | **Technology** | **Version** | **Justification** |
|--------------|----------------|-------------|-------------------|
| **Agent Language** | PowerShell Core | 7.4+ | Primary language per project constraints. Cross-platform runtime, Docker-native, excellent built-in support for HTTP protocol scripting, JSON parsing, and X.509 certificate operations. Rich .NET cryptography libraries eliminate need for external crypto dependencies. |
| **Container Runtime** | Docker | 20.10+ | Industry-standard containerization platform required by project constraints. Provides process isolation, resource limits, network abstraction, and volume management essential for multi-service PoC orchestration. |
| **Orchestration** | Docker Compose | 2.x | Sufficient for single-host PoC demonstration. Simple YAML-based declarative configuration, integrated with Docker CLI, supports service dependencies, volume management, and network configuration without Kubernetes complexity. |
| **PKI Infrastructure** | Smallstep step-ca | 0.25+ | Modern open-source Certificate Authority with native ACME and EST protocol support. Designed specifically for cloud-native and edge scenarios, providing lightweight CA suitable for containerized deployment. API-first design simplifies agent integration. |
| **Target Server** | NGINX | 1.25+ Alpine | Industry-standard high-performance web server. Supports graceful configuration reload via SIGHUP signal enabling zero-downtime certificate rotation. Minimal Alpine-based image reduces attack surface and resource footprint. |
| **Target Client** | Alpine Linux + curl | 3.19+ | Lightweight container for mutual TLS client demonstrations. Includes curl with OpenSSL support for HTTPS requests with client certificate authentication. Minimal base image (5MB) ideal for edge deployment simulation. |
| **Test Framework** | Pester | 5.5+ | De facto PowerShell testing framework. Supports mocking, assertions, code coverage reporting, and BDD-style test organization. Essential for achieving comprehensive test coverage objective. |
| **Logging** | Structured stdout/stderr | N/A | Docker best practice for containerized logging. JSON-structured logs enable machine parsing and log aggregation. Plain text alternative supports human readability during development. No external logging dependencies required. |
| **Web Dashboard** | Node.js + Express | 20 LTS | (Optional/Stretch Goal) Lightweight web framework for monitoring UI. JavaScript/TypeScript enables rapid prototyping. Express middleware ecosystem provides WebSocket support for real-time certificate status updates. |

This technology stack minimizes external dependencies while leveraging industry-standard protocols and tools, ensuring the PoC demonstrates production-viable patterns rather than toy implementations.

## System Components

The ECA PoC consists of six primary services, each deployed as an independent Docker container. This section describes each component's purpose, technology foundation, key responsibilities, and communication interfaces.

### PKI Service (step-ca)

**Purpose**: The PKI service provides the foundational certificate authority infrastructure, implementing both ACME and EST protocols to issue certificates in response to agent requests. It maintains the root of trust for the entire system.

**Technology**: Smallstep step-ca 0.25+ running in an Alpine Linux container. The CA is configured with a root certificate, intermediate certificate, ACME provisioner for server certificates, and EST provisioner for client certificates.

**Key Responsibilities**:
- Issue server certificates in response to ACME protocol requests (newOrder, finalize flows)
- Issue client certificates in response to EST protocol requests (simpleenroll, simplereenroll)
- Validate domain control via HTTP-01 ACME challenges (fetch `.well-known/acme-challenge` tokens)
- Validate bootstrap tokens for initial EST enrollment
- Validate existing client certificates for EST re-enrollment using mutual TLS
- Maintain CA database of issued certificates and serial numbers
- Serve CA root and intermediate certificates for trust chain validation

**Communication Interfaces**:
- **HTTPS API (ACME)**: Exposes RESTful ACME v2 endpoints on port 9000 (`/acme/{provisioner}/directory`, `/acme/{provisioner}/new-order`, etc.)
- **HTTPS API (EST)**: Exposes EST endpoints on port 9000 (`/.well-known/est/{provisioner}/simpleenroll`, `/simplereenroll`, `/cacerts`)
- **HTTP Challenge Validation**: Makes outbound HTTP requests to port 80 on target-server to validate HTTP-01 challenges
- **Persistent Volume**: Stores CA database and configuration on `pki-data` Docker volume

### ECA-ACME Agent

**Purpose**: The ACME agent autonomously manages the complete server certificate lifecycle for the NGINX target server, ensuring certificates are renewed before expiration and installed with zero-downtime service reloads.

**Technology**: PowerShell Core 7.4+ running in an Alpine Linux container. Leverages shared PowerShell modules (`Logger.psm1`, `CryptoHelper.psm1`, `ConfigManager.psm1`, `FileOperations.psm1`) and implements ACME v2 protocol client logic.

**Key Responsibilities**:
- Monitor server certificate expiry status by parsing certificate files and calculating remaining validity period
- Initiate certificate renewal when remaining validity falls below configured threshold (default 33% of total lifetime)
- Generate RSA or ECDSA private keys using cryptographically secure random number generators
- Create Certificate Signing Requests (CSRs) with appropriate Subject Alternative Names (SANs)
- Implement ACME v2 protocol workflow: account registration, order creation, HTTP-01 challenge fulfillment, order finalization, certificate download
- Install renewed certificates atomically to shared volume using temporary files and atomic rename operations
- Trigger NGINX configuration reload via Docker exec and SIGHUP signal for zero-downtime certificate activation
- Provide structured logging of all lifecycle events (checks, renewals, installations, errors)
- Support manual renewal triggers via environment variable flags for testing and demonstration

**Communication Interfaces**:
- **HTTPS Client (ACME)**: Synchronous REST API calls to step-ca on port 9000 for ACME protocol operations
- **HTTP Server (Challenge)**: Runs temporary HTTP server on port 80 to respond to ACME HTTP-01 challenges
- **Shared Volume Write**: Writes certificate and private key files to `server-certs` volume
- **Docker Exec**: Executes `nginx -s reload` command in target-server container to trigger graceful reload
- **Environment Variables**: Reads configuration (CA URL, domain name, renewal threshold, check interval)

### ECA-EST Agent

**Purpose**: The EST agent autonomously manages the complete client certificate lifecycle for the target client, handling both initial enrollment (using bootstrap token) and re-enrollment (using existing certificate) before expiration.

**Technology**: PowerShell Core 7.4+ running in an Alpine Linux container. Shares common modules with ACME agent and implements EST (RFC 7030) protocol client logic.

**Key Responsibilities**:
- Monitor client certificate expiry status by parsing certificate files and calculating remaining validity period
- Perform initial enrollment using pre-shared bootstrap token via EST `/simpleenroll` endpoint
- Perform re-enrollment using existing client certificate for mutual TLS authentication via EST `/simplereenroll` endpoint
- Generate RSA or ECDSA private keys for client certificate enrollment
- Create Certificate Signing Requests (CSRs) with appropriate subject Distinguished Name (DN)
- Install enrolled certificates atomically to shared volume
- Provide structured logging of enrollment and renewal events
- Securely manage bootstrap token (environment variable with restricted permissions)

**Communication Interfaces**:
- **HTTPS Client (EST)**: Synchronous REST API calls to step-ca on port 9000 for EST protocol operations (`/simpleenroll`, `/simplereenroll`)
- **Mutual TLS Client**: Uses existing client certificate for re-enrollment authentication
- **Shared Volume Write**: Writes client certificate and private key files to `client-certs` volume
- **Environment Variables**: Reads configuration (CA URL, bootstrap token, subject DN, renewal threshold, check interval)

### Target Server (NGINX)

**Purpose**: The target server represents a typical edge service requiring automated server certificate management. It demonstrates zero-downtime certificate rotation through graceful configuration reload.

**Technology**: NGINX 1.25+ on Alpine Linux. Configured to serve HTTPS on port 443 using certificates provided by the ACME agent via shared volume.

**Key Responsibilities**:
- Serve HTTPS traffic using TLS certificates from shared volume
- Respond to ACME HTTP-01 challenge requests on port 80 (`.well-known/acme-challenge` path proxied to ACME agent)
- Perform graceful configuration reload when signaled (SIGHUP) to activate new certificates without dropping active connections
- Serve simple HTML demonstration page confirming TLS is operational
- Log HTTPS access and errors

**Communication Interfaces**:
- **HTTPS Server**: Listens on port 443, exposed to host for browser testing
- **HTTP Server**: Listens on port 80 for ACME HTTP-01 challenge validation
- **Shared Volume Read**: Reads server certificate and private key from `server-certs` volume
- **Process Signal**: Receives SIGHUP signal from ACME agent via Docker exec to trigger reload

### Target Client

**Purpose**: The target client represents a device or service requiring automated client certificate management for mutual TLS authentication. It demonstrates client certificate usage for authenticated API access.

**Technology**: Alpine Linux 3.19+ with curl and OpenSSL. Shell script implements demonstration HTTPS requests with client certificate authentication.

**Key Responsibilities**:
- Make periodic HTTPS requests to external APIs using client certificate for mutual TLS authentication
- Read client certificate and private key from shared volume
- Validate server TLS certificates against CA root certificate
- Log successful and failed authentication attempts
- Demonstrate automatic client certificate usage after EST agent renewal

**Communication Interfaces**:
- **HTTPS Client (mTLS)**: Makes outbound HTTPS requests using client certificate for authentication
- **Shared Volume Read**: Reads client certificate and private key from `client-certs` volume

### Web UI (Optional/Stretch Goal)

**Purpose**: The web UI provides a browser-based dashboard for monitoring certificate status, viewing lifecycle events, and visualizing renewal timelines. This component enhances observability but is not required for core PoC functionality.

**Technology**: Node.js 20 LTS with Express web framework, serving static HTML/CSS/JavaScript frontend and WebSocket API for real-time updates.

**Key Responsibilities**:
- Display current certificate status (expiry dates, remaining validity, renewal state)
- Stream real-time logs from agent containers
- Visualize certificate renewal timeline and historical events
- Provide manual renewal trigger buttons for demonstration purposes
- Display system health (container status, network connectivity, CA availability)

**Communication Interfaces**:
- **HTTP/WebSocket Server**: Listens on port 8080 for browser connections
- **Docker API Client**: Queries container status and reads logs via Docker socket
- **Shared Volume Read**: Reads certificate files to display status information

## Communication Patterns

The ECA system employs four distinct communication patterns, each optimized for specific interaction types. Understanding these patterns is essential for comprehending system behavior and troubleshooting operational issues.

### Pattern 1: Polling Loop (Agent Event Detection)

**Where Used**: Both ACME and EST agents use polling loops as their primary execution model.

**How It Works**: Agents run an infinite loop with the following phases:
1. **Check Phase**: Read certificate from shared volume, parse X.509 expiry date, calculate remaining validity
2. **Decision Phase**: Compare remaining validity against configured threshold percentage (e.g., renew when <33% lifetime remains)
3. **Action Phase**: If renewal needed, execute protocol-specific workflow (ACME or EST)
4. **Sleep Phase**: Wait for configured interval (e.g., 6 hours) before next check

**Why This Pattern**: Polling loops are optimal for certificate lifecycle management because:
- **Simplicity**: No external scheduler or event infrastructure required
- **Resilience**: Transient failures (network issues, CA downtime) automatically retry on next loop iteration
- **Resource Efficiency**: Long sleep intervals minimize CPU consumption while still providing timely renewals
- **Deterministic Behavior**: Predictable check intervals simplify troubleshooting and capacity planning

**Trade-offs**: Polling introduces latency between expiry threshold breach and renewal action (maximum latency equals polling interval). For certificate management, this latency is acceptable because renewal thresholds are set days or weeks before actual expiry.

### Pattern 2: Synchronous Request-Response (Protocol Communication)

**Where Used**: All agent-to-PKI communication uses synchronous HTTPS request-response for ACME and EST protocol interactions.

**How It Works**: Agents make blocking HTTP requests using PowerShell's `Invoke-WebRequest` or `Invoke-RestMethod` cmdlets, waiting for step-ca to process the request and return a response before continuing execution.

**Examples**:
- ACME newOrder request: Agent sends order JSON, blocks until CA returns order object with challenge details
- EST simpleenroll request: Agent sends CSR in PKCS#10 format, blocks until CA returns signed certificate
- ACME challenge validation: CA makes synchronous HTTP-01 GET request to agent, agent responds immediately

**Why This Pattern**: Synchronous request-response is appropriate because:
- **Protocol Semantics**: ACME and EST are defined as synchronous HTTP protocols in RFCs 8555 and 7030
- **Simplicity**: No callback infrastructure or async state management required
- **Error Handling**: Immediate HTTP status codes and error responses enable straightforward error handling
- **Latency Requirements**: Certificate operations complete in seconds, making blocking acceptable

**Trade-offs**: Blocking requests tie up agent execution thread during network I/O. For this PoC with single-threaded PowerShell agents, this is acceptable because agents perform one operation at a time.

### Pattern 3: Shared Volume (Certificate Distribution)

**Where Used**: Certificate and private key files are shared between agents and target services via Docker named volumes.

**How It Works**:
1. Agent generates private key and obtains certificate from CA
2. Agent writes key and certificate to temporary files on shared volume with restricted permissions
3. Agent atomically renames temporary files to final names (atomic filesystem operation)
4. Target service reads certificate and key files on startup or reload

**Volume Mappings**:
- `server-certs` volume: Shared between ACME agent (write) and target-server (read)
- `client-certs` volume: Shared between EST agent (write) and target-client (read)

**File Permissions**:
- Private keys: `0600` (owner read/write only) to prevent unauthorized access
- Certificates: `0644` (owner read/write, others read) as certificates are not secret

**Why This Pattern**: File-based communication via shared volumes is optimal because:
- **Decoupling**: Agents and target services don't need network connectivity or API interfaces
- **Simplicity**: No custom protocols or serialization formats—standard PEM encoding
- **Unix Philosophy**: Files as universal interface, readable by all standard TLS libraries
- **Atomicity**: Atomic rename operations prevent target services from reading partial writes
- **Docker Native**: Shared volumes are first-class Docker primitives requiring no additional infrastructure

**Trade-offs**: File-based communication requires both containers to run on the same Docker host. For multi-host deployments, network-based certificate distribution (e.g., Kubernetes secrets) would be required.

### Pattern 4: Process Signaling (Service Reload)

**Where Used**: ACME agent triggers NGINX configuration reload after installing new server certificates.

**How It Works**:
1. ACME agent installs new certificate files to `server-certs` volume
2. Agent executes `docker exec target-server nginx -s reload` command
3. Docker runtime sends SIGHUP signal to NGINX master process inside target-server container
4. NGINX gracefully reloads configuration: loads new certificates, spawns new worker processes, drains old workers without dropping connections
5. Agent validates command exit code to confirm successful reload

**Why This Pattern**: Process signaling enables zero-downtime certificate rotation because:
- **Graceful Reload**: NGINX SIGHUP handler is specifically designed for config reload without service interruption
- **Immediate Activation**: New certificates take effect immediately without waiting for service restart
- **Standard Pattern**: Docker exec is the standard mechanism for process signaling in containerized environments
- **Reliable Feedback**: Exit codes provide immediate confirmation of reload success or failure

**Trade-offs**: This pattern couples the agent to Docker infrastructure (requires Docker socket access for exec command). In Kubernetes, this would be replaced with API-driven pod restarts or init container patterns.

## Data Model

The ECA system uses a **file-based data model** rather than traditional database storage. This architectural decision reflects the ephemeral, operational nature of certificate management where the authoritative data source is the PKI infrastructure itself, not the agent's local storage.

### Why Files Instead of Databases

- **Simplicity**: No database deployment, schema migrations, or ORM complexity
- **Standard Formats**: PEM and DER are universal X.509 certificate encodings supported by all TLS libraries
- **Unix Philosophy**: Files as universal data interface enable interoperability with standard tools (`openssl`, `curl`, etc.)
- **Edge-Appropriate**: Minimal resource footprint (no database process) suitable for resource-constrained edge environments
- **Immutability**: Certificates are write-once, read-many artifacts without complex update patterns requiring transactional storage

### Data Entities

The system manages four primary file-based data entities:

#### 1. Certificate Files (X.509 Certificates)

**Storage Location**:
- Server certificates: `/certs/server/server.crt` (on `server-certs` volume)
- Client certificates: `/certs/client/client.crt` (on `client-certs` volume)

**Format**: PEM-encoded X.509 certificates (Base64-encoded DER with `-----BEGIN CERTIFICATE-----` headers)

**Attributes**:
- **Subject Distinguished Name**: CN=edge-server.eca-poc.local (server) or CN=edge-client (client)
- **Subject Alternative Names** (server only): DNS names the certificate is valid for
- **Issuer DN**: Intermediate CA that signed the certificate
- **Serial Number**: Unique identifier assigned by CA
- **Validity Period**: NotBefore and NotAfter timestamps (UTC) defining certificate lifetime
- **Public Key**: RSA 2048-bit or ECDSA P-256 public key

**Permissions**: `0644` (readable by all users, writable by owner) since certificates are public data

**Lifecycle**: Certificates are replaced (not modified) during renewal. Old certificates are deleted after successful installation of new certificates.

#### 2. Private Key Files (Cryptographic Keys)

**Storage Location**:
- Server keys: `/certs/server/server.key` (on `server-certs` volume)
- Client keys: `/certs/client/client.key` (on `client-certs` volume)

**Format**: PEM-encoded PKCS#8 or PKCS#1 private keys (unencrypted for PoC simplicity)

**Attributes**:
- **Key Algorithm**: RSA or ECDSA
- **Key Size**: RSA 2048-bit or ECDSA P-256
- **Key Material**: Private exponent (RSA) or scalar (ECDSA)

**Permissions**: `0600` (readable/writable by owner only) to prevent unauthorized key access. This is critical for security.

**Lifecycle**: Private keys are generated by agents immediately before creating CSRs. Keys are replaced during renewal (agents generate new key pairs for each renewal, following PKI best practices). Old keys are securely deleted (overwritten and removed).

**Security Considerations**: Keys are stored **unencrypted** in this PoC for simplicity. Production deployments should consider encrypted key storage with hardware security modules (HSMs) or key management services (KMS) for high-security environments.

#### 3. Agent Configuration (YAML/Environment Variables)

**Storage Location**: Environment variables injected via Docker Compose `environment` section

**Format**: Key-value pairs (environment variables) or YAML configuration files

**Attributes** (ACME Agent):
- `CA_URL`: step-ca API endpoint (e.g., `https://pki:9000`)
- `ACME_PROVISIONER`: Provisioner name (e.g., `acme`)
- `DOMAIN_NAME`: Server certificate domain (e.g., `edge-server.eca-poc.local`)
- `CERT_PATH`: Certificate file path (e.g., `/certs/server.crt`)
- `KEY_PATH`: Private key file path (e.g., `/certs/server.key`)
- `RENEWAL_THRESHOLD_PERCENT`: Percentage of lifetime remaining to trigger renewal (e.g., `33`)
- `CHECK_INTERVAL_SECONDS`: Polling loop sleep duration (e.g., `21600` = 6 hours)
- `LOG_LEVEL`: Logging verbosity (DEBUG, INFO, WARN, ERROR)

**Attributes** (EST Agent):
- Similar to ACME agent with protocol-specific additions:
- `BOOTSTRAP_TOKEN`: Pre-shared secret for initial enrollment
- `EST_PROVISIONER`: Provisioner name (e.g., `est`)
- `SUBJECT_DN`: Certificate subject (e.g., `CN=edge-client`)

**Permissions**: Configuration files should be `0600` to protect bootstrap tokens from unauthorized access.

**Lifecycle**: Configuration is read once on agent startup and cached in memory. Configuration changes require agent restart.

#### 4. CA Certificate Database (step-ca Internal State)

**Storage Location**: `/home/step/` directory on `pki-data` volume (internal to step-ca container)

**Format**: SQLite database (default step-ca backend) or other backend configured via step-ca

**Attributes**:
- Issued certificate records (serial number, subject DN, expiry, revocation status)
- ACME account keys and metadata
- EST bootstrap token hashes
- CA configuration and provisioner settings

**Permissions**: Managed by step-ca process, not directly accessed by agents

**Lifecycle**: Maintained by step-ca as authoritative PKI state. Backed up via `pki-data` volume for PoC persistence across container restarts.

### Data Flow Example: Server Certificate Renewal

1. ACME agent reads `/certs/server/server.crt` to check expiry (reads **Certificate File**)
2. Agent determines renewal needed, generates new RSA key pair (creates **Private Key File** in memory)
3. Agent reads `CA_URL` and `DOMAIN_NAME` from environment (reads **Agent Configuration**)
4. Agent creates CSR with new public key, sends ACME order to step-ca
5. step-ca validates domain control, issues certificate, updates internal database (writes **CA Certificate Database**)
6. Agent downloads new certificate, writes temporary files to `/certs/server/server.crt.tmp` and `/certs/server/server.key.tmp`
7. Agent atomically renames files to `/certs/server/server.crt` and `/certs/server/server.key` (updates **Certificate File** and **Private Key File**)
8. NGINX reload reads new certificate and key files from `/certs/server/`

This file-based data flow demonstrates the simplicity and effectiveness of the chosen data model for certificate lifecycle management.

## Security Considerations

Security is paramount in PKI infrastructure. The ECA system implements defense-in-depth with multiple security controls across cryptographic operations, communication channels, secrets management, authentication mechanisms, and container isolation.

### Private Key Management

Private keys are the most sensitive cryptographic assets in the system. Compromise of a private key enables impersonation attacks and breaks the entire PKI trust model.

**Key Generation**:
- Keys generated within agent containers using cryptographically secure random number generators (CSPRNGs)
- PowerShell agents use .NET `System.Security.Cryptography.RSA.Create()` and `System.Security.Cryptography.ECDsa.Create()` which leverage OS-provided entropy sources (`/dev/urandom` on Linux)
- Default key parameters: RSA 2048-bit or ECDSA P-256 curve (NIST-approved strengths)
- Keys generated fresh for each certificate renewal (no key reuse across certificates)

**Key Storage**:
- PEM files on Docker volumes with `0600` permissions (owner read/write only)
- Stored **unencrypted** in this PoC for simplicity (acceptable for demonstration environment)
- Production deployments should encrypt keys at rest using volume encryption (LUKS, dm-crypt) or KMS integration
- Keys never stored in container image layers (only in runtime volumes)

**Key Transmission**:
- Private keys **NEVER transmitted over network** (fundamental PKI principle)
- Only public keys and CSRs (containing public keys) transmitted to CA
- Certificates (containing public keys) transmitted over HTTPS but public keys are not secret

**Key Lifecycle**:
- Old private keys securely deleted after successful certificate renewal
- File overwrite before removal to prevent recovery from unallocated disk space (stretch goal: use `shred` command)

**Key Access Control**:
- Agent containers run as non-root user (UID 1000) with minimal capabilities
- Docker volume permissions restrict key access to agent container user only
- Host filesystem access to volumes should be restricted to root user

### Secure Communication (TLS Everywhere)

All network communication in the ECA system is encrypted using TLS to prevent eavesdropping and tampering.

**Agent-to-PKI Communication**:
- All ACME and EST protocol requests use HTTPS (TLS 1.2 or 1.3)
- step-ca TLS certificate validated against system trust store
- PowerShell `Invoke-WebRequest` performs automatic certificate chain validation
- Prevents man-in-the-middle attacks on certificate issuance

**Browser-to-Server Communication**:
- NGINX serves HTTPS on port 443 using certificates managed by ACME agent
- Demonstrates end-to-end TLS from browser through target service
- Modern cipher suites configured (ECDHE for forward secrecy, AES-GCM for authenticated encryption)

**Client-to-API Communication (Mutual TLS)**:
- Target client demonstrates mutual TLS (mTLS) for client authentication
- Client presents certificate obtained via EST agent to authenticate to remote APIs
- Server validates client certificate against CA trust chain
- Provides cryptographic proof of client identity (stronger than API keys or passwords)

**EST Re-Enrollment (mTLS)**:
- EST protocol requires mTLS for re-enrollment operations
- Agent authenticates to step-ca using existing client certificate
- CA validates certificate not expired and signed by trusted issuer before issuing renewed certificate
- Prevents unauthorized re-enrollment by attackers without valid client certificate

### Secrets Management

The ECA system manages several types of secrets requiring protection from unauthorized access.

**Bootstrap Tokens (EST Initial Enrollment)**:
- Pre-shared secrets used for EST `/simpleenroll` first-time enrollment
- Stored as environment variables in Docker Compose configuration
- **Security Limitations**:
  - Visible in `docker inspect` output and process environment
  - Not encrypted at rest in Docker Compose YAML file
- **PoC Acceptable Risk**: Demo environment with no sensitive data
- **Production Alternatives**: Docker secrets, Kubernetes secrets, HashiCorp Vault integration
- **Best Practice**: Tokens should be single-use and revoked after initial enrollment (step-ca supports this with admin API)

**ACME Account Keys**:
- ACME protocol uses account key pairs for request signing (JWS - JSON Web Signature)
- Account private keys stored in agent container filesystem (not shared volumes)
- Persistent across container restarts via named volumes or recreated on startup
- Less sensitive than certificate private keys (compromise allows unauthorized ACME requests but not service impersonation)

**Configuration Files**:
- Agent configuration may contain CA URLs, provisioner names, domain names
- Not highly sensitive but should be protected from tampering
- File permissions `0600` prevent unauthorized modification
- Integrity validation on startup (check required parameters present and valid format)

**Log Redaction**:
- Structured logging must NEVER log private keys, bootstrap tokens, or other secrets
- Logger implementation includes redaction for sensitive field names (`password`, `token`, `key`)
- Certificate serial numbers and public data safe to log for traceability

### Authentication Mechanisms

The system uses different authentication mechanisms for ACME vs. EST protocols, reflecting their different use cases.

**ACME Protocol Authentication (Server Certificates)**:
- **Account-Based Authentication**: ACME accounts identified by public/private key pairs (JWK - JSON Web Key)
- **Request Signing**: Every ACME request signed with account private key using JWS (RFC 7515)
- **Domain Control Validation**: Proof of domain ownership via HTTP-01 challenge (CA fetches token from `http://domain/.well-known/acme-challenge/{token}`)
- **Why This Works**: Server certificate issuance requires proving control of the domain, not pre-existing trust relationship
- **Threat Model**: Prevents unauthorized certificate issuance for domains attacker doesn't control

**EST Protocol Authentication (Client Certificates)**:
- **Initial Enrollment**: Bootstrap token authentication (pre-shared secret in HTTP Basic Auth header)
  - Token proves device authorized for initial enrollment
  - Requires out-of-band token distribution to devices (QR code, USB, provisioning system)
- **Re-Enrollment**: Certificate-based authentication via mutual TLS
  - Existing valid certificate proves identity for renewal
  - No bootstrap token needed after initial enrollment
- **Why This Works**: Client certificates identify devices/users, requiring proof of authorization rather than domain control
- **Threat Model**: Prevents unauthorized devices from obtaining client certificates; prevents expired certificate renewal by attackers

### Container Security

Containers provide process isolation and resource limits, but require proper configuration to prevent privilege escalation and lateral movement.

**Non-Root Users**:
- All agent containers run as non-root user (UID 1000, GID 1000)
- Prevents privilege escalation attacks if container compromised
- Limits blast radius of vulnerabilities in PowerShell runtime or dependencies

**Minimal Base Images**:
- Alpine Linux base images (~5MB) reduce attack surface compared to full Debian/Ubuntu images
- Fewer installed packages mean fewer potential vulnerabilities
- Security updates easier to apply with smaller image size

**Read-Only Root Filesystems**:
- Container root filesystems should be read-only (Docker `--read-only` flag)
- Writable volumes explicitly mounted for `/certs/` and `/tmp/`
- Prevents malware persistence in container filesystem
- **PoC Status**: Not currently implemented; stretch goal for hardening

**Capability Dropping**:
- Containers drop unnecessary Linux capabilities (CAP_NET_RAW, CAP_SYS_ADMIN, etc.)
- Principle of least privilege: only grant capabilities required for agent operation
- **PoC Status**: Default Docker capability set used; further restriction possible

**Network Segmentation**:
- Docker bridge network (`eca-poc-network`) isolates PoC containers from host network
- Only HTTPS port 443 and Web UI port 8080 exposed to host
- Prevents unauthorized access to internal services (step-ca port 9000 not exposed to host)

**Security Scanning**:
- Container images should be scanned for known vulnerabilities (CVEs) using tools like Trivy or Clair
- Base image updates applied regularly to patch security issues
- **PoC Status**: Manual image updates; automated scanning stretch goal

These layered security controls provide defense-in-depth, ensuring that compromise of any single component does not compromise the entire system.

## Diagram References

The following architectural diagrams provide visual representations of the system structure, deployment topology, and data relationships. Source files are now authored in Mermaid (`.mmd`) so they render natively in GitHub, docs-as-code pipelines, and most Markdown viewers.

### Component Overview Diagram

**File Path**: `docs/diagrams/component_overview.mmd`

**Format**: Mermaid flowchart (C4-inspired container view)

**Description**: This diagram illustrates the complete system architecture showing all six deployable containers (PKI, ECA-ACME Agent, ECA-EST Agent, Target Server, Target Client, Web UI) and their communication relationships. Each container is annotated with its technology stack (PowerShell, NGINX, Node.js, etc.) and communication patterns are shown with directional arrows labeled by protocol (HTTPS/ACME, HTTPS/EST, Docker exec, shared volume).

**Use This Diagram To**: Understand the overall system topology, identify communication paths between services, and see how the sidecar pattern is applied to target services. This is the primary reference for understanding the microservices architecture.

### Deployment Architecture Diagram

**File Path**: `docs/diagrams/deployment_architecture.mmd`

**Format**: Mermaid flowchart (deployment topology)

**Description**: This diagram shows the physical deployment topology of the Docker Compose environment on a single host machine. It visualizes Docker containers as deployment nodes, Docker named volumes (`server-certs`, `client-certs`, `pki-data`) as persistent storage, the Docker bridge network (`eca-poc-network`) connecting containers, and port mappings exposing services to the host (443 for NGINX HTTPS, 8080 for Web UI, 9000 for step-ca kept internal).

**Use This Diagram To**: Understand the Docker infrastructure architecture, volume mounting patterns, network topology, and port exposure model. This diagram is essential for troubleshooting connectivity issues and understanding the single-host deployment constraints.

### Data Model Diagram

**File Path**: `docs/diagrams/data_model.mmd`

**Format**: Mermaid Entity Relationship Diagram (ERD)

**Description**: This diagram represents the conceptual file-based data model showing four entities (CertificateFile, PrivateKeyFile, AgentConfiguration, CACertificateRecord) and their relationships. Relationships include "CertificateFile paired_with PrivateKeyFile" (1:1), "AgentConfiguration manages_lifecycle CertificateFile" (1:N), and "CACertificateRecord issued_by CA" (N:1). Entity attributes are listed including file paths, permissions, and key fields.

**Use This Diagram To**: Understand the data entities managed by the system, their relationships, and storage locations. This diagram clarifies the file-based data model and is useful for understanding certificate lifecycle data flow and storage requirements.

---

## Conclusion

The ECA PoC architecture demonstrates that zero-touch certificate lifecycle management is achievable in containerized edge environments using industry-standard protocols (ACME, EST), proven technologies (PowerShell, Docker, step-ca), and well-established architectural patterns (event-driven, microservices, sidecar).

The hybrid architectural style balances simplicity (polling loops, file-based communication) with production readiness (standard protocols, comprehensive security controls), making this PoC both a functional demonstration and a blueprint for real-world edge PKI deployments.

Key architectural strengths:
- **Autonomy**: Agents operate independently without central orchestration
- **Resilience**: Polling-based event detection provides automatic retry on transient failures
- **Observability**: Structured logging and optional Web UI provide comprehensive visibility
- **Extensibility**: Modular design enables new agent types (SCEP, CMP, other protocols) without architectural changes
- **Security**: Defense-in-depth with TLS everywhere, minimal privileges, and secrets management

This architecture provides a solid foundation for the implementation tasks that follow, with clear component boundaries, well-defined interfaces, and comprehensive security considerations.
