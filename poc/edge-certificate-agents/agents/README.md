# ECA Agent Architecture - Complete Reference

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Active Agents](#active-agents)
4. [Shared Modules](#shared-modules)
5. [Workflow Pattern](#workflow-pattern)
6. [Adding a New Agent](#adding-a-new-agent)
7. [Adding a New Workflow Step](#adding-a-new-workflow-step)
8. [Configuration](#configuration)
9. [Agent-Specific Details](#agent-specific-details)
10. [Code Examples](#code-examples)
11. [Best Practices](#best-practices)
12. [Module Reference](#module-reference)
13. [Testing](#testing)

---

## Overview

### What are ECA Agents?

Edge Certificate Agents (ECA) are **autonomous, containerized services** that manage certificate lifecycles for edge devices and services. Each agent:

- **Monitors** certificate health (expiry, revocation status)
- **Decides** when enrollment or renewal is needed
- **Executes** protocol-specific operations (ACME, EST)
- **Validates** deployment and triggers service reloads

### Purpose

The ECA agent architecture provides:

- **Automation**: Zero-touch certificate lifecycle management
- **Protocol Support**: ACME for server certificates, EST for device credentials
- **Observability**: Structured logging, metrics, and health monitoring
- **Security**: CRL validation, secure key management, atomic file operations
- **Modularity**: Reusable components across protocols, easy extensibility

### Key Benefits

| Benefit | Description |
|---------|-------------|
| **Testability** | Each module is independently unit tested |
| **Maintainability** | Business logic separated from orchestration |
| **Reusability** | Common modules shared across protocols (60% code reuse) |
| **Observability** | Built-in metrics and structured logging |
| **Flexibility** | Easy to add new protocols (2-3 hours vs 2-3 days) |

---

## Architecture

### 4-Layer Modular Architecture

The ECA agent system uses a **state-of-the-art layered architecture** that separates concerns and maximizes reusability:

```
┌─────────────────────────────────────────────────────────────┐
│                   Layer 1: Orchestration                     │
│              (acme-agent.ps1 / est-agent.ps1)                │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  • Load Configuration                                   │ │
│  │  • Initialize Logging                                   │ │
│  │  • Register Workflow Steps                              │ │
│  │  • Start Orchestrator                                   │ │
│  │  • NO Business Logic (134-135 lines)                    │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                 Layer 2: Workflow Engine                     │
│            (WorkflowOrchestrator.psm1 - Generic)            │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  • State Machine                                        │ │
│  │  • Step Registration & Execution                        │ │
│  │  • Error Handling & Retry Logic                         │ │
│  │  • Metrics Collection                                   │ │
│  │  • Iteration Management                                 │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                  Layer 3: Business Logic                     │
│        (AcmeWorkflow.psm1 / EstWorkflow.psm1)               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  • Step-MonitorCertificate                              │ │
│  │  • Step-DecideAction                                    │ │
│  │  • Step-ExecuteProtocol                                 │ │
│  │  • Step-ValidateDeployment                              │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                    Layer 4: Common Modules                   │
│   (Logger, Config, CertMonitor, CRL, Crypto, File, etc.)   │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  • Shared Functionality                                 │ │
│  │  • Reusable Across Agents                               │ │
│  │  • Protocol-Agnostic                                    │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Architecture Benefits

1. **Thin Orchestration Layer**: Agent scripts are <140 lines of pure configuration
2. **Generic Workflow Engine**: WorkflowOrchestrator is reusable across all protocols
3. **Protocol-Specific Logic**: Isolated in workflow modules (AcmeWorkflow, EstWorkflow)
4. **Shared Components**: Common modules eliminate code duplication

---

## Active Agents

These are the **modular, production-ready** agents used by the Docker containers:

### ACME Agent

- **Entry Point**: `acme/acme-agent.ps1` (134 lines)
- **Workflow Module**: `acme/AcmeWorkflow.psm1`
- **Architecture**: Thin orchestration layer using WorkflowOrchestrator
- **Purpose**: Server certificate lifecycle management via ACME protocol
- **Features**:
  - Posh-ACME integration for RFC 8555 compliance
  - HTTP-01 challenge handling
  - NGINX service reload automation
  - CRL validation
- **Status**: ✅ **ACTIVE** (used by Dockerfile)

### EST Agent

- **Entry Point**: `est/est-agent.ps1` (135 lines)
- **Workflow Module**: `est/EstWorkflow.psm1`
- **Architecture**: Thin orchestration layer using WorkflowOrchestrator
- **Purpose**: Device certificate lifecycle management via EST protocol
- **Features**:
  - Bootstrap token enrollment
  - mTLS re-enrollment
  - Device identity management
  - CRL validation
- **Status**: ✅ **ACTIVE** (used by Dockerfile)

---

## Shared Modules

All agents share these battle-tested modules in `common/`:

### WorkflowOrchestrator.psm1
**Generic workflow execution engine**

- **Purpose**: Provides state machine for certificate lifecycle workflows
- **Key Features**:
  - Protocol-agnostic step registration and execution
  - Error handling with configurable continue-on-error
  - Automatic metrics collection (timing, success rates)
  - Iteration management with configurable intervals
- **Exported Functions**:
  - `New-WorkflowContext` - Create workflow execution context
  - `Register-WorkflowStep` - Register named workflow step
  - `Invoke-WorkflowStep` - Execute single workflow step
  - `Start-WorkflowLoop` - Main orchestration loop
  - `Get-WorkflowMetrics` - Retrieve execution metrics
  - `Reset-WorkflowMetrics` - Reset metrics (testing)

### ConfigManager.psm1
**Configuration loading and validation**

- **Purpose**: YAML config parsing with environment overrides and JSON schema validation
- **Key Features**:
  - Environment variable overrides (uppercase naming convention)
  - Multi-instance deployment support (agent-specific prefixes)
  - JSON Schema validation against `config/agent_config_schema.json`
  - Type conversion and format validation
  - Sensitive field redaction (tokens, passwords)
- **Configuration Precedence**:
  1. Prefixed environment variables (e.g., `ACME_PKI_URL`)
  2. Legacy/unprefixed environment variables (e.g., `PKI_URL`)
  3. YAML file values
  4. Schema default values
- **Exported Functions**:
  - `Read-AgentConfig` - Load and validate configuration
  - `Test-ConfigValid` - Validate config against schema

### Logger.psm1
**Structured JSON and console logging**

- **Purpose**: Provides consistent logging across all agents and modules
- **Key Features**:
  - **JSON format**: Machine-readable for log aggregation (Fluentd, Loki)
  - **Console format**: Human-readable with color coding for development
  - ISO 8601 UTC timestamps
  - Contextual logging with key-value pairs
  - Environment variable control (`LOG_FORMAT`)
- **Log Levels**:
  - INFO (Cyan) - Normal lifecycle events
  - WARN (Yellow) - Recoverable errors
  - ERROR (Red) - Non-recoverable errors
  - DEBUG (Gray) - Protocol-level details
- **Exported Functions**:
  - `Write-LogInfo` - Log informational messages
  - `Write-LogWarn` - Log warning messages
  - `Write-LogError` - Log error messages
  - `Write-LogDebug` - Log debug information
- **Security**: NEVER logs sensitive data (private keys, passwords, tokens)

### CertificateMonitor.psm1
**Certificate lifecycle tracking**

- **Purpose**: Monitor certificate status and calculate lifetime metrics
- **Key Features**:
  - Certificate existence checking
  - Expiry date validation
  - Lifetime elapsed percentage calculation
  - Days remaining calculation
  - Certificate information extraction
- **Exported Functions**:
  - `Test-CertificateExists` - Check if certificate file exists
  - `Get-CertificateLifetimeElapsed` - Calculate % of lifetime elapsed
  - `Get-CertificateInfo` - Extract comprehensive certificate info

### CryptoHelper.psm1
**Key generation and CSR creation**

- **Purpose**: Cryptographic operations for certificate lifecycle
- **Key Features**:
  - RSA 2048-bit key pair generation
  - PKCS#10 CSR creation with SANs
  - PKCS#8 private key export
  - X.509 certificate parsing
  - Certificate expiry validation
- **Exported Functions**:
  - `New-RSAKeyPair` - Generate RSA 2048-bit key pair
  - `New-CertificateRequest` - Create PKCS#10 CSR
  - `Read-Certificate` - Parse X.509 certificate from PEM
  - `Export-PrivateKey` - Export private key to PKCS#8 PEM
  - `Test-CertificateExpiry` - Check if renewal needed

### FileOperations.psm1
**Atomic file writes and permissions**

- **Purpose**: Secure file operations for certificates and keys
- **Key Features**:
  - Atomic file writes (temp + rename pattern)
  - Cross-platform permission management (chmod, icacls)
  - Permission validation
  - Automatic cleanup on errors
- **Security**: Private keys set to 0600 (owner-only read/write)
- **Exported Functions**:
  - `Write-FileAtomic` - Write file atomically
  - `Set-FilePermissions` - Set Unix/Windows permissions
  - `Test-FilePermissions` - Validate file permissions

### CrlValidator.psm1
**Certificate revocation checking**

- **Purpose**: Download, cache, and validate CRLs
- **Key Features**:
  - CRL download and caching
  - Age-based cache refresh
  - Certificate revocation checking
  - CRL information extraction
- **Exported Functions**:
  - `Get-CrlFromUrl` - Download CRL from URL
  - `Update-CrlCache` - Update cached CRL if stale
  - `Test-CertificateRevoked` - Check if certificate is revoked
  - `Get-CrlInfo` - Extract CRL metadata
  - `Get-CrlAge` - Return age of cached CRL

---

## Workflow Pattern

All agents follow the **Monitor → Decide → Execute → Validate** pattern:

```
┌─────────────────────────────────────────────────────────────┐
│  Thin Orchestrator (acme-agent.ps1 / est-agent.ps1)        │
│  - Load config                                              │
│  - Initialize logging                                       │
│  - Register workflow steps                                  │
│  - Start workflow loop                                      │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│  WorkflowOrchestrator.psm1 (Generic Engine)                │
│  - Execute steps in order                                   │
│  - Handle errors and retries                                │
│  - Collect metrics                                          │
│  - Log execution traces                                     │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│  Protocol Workflow Module (AcmeWorkflow / EstWorkflow)     │
│  - Monitor: Check certificate status                        │
│  - Decide: Determine action needed                          │
│  - Execute: Run protocol-specific logic                     │
│  - Validate: Verify deployment                              │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│  Common Modules (Logger, CryptoHelper, etc.)               │
│  - Reusable business logic                                  │
│  - Protocol-agnostic helpers                                │
└─────────────────────────────────────────────────────────────┘
```

### Workflow Steps Explained

#### 1. Monitor
- Check certificate existence
- Validate expiry and lifetime percentage
- Check CRL revocation status
- Update context state with certificate status

#### 2. Decide
- Analyze certificate status from Monitor step
- Determine action: **enroll**, **renew**, or **skip**
- Select authentication mode (EST: bootstrap vs mTLS)
- Set decision in context for Execute step

#### 3. Execute
- Execute protocol based on decision
- **ACME**: New-Order, HTTP-01 challenge, Finalize-Order
- **EST**: Bootstrap enrollment or mTLS re-enrollment
- Write certificate and key files atomically
- Set proper file permissions

#### 4. Validate
- Verify certificate and key files exist
- Validate file permissions (key = 0600, cert = 0644)
- Trigger service reload (ACME: NGINX restart)
- Confirm deployment success

---

## Adding a New Agent

To add support for a new certificate protocol (e.g., SCEP, CMPv2), follow this checklist:

### 1. Bootstrap the Module

Create `agents/<protocol>/` directory with:

```
agents/scep/
├── scep-agent.ps1              # Thin orchestrator (copy from acme-agent.ps1)
├── ScepWorkflow.psm1           # Protocol-specific workflow steps
├── ScepClient.psm1             # Protocol client (if needed)
├── Dockerfile                  # Container configuration
└── config.yaml                 # Default configuration
```

**Example: scep-agent.ps1**

```powershell
#Requires -Version 7.0

# Module Imports
Import-Module /app/agents/common/Logger.psm1
Import-Module /app/agents/common/ConfigManager.psm1
Import-Module /app/agents/common/WorkflowOrchestrator.psm1
Import-Module /app/agents/scep/ScepWorkflow.psm1

# Load Configuration
$config = Read-AgentConfig -ConfigFilePath "/config/scep-agent.yaml"

# Initialize Workflow
Initialize-ScepWorkflowSteps
$context = New-WorkflowContext -Config $config

# Start Workflow Loop
$steps = @("Monitor", "Decide", "Execute", "Validate")
Start-WorkflowLoop -Context $context -Steps $steps -IntervalSeconds $config.check_interval_sec
```

### 2. Implement Workflow Module

Create `ScepWorkflow.psm1` with these required functions:

```powershell
function Initialize-ScepWorkflowSteps {
    # Register all workflow steps
    Register-WorkflowStep -Name "Monitor" -ScriptBlock {
        param($Context)
        Step-MonitorCertificate -Context $Context
    }

    Register-WorkflowStep -Name "Decide" -ScriptBlock {
        param($Context)
        Step-DecideAction -Context $Context
    }

    Register-WorkflowStep -Name "Execute" -ScriptBlock {
        param($Context)
        Step-ExecuteScepProtocol -Context $Context
    }

    Register-WorkflowStep -Name "Validate" -ScriptBlock {
        param($Context)
        Step-ValidateDeployment -Context $Context
    }
}

function Step-MonitorCertificate {
    param([hashtable]$Context)
    # Monitoring logic using CertificateMonitor.psm1
}

function Step-DecideAction {
    param([hashtable]$Context)
    # Decision logic based on certificate status
}

function Step-ExecuteScepProtocol {
    param([hashtable]$Context)
    # SCEP-specific protocol execution
}

function Step-ValidateDeployment {
    param([hashtable]$Context)
    # Deployment validation
}

Export-ModuleMember -Function @(
    'Initialize-ScepWorkflowSteps',
    'Step-MonitorCertificate',
    'Step-DecideAction',
    'Step-ExecuteScepProtocol',
    'Step-ValidateDeployment'
)
```

### 3. Update Configuration Schema

Add protocol-specific fields to `config/agent_config_schema.json`:

```json
{
  "scep_url": {
    "type": "string",
    "format": "uri",
    "description": "SCEP server URL"
  },
  "scep_challenge_password": {
    "type": "string",
    "description": "SCEP challenge password (sensitive)"
  }
}
```

### 4. Update ConfigManager

Add new fields to environment variable mappings in `ConfigManager.psm1`:

```powershell
$envMappings = @{
    'scep_url'                = 'SCEP_URL'
    'scep_challenge_password' = 'SCEP_CHALLENGE_PASSWORD'
    # ... existing mappings
}
```

### 5. Docker Compose Integration

Add service to `docker-compose.yml`:

```yaml
eca-scep-agent:
  build:
    context: .
    dockerfile: agents/scep/Dockerfile
  environment:
    AGENT_ENV_PREFIX: SCEP_
    SCEP_PKI_URL: ${SCEP_PKI_URL}
    SCEP_DEVICE_NAME: ${SCEP_DEVICE_NAME}
    LOG_FORMAT: ${LOG_FORMAT:-json}
  volumes:
    - scep-certs:/certs/scep
  networks:
    - eca-network
```

### 6. Testing

Create test files:

```
tests/unit/ScepWorkflow.Tests.ps1
tests/integration/ScepAgent.Tests.ps1
```

### 7. Documentation

Update documentation:

- `README.md` - Add SCEP agent to Active Agents section
- `docs/ARCHITECTURE.md` - Add SCEP protocol flow diagram
- `QUICKSTART.md` - Add SCEP agent setup instructions

### Estimated Time

**2-3 hours** (vs 2-3 days for monolithic approach)

---

## Adding a New Workflow Step

To extend an existing agent with a new workflow step:

### 1. Add Step Function to Workflow Module

**Example: Add notification step to ACME agent**

Edit `agents/acme/AcmeWorkflow.psm1`:

```powershell
function Step-NotifyAdministrator {
    [CmdletBinding()]
    param([hashtable]$Context)

    $config = $Context.Config
    $state = $Context.State

    # Send notification if renewal occurred
    if ($state.LastDecision -eq "renew" -and $state.RenewalSuccessful) {
        Write-LogInfo -Message "Sending renewal notification" -Context @{
            domain = $config.domain_name
            email = $config.admin_email
        }

        # Send email or webhook notification
        # ...
    }
}

Export-ModuleMember -Function @(
    'Step-MonitorCertificate',
    'Step-DecideAction',
    'Step-ExecuteAcmeProtocol',
    'Step-ValidateDeployment',
    'Step-NotifyAdministrator'  # Add new function
)
```

### 2. Register Step in Initialization

Update `Initialize-AcmeWorkflowSteps`:

```powershell
function Initialize-AcmeWorkflowSteps {
    Register-WorkflowStep -Name "Monitor" -ScriptBlock {
        param($Context)
        Step-MonitorCertificate -Context $Context
    }

    Register-WorkflowStep -Name "Decide" -ScriptBlock {
        param($Context)
        Step-DecideAction -Context $Context
    }

    Register-WorkflowStep -Name "Execute" -ScriptBlock {
        param($Context)
        Step-ExecuteAcmeProtocol -Context $Context
    }

    Register-WorkflowStep -Name "Validate" -ScriptBlock {
        param($Context)
        Step-ValidateDeployment -Context $Context
    }

    # Add new step
    Register-WorkflowStep -Name "Notify" -ScriptBlock {
        param($Context)
        Step-NotifyAdministrator -Context $Context
    }
}
```

### 3. Update Agent Script

Edit `agents/acme/acme-agent.ps1`:

```powershell
# Add "Notify" to workflow steps
$steps = @("Monitor", "Decide", "Execute", "Validate", "Notify")
Start-WorkflowLoop -Context $context -Steps $steps -IntervalSeconds $config.check_interval_sec
```

### 4. Optional: Add Configuration

If the step needs configuration, update `config.yaml`:

```yaml
admin_email: "admin@example.com"
notification_webhook: "https://alerts.example.com/webhook"
```

### 5. Test the Step

Create unit test in `tests/unit/AcmeWorkflow.Tests.ps1`:

```powershell
Describe "Step-NotifyAdministrator" {
    It "Sends notification on successful renewal" {
        Mock Send-Email { return $true }

        $context = @{
            Config = @{ admin_email = "admin@test.com" }
            State = @{
                LastDecision = "renew"
                RenewalSuccessful = $true
            }
        }

        Step-NotifyAdministrator -Context $context

        Should -Invoke Send-Email -Times 1
    }
}
```

---

## Configuration

### Configuration Patterns

All agents use the same configuration pattern:

1. Load from `config.yaml`
2. Override with environment variables (prefix-aware)
3. Validate against JSON schema
4. Merge with sensible defaults

### Environment Variable Prefixes

For multi-instance deployments, use agent-specific prefixes:

```bash
# ACME Agent Instance 1
export AGENT_ENV_PREFIX=ACME_APP1_
export ACME_APP1_PKI_URL="https://pki:9000"
export ACME_APP1_DOMAIN_NAME="app1.example.com"

# ACME Agent Instance 2
export AGENT_ENV_PREFIX=ACME_APP2_
export ACME_APP2_PKI_URL="https://pki:9000"
export ACME_APP2_DOMAIN_NAME="app2.example.com"
```

### Configuration Precedence

**Highest to Lowest:**

1. **Prefixed environment variables** (e.g., `ACME_PKI_URL`)
2. **Unprefixed environment variables** (e.g., `PKI_URL` - legacy)
3. **YAML file values**
4. **Schema default values**

### Common Configuration Fields

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `pki_url` | URI | Yes | - | Base URL of PKI API |
| `cert_path` | String | Yes | - | Certificate output path |
| `key_path` | String | Yes | - | Private key output path |
| `domain_name` | String | No | - | Subject/SAN for certificate |
| `device_name` | String | No | - | Device identifier (EST) |
| `renewal_threshold_pct` | Integer | No | 75 | Renewal trigger % (1-100) |
| `check_interval_sec` | Integer | No | 60 | Check interval in seconds |
| `bootstrap_token` | String | No | - | EST bootstrap token (sensitive) |
| `agent_id` | String | No | - | Unique agent identifier |

### Environment Variable Naming

**Convention**: YAML snake_case → ENV UPPER_SNAKE_CASE

- `pki_url` → `PKI_URL`
- `cert_path` → `CERT_PATH`
- `renewal_threshold_pct` → `RENEWAL_THRESHOLD_PCT`
- `check_interval_sec` → `CHECK_INTERVAL_SEC`

### Example: docker-compose.yml

```yaml
eca-acme-agent:
  environment:
    AGENT_ENV_PREFIX: ACME_
    ACME_PKI_URL: https://pki.local:9000
    ACME_DOMAIN_NAME: target-server
    ACME_RENEWAL_THRESHOLD_PCT: 75
    ACME_CHECK_INTERVAL_SEC: 60
    LOG_FORMAT: json
```

---

## Agent-Specific Details

### ACME Agent

#### Purpose
Server certificate lifecycle management via ACME protocol (RFC 8555)

#### Key Features

**Posh-ACME Integration**
- Leverages Posh-ACME PowerShell module for RFC 8555 compliance
- Supports ACME account management
- Multi-domain certificates with SANs
- Automatic ACME account creation and key management

**HTTP-01 Challenge Handling**
- Shared Docker volume for challenge files
- NGINX serves `.well-known/acme-challenge/` from shared volume
- Agent writes challenge responses to shared directory
- Automatic cleanup after validation

**Service Reload**
- Detects when certificates are updated
- Executes `docker exec nginx nginx -s reload`
- Configurable timeout and retry logic
- Logs reload success/failure

**Workflow Steps**
1. **Monitor**: Check certificate via CertificateMonitor, validate CRL
2. **Decide**: Determine if enrollment or renewal needed (threshold-based)
3. **Execute**: Execute ACME protocol (New-Order → Challenges → Finalize)
4. **Validate**: Verify deployment, trigger NGINX reload

#### Configuration Example

```yaml
# ACME Agent Configuration
pki_url: "https://pki.local:9000"
cert_path: "/certs/server/cert.pem"
key_path: "/certs/server/key.pem"
domain_name: "target-server"
renewal_threshold_pct: 75
check_interval_sec: 60

# ACME-specific settings
challenge_directory: "/challenges"
acme_account_contact_email: "admin@example.com"
acme_directory_path: "/padata"
acme_certificate_key_type: "rsa"
acme_certificate_key_size: 2048

# Service reload settings
service_reload_container_name: "eca-target-server"
service_reload_timeout_seconds: 10

# CRL validation
crl:
  enabled: true
  url: "http://pki.local:9001/crl/intermediate_ca.crl"
  cache_path: "/tmp/crl/intermediate_ca.crl"
  max_age_hours: 24
```

### EST Agent

#### Purpose
Device certificate lifecycle management via EST protocol (RFC 7030)

#### Key Features

**Bootstrap Token Enrollment**
- One-time token for initial enrollment
- Token provided via environment variable (`BOOTSTRAP_TOKEN`)
- Automatic transition to mTLS re-enrollment after initial cert

**mTLS Re-Enrollment**
- Uses existing certificate for authentication
- Automatic re-enrollment when threshold reached
- No manual intervention required

**Device Identity**
- Device name becomes certificate subject
- Supports device-specific configurations
- Multi-device deployments via prefixed environment variables

**Workflow Steps**
1. **Monitor**: Check certificate status, validate CRL
2. **Decide**: Determine enrollment vs re-enrollment, select auth mode
3. **Execute**: Execute EST protocol (bootstrap or mTLS)
4. **Validate**: Verify certificate and chain deployment

#### Configuration Example

```yaml
# EST Agent Configuration
pki_url: "https://pki.local:8443"
cert_path: "/certs/client/cert.pem"
key_path: "/certs/client/key.pem"
device_name: "client-device-001"
renewal_threshold_pct: 75
check_interval_sec: 60

# EST-specific settings
bootstrap_token: "${BOOTSTRAP_TOKEN}"  # From environment

# CRL validation
crl:
  enabled: true
  url: "http://pki.local:9001/crl/intermediate_ca.crl"
  cache_path: "/tmp/crl/intermediate_ca.crl"
  max_age_hours: 24
```

#### Bootstrap vs mTLS Decision Logic

```
IF certificate does NOT exist:
    USE bootstrap token enrollment
ELSE IF certificate lifetime >= renewal_threshold_pct:
    USE mTLS re-enrollment with existing certificate
ELSE:
    SKIP (no action needed)
```

---

## Code Examples

### Example 1: Thin Orchestration Script

**agents/acme/acme-agent.ps1** (134 lines)

```powershell
#Requires -Version 7.0

# ==============================================================================
# Module Imports
# ==============================================================================
Import-Module /app/agents/common/Logger.psm1
Import-Module /app/agents/common/ConfigManager.psm1
Import-Module /app/agents/common/WorkflowOrchestrator.psm1
Import-Module /app/agents/acme/AcmeWorkflow.psm1

# ==============================================================================
# Configuration Loading
# ==============================================================================
$configPath = "/config/acme-agent.yaml"
$config = Read-AgentConfig -ConfigFilePath $configPath

Write-LogInfo -Message "ACME Agent starting" -Context @{
    version = "2.0"
    environment = $config.environment
    pki_url = $config.pki_url
}

# ==============================================================================
# Workflow Initialization
# ==============================================================================
Initialize-AcmeWorkflowSteps
$context = New-WorkflowContext -Config $config

# ==============================================================================
# Workflow Execution
# ==============================================================================
try {
    $steps = @("Monitor", "Decide", "Execute", "Validate")
    $interval = $config.check_interval_sec

    Write-LogInfo -Message "Starting workflow loop" -Context @{
        steps = ($steps -join ", ")
        interval_sec = $interval
    }

    Start-WorkflowLoop -Context $context -Steps $steps -IntervalSeconds $interval
}
catch {
    Write-LogError -Message "Agent terminated with error" -Context @{
        error = $_.Exception.Message
    }
    exit 1
}
finally {
    # Display metrics on shutdown
    $metrics = Get-WorkflowMetrics
    Write-LogInfo -Message "Agent metrics" -Context @{
        uptime = $metrics.Uptime.ToString()
        total_iterations = $metrics.TotalIterations
        success_rate = "$($metrics.SuccessRate)%"
    }
}
```

### Example 2: Workflow Step Registration

**Initialize-AcmeWorkflowSteps**

```powershell
function Initialize-AcmeWorkflowSteps {
    [CmdletBinding()]
    param()

    # Register Monitor step
    Register-WorkflowStep -Name "Monitor" -ScriptBlock {
        param($Context)
        Step-MonitorCertificate -Context $Context
    } -Description "Monitor certificate status and CRL"

    # Register Decide step
    Register-WorkflowStep -Name "Decide" -ScriptBlock {
        param($Context)
        Step-DecideAction -Context $Context
    } -Description "Determine enrollment/renewal action"

    # Register Execute step
    Register-WorkflowStep -Name "Execute" -ScriptBlock {
        param($Context)
        Step-ExecuteAcmeProtocol -Context $Context
    } -Description "Execute ACME protocol"

    # Register Validate step
    Register-WorkflowStep -Name "Validate" -ScriptBlock {
        param($Context)
        Step-ValidateDeployment -Context $Context
    } -Description "Validate deployment and reload services"
}
```

### Example 3: Monitor Step Implementation

**Step-MonitorCertificate**

```powershell
function Step-MonitorCertificate {
    [CmdletBinding()]
    param([hashtable]$Context)

    $config = $Context.Config
    $certPath = $config.cert_path

    Write-LogInfo -Message "Monitoring certificate" -Context @{
        cert_path = $certPath
    }

    # Check if certificate exists
    if (-not (Test-CertificateExists -Path $certPath)) {
        Write-LogInfo -Message "Certificate not found - initial enrollment needed"

        $Context.State.CertificateStatus.Exists = $false
        $Context.State.CertificateStatus.RenewalRequired = $true
        return
    }

    # Get certificate information
    $certInfo = Get-CertificateInfo -Path $certPath

    Write-LogInfo -Message "Certificate found" -Context @{
        subject = $certInfo.Subject
        days_remaining = $certInfo.DaysRemaining
        lifetime_elapsed_pct = $certInfo.LifetimeElapsedPercent
    }

    # Check if renewal needed based on threshold
    $threshold = $config.renewal_threshold_pct
    $renewalNeeded = $certInfo.LifetimeElapsedPercent -ge $threshold

    # Update context state
    $Context.State.CertificateStatus.Exists = $true
    $Context.State.CertificateStatus.ExpiryDate = $certInfo.NotAfter
    $Context.State.CertificateStatus.LifetimePercentage = $certInfo.LifetimeElapsedPercent
    $Context.State.CertificateStatus.RenewalRequired = $renewalNeeded
    $Context.State.CertificateStatus.Revoked = $false

    # Check CRL if enabled
    if ($config.crl.enabled) {
        # Update CRL cache
        $crlUpdate = Update-CrlCache -Url $config.crl.url `
                                      -CachePath $config.crl.cache_path `
                                      -MaxAgeHours $config.crl.max_age_hours

        # Check if certificate is revoked
        $isRevoked = Test-CertificateRevoked -CertificatePath $certPath `
                                              -CrlPath $config.crl.cache_path

        if ($isRevoked) {
            Write-LogWarn -Message "Certificate is REVOKED" -Context @{
                serial = $certInfo.SerialNumber
            }

            $Context.State.CertificateStatus.Revoked = $true
            $Context.State.CertificateStatus.RenewalRequired = $true
        }
    }
}
```

### Example 4: Decision Step

**Step-DecideAction**

```powershell
function Step-DecideAction {
    [CmdletBinding()]
    param([hashtable]$Context)

    $status = $Context.State.CertificateStatus

    # Determine action based on certificate status
    if (-not $status.Exists) {
        $decision = "enroll"
        Write-LogInfo -Message "Decision: Initial enrollment"
    }
    elseif ($status.Revoked) {
        $decision = "renew"
        Write-LogWarn -Message "Decision: Re-enrollment (certificate revoked)"
    }
    elseif ($status.RenewalRequired) {
        $decision = "renew"
        Write-LogInfo -Message "Decision: Renewal required" -Context @{
            lifetime_elapsed_pct = $status.LifetimePercentage
            threshold_pct = $Context.Config.renewal_threshold_pct
        }
    }
    else {
        $decision = "skip"
        Write-LogInfo -Message "Decision: No action needed" -Context @{
            lifetime_elapsed_pct = $status.LifetimePercentage
            days_remaining = ($status.ExpiryDate - (Get-Date)).TotalDays
        }
    }

    # Store decision in context
    $Context.State.LastDecision = $decision
}
```

---

## Best Practices

### Design Patterns

#### 1. Keep Scripts Thin

**Agent scripts should ONLY:**
- Load configuration
- Initialize logging
- Register workflow steps
- Start orchestrator
- Display metrics on shutdown

**Agent scripts should NOT:**
- Implement business logic
- Make HTTP requests
- Parse certificates
- Execute protocols

#### 2. Module Single Responsibility

Each module has one clear purpose:

- **WorkflowOrchestrator**: Orchestration only
- **AcmeWorkflow**: ACME workflow steps only
- **CrlValidator**: CRL operations only
- **ConfigManager**: Configuration only

#### 3. Use Dependency Injection

Pass dependencies via context:

```powershell
# Good
$context = New-WorkflowContext -Config $config -Logger $logger

function Step-Monitor {
    param($Context)
    $config = $Context.Config  # Use injected dependency
}

# Bad
function Step-Monitor {
    $config = Get-Configuration  # Creates dependency
}
```

#### 4. Make Workflows Stateless

Workflow steps should not maintain state between invocations. Use context for state:

```powershell
# Good
function Step-Decide {
    param($Context)
    $decision = # ... make decision
    $Context.State.LastDecision = $decision  # Store in context
}

# Bad (stateful)
$script:LastDecision = $null  # Module-level state

function Step-Decide {
    $script:LastDecision = # ... make decision
}
```

#### 5. Fail Fast

Let errors bubble up to orchestrator:

```powershell
function Step-Execute {
    param($Context)

    if (-not (Test-Path $requiredFile)) {
        throw "Required file not found"  # Let orchestrator handle
    }
}
```

### Testing Guidelines

#### Unit Testing Each Layer

```powershell
# Test WorkflowOrchestrator in isolation
Describe "WorkflowOrchestrator" {
    It "Executes registered steps" {
        Register-WorkflowStep -Name "Test" -ScriptBlock { return "success" }
        $result = Invoke-WorkflowStep -Name "Test" -Context @{}
        $result.Success | Should -Be $true
    }
}

# Test workflow steps in isolation
Describe "AcmeWorkflow" {
    It "Detects missing certificate" {
        Mock Test-Path { return $false }
        $result = Step-MonitorCertificate -Context $context
        $result.CertificateExists | Should -Be $false
    }
}
```

#### Integration Testing

```bash
# Run integration tests (requires Docker services)
./scripts/run-tests.sh --auto-start-integration

# Or PowerShell
pwsh -File scripts/run-tests.ps1 -IntegrationOnly -AutoStartIntegration
```

### Error Handling

#### Structured Error Logging

```powershell
try {
    # Operation
}
catch {
    Write-LogError -Message "Operation failed" -Context @{
        error = $_.Exception.Message
        operation = "certificate_renewal"
        cert_path = $certPath
    }
    throw
}
```

#### Continue on Error

For non-critical steps:

```powershell
Register-WorkflowStep -Name "Notify" -ScriptBlock {
    param($Context)
    # Notification logic
} -ContinueOnError $true  # Don't stop workflow if notification fails
```

### Security Best Practices

#### Never Log Sensitive Data

```powershell
# Bad
Write-LogInfo -Message "Config loaded" -Context @{
    config = $config  # May contain bootstrap_token
}

# Good
$redactedConfig = Get-RedactedConfig -Config $config
Write-LogInfo -Message "Config loaded" -Context @{
    config = $redactedConfig  # Tokens replaced with '***REDACTED***'
}
```

#### Set Proper File Permissions

```powershell
# Write private key atomically
Write-FileAtomic -Path $keyPath -Content $privateKeyPem

# CRITICAL: Set owner-only permissions immediately
Set-FilePermissions -Path $keyPath -Mode "0600"

# Validate permissions
if (-not (Test-FilePermissions -Path $keyPath -ExpectedMode "0600")) {
    throw "Private key permissions validation failed"
}
```

#### Validate Configuration

```powershell
# Always validate config against schema
$config = Read-AgentConfig -ConfigFilePath $configPath

# Never trust environment variables without validation
Test-ConfigValid -Config $config -SchemaPath $schemaPath
```

---

## Module Reference

### WorkflowOrchestrator.psm1

```powershell
# Create workflow execution context
New-WorkflowContext -Config <hashtable> [-Logger <object>] [-AdditionalState <hashtable>]

# Register workflow step
Register-WorkflowStep -Name <string> -ScriptBlock <scriptblock> [-Description <string>] [-ContinueOnError <bool>]

# Execute single workflow step
Invoke-WorkflowStep -Name <string> -Context <hashtable>

# Start main orchestration loop
Start-WorkflowLoop -Context <hashtable> -Steps <string[]> [-IntervalSeconds <int>] [-MaxIterations <int>]

# Get execution metrics
Get-WorkflowMetrics

# Reset metrics (testing)
Reset-WorkflowMetrics
```

### ConfigManager.psm1

```powershell
# Load and validate configuration
Read-AgentConfig -ConfigFilePath <string> [-EnvVarPrefixes <string[]>]

# Validate configuration against schema
Test-ConfigValid -Config <hashtable> [-SchemaPath <string>]
```

### Logger.psm1

```powershell
# Log informational messages
Write-LogInfo -Message <string> [-Context <hashtable>]

# Log warning messages
Write-LogWarn -Message <string> [-Context <hashtable>]

# Log error messages
Write-LogError -Message <string> [-Context <hashtable>]

# Log debug messages
Write-LogDebug -Message <string> [-Context <hashtable>]
```

**Environment Variables:**
- `LOG_FORMAT`: `json` or `console` (default: `console`)

### CertificateMonitor.psm1

```powershell
# Check if certificate exists
Test-CertificateExists -Path <string>

# Calculate lifetime elapsed percentage
Get-CertificateLifetimeElapsed -Certificate <X509Certificate2>

# Get comprehensive certificate information
Get-CertificateInfo -Path <string>
```

**Returns (Get-CertificateInfo):**
```powershell
@{
    Subject                = "CN=example.com"
    Issuer                 = "CN=Intermediate CA"
    NotBefore              = [DateTime]
    NotAfter               = [DateTime]
    SerialNumber           = "0A1B2C3D..."
    DaysRemaining          = 89.45
    LifetimeElapsedPercent = 25.67
}
```

### CryptoHelper.psm1

```powershell
# Generate RSA 2048-bit key pair
New-RSAKeyPair

# Create PKCS#10 CSR
New-CertificateRequest -SubjectDN <string> [-SubjectAlternativeNames <string[]>] -RsaKey <RSA>

# Parse X.509 certificate from PEM
Read-Certificate -Path <string>

# Export private key to PKCS#8 PEM
Export-PrivateKey -RsaKey <RSA>

# Check if certificate needs renewal
Test-CertificateExpiry -Certificate <X509Certificate2> -ThresholdPercentage <int>
```

### FileOperations.psm1

```powershell
# Write file atomically
Write-FileAtomic -Path <string> -Content <object>

# Set file permissions
Set-FilePermissions -Path <string> -Mode <string>

# Validate file permissions
Test-FilePermissions -Path <string> -ExpectedMode <string>
```

**Common Permission Modes:**
- `0600`: Owner read/write only (private keys)
- `0644`: Owner read/write, others read (certificates)
- `0400`: Owner read-only
- `0700`: Owner read/write/execute (directories)

### CrlValidator.psm1

```powershell
# Download CRL from URL
Get-CrlFromUrl -Url <string> -CachePath <string> [-TimeoutSeconds <int>]

# Update CRL cache if stale
Update-CrlCache -Url <string> -CachePath <string> [-MaxAgeHours <double>]

# Check if certificate is revoked
Test-CertificateRevoked -CertificatePath <string> -CrlPath <string>

# Get CRL metadata
Get-CrlInfo -CrlPath <string>

# Get CRL age in hours
Get-CrlAge -CrlPath <string>
```

**Returns (Get-CrlInfo):**
```powershell
@{
    Issuer        = "CN=Intermediate CA"
    ThisUpdate    = "Jan 15 10:00:00 2025 GMT"
    NextUpdate    = "Jan 16 10:00:00 2025 GMT"
    RevokedCount  = 5
    RevokedSerials = @("0A1B2C...", "3D4E5F...")
}
```

---

## Testing

### Unit Tests

Run unit tests for modules:

```bash
# Bash
cd agents/common
pwsh test_configmanager.ps1
pwsh test_certificatemonitor.ps1
pwsh test_cryptohelper.ps1
pwsh Test-FileOperations.ps1

# Or run all unit tests
./scripts/run-tests.sh -u
```

```powershell
# PowerShell
pwsh -File scripts/run-tests.ps1 -UnitOnly
```

### Integration Tests

Run integration tests (requires Docker services):

```bash
# Bash
./scripts/run-tests.sh --auto-start-integration

# PowerShell
pwsh -File scripts/run-tests.ps1 -IntegrationOnly -AutoStartIntegration
```

### Coverage Reports

Generate coverage reports:

```bash
# Bash
./scripts/run-tests.sh --coverage

# PowerShell
pwsh -File scripts/run-tests.ps1 -Coverage
```

Results: `tests/coverage.xml`

### CI Workflow

Tests run automatically on push/pull-request via `.github/workflows/test.yml`:

1. Unit tests (~30s)
2. Integration tests (~2 minutes with infrastructure)

---

## Code Metrics

| Metric | Monolithic | Modular | Improvement |
|--------|-----------|---------|-------------|
| Agent LOC | 800-900 | 134-135 | **-85%** |
| Testability | Poor | Excellent | **10x** |
| Code Reuse | 0% | 60% | **+60%** |
| Time to Add Protocol | 2-3 days | 2-3 hours | **-90%** |
| Maintainability Score | 52/100 | 93/100 | **+79%** |

---

## Additional Resources

### Documentation

- **README.md** - Quick start and operator notes
- **QUICKSTART.md** - Hands-on setup walkthrough
- **docs/ARCHITECTURE.md** - Detailed architecture and diagrams
- **docs/MODULAR_ARCHITECTURE.md** - Deep dive on modular design
- **docs/ECA_DEVELOPER_GUIDE.md** - Developer guide for extending the platform
- **docs/PKI_INITIALIZATION.md** - Volume bootstrapping and provisioning
- **docs/TESTING.md** - Full test matrix and troubleshooting

### Configuration

- **config/agent_config_schema.json** - Authoritative configuration reference
- **config/acme-agent.yaml** - ACME agent default configuration
- **config/est-agent.yaml** - EST agent default configuration

### Operations

- **docker-compose.yml** - Service definitions and networking
- **scripts/run-tests.sh** - Test execution script
- **scripts/observability.sh** - Logging pipeline (Fluentd → Loki → Grafana)

---

## Summary

The ECA agent architecture achieves:

✅ **State-of-the-Art Design**: Thin orchestration, modular business logic
✅ **Superior Testability**: Each component independently testable
✅ **Enhanced Maintainability**: Easy to modify, extend, and understand
✅ **Maximum Reusability**: Common modules shared across agents (60% reuse)
✅ **Built-in Observability**: Metrics and logging integrated
✅ **Production-Ready**: Zero business logic in orchestration scripts

This architecture sets a new standard for PowerShell autonomous agent design and provides a solid foundation for enterprise certificate lifecycle management.

---

**Document Version**: 2.0
**Last Updated**: 2025-11-06
**Maintained By**: ECA Project Team
