# Edge Certificate Agent (ECA) - Proof of Concept

**Autonomous certificate lifecycle management for Zero Trust architectures.**

---

## Table of Contents

1. [Introduction](#-introduction)
2. [Background](#-background)
3. [What This Demonstrates](#-what-this-demonstrates)
4. [Quick Start](#-quick-start)
5. [Architecture](#-architecture)
6. [Port Mappings](#-port-mappings)
7. [Setup & Installation](#-setup--installation)
8. [Configuration](#-configuration)
9. [Testing](#-testing)
10. [Observability](#-observability)
11. [Production Deployment](#-production-deployment)
12. [Troubleshooting](#-troubleshooting)
13. [Documentation Map](#-documentation-map)
14. [Contributing](#-contributing)
15. [License & Credits](#-license--credits)

---

## 1. Introduction

### What is This?

This Proof of Concept demonstrates **autonomous certificate management** using software agents that automatically enroll, renew, and deploy certificates without human intervention. It showcases the capabilities planned for **Lumia 1.1**—the next generation of certificate lifecycle management for Zero Trust architectures.

### Lumia 1.1 Context

**Production Deployment (Lumia 1.1)**:
- Deploys on **Windows Server** infrastructure
- Integrates with **customer PKI** environments
- PowerShell-based agents running as Windows services
- Supports enterprise certificate management workflows

**Production Certificate Targets**:
- **Server Certificates (ACME Protocol)**:
  - **Mosquitto MQTT Broker**: TLS certificates for secure MQTT communication (port 8883)
  - **MinIO Object Storage Server**: HTTPS certificates for S3-compatible API (port 9000)
- **Client Certificates (EST Protocol)**:
  - **Device Communication Service (DCS)**: mTLS client certificates for device-to-Lumia MQTT communication
  - **End of Run Service**: mTLS client certificates for Rika Procedural information extraction
  - **Bct.Common.Auditing.Host**: mTLS client certificates for audit event publishing to MQTT
  - Other C# services requiring mTLS authentication

**IIS Role** (NOT a certificate target):
- IIS already runs Lumia Web Server and its Web Interface
- **IIS serves as ACME HTTP-01 challenge responder** via virtual directory
- Virtual directory `/.well-known/acme-challenge/` maps to file system location where agent writes challenge files
- No need for agent to run separate HTTP server—IIS handles challenge validation

**This PoC (Demonstration)**:
- Uses **Docker containers** for cross-platform demonstration
- Uses **NGINX** as generic web server (production uses **IIS**)
- Provides self-contained environment for validation
- Demonstrates core concepts that will be **adapted for Windows Server deployment** as the software roadmap matures

> **Note**: The containerized approach is purely for PoC demonstration purposes. The PoC uses NGINX to demonstrate generic web server integration, but **Lumia 1.1 production will integrate with IIS** for Windows Server web hosting. The architecture patterns, protocols, and agent logic demonstrated here will be adapted for Windows Server deployment in Lumia 1.1.

### Why This Matters

Traditional manual certificate management doesn't scale for modern infrastructure:
- Manual renewals cause outages (LinkedIn 2023, Microsoft Teams 2020, Equifax 2017)
- Long-lived credentials (90+ days) create security risks
- Doesn't scale for distributed applications, IoT devices, edge computing

**Lumia 1.1 solves this** by enabling:
- Short-lived certificates (minutes to hours, not months)
- Automatic renewal before expiration
- Zero-downtime deployments
- Foundation of **Zero Trust security**

> **New to PKI or Zero Trust?** Start with **[CERTIFICATES_101.md](CERTIFICATES_101.md)** to understand the fundamentals before diving in.

---

## 2. Background

### The Problem: Traditional Certificate Management

**Manual workflow:**
1. Admin manually generates a private key
2. Admin creates a Certificate Signing Request (CSR)
3. Admin submits CSR to CA (often via web form or email)
4. CA admin manually validates request
5. CA issues certificate (hours or days later)
6. Admin manually installs certificate on server
7. Admin manually configures service (NGINX, Apache, etc.)
8. Admin sets calendar reminder for renewal in 90 days
9. **Repeat for every server, device, and microservice**

### Critical Problems

**1. Certificate Expiration Outages**
- Human error: Forgot to renew → service goes down
- Famous outages: LinkedIn (2023), Microsoft Teams (2020), Equifax monitoring (2017)
- Impact: Revenue loss, customer trust damage, emergency fire drills

**2. Long-Lived Credentials Are Dangerous**
- Traditional certificates: **1-2 years validity**
- If stolen: attacker has **months** of access
- Credential rotation is slow and manual

**3. Doesn't Scale for Modern Infrastructure**
- **Microservices**: Hundreds of services, each needing certificates
- **IoT devices**: Thousands of edge devices
- **Cloud-native**: Containers spin up/down dynamically
- **Manual processes** + **explosive scale** = **impossible**

**4. Poor Security Hygiene**
- Shared private keys across environments
- Keys stored in config files, wikis, or (worse) Slack
- No audit trail of certificate usage
- No automated compliance enforcement

> *"It's 2 AM. Your monitoring alerts that the production API is down. You SSH into the server and see: `certificate expired 3 hours ago`. You frantically search for the CA admin's phone number while your CEO emails asking why customers can't log in."*

**There has to be a better way.**

For a comprehensive explanation of PKI fundamentals, Zero Trust architecture, and how ECA solves these problems, see **[CERTIFICATES_101.md](CERTIFICATES_101.md)**.

---

## 3. What This Demonstrates

### Core Capabilities

✅ **Automated Certificate Enrollment**
- ACME agent requests server certificates via HTTP-01 challenge (RFC 8555)
- EST agent requests client certificates via mTLS enrollment (RFC 7030)
- No manual CSR submission, no human approval workflow

✅ **Proactive Automatic Renewal**
- Certificates renew at 33% remaining lifetime (configurable)
- Zero downtime: new cert installed before old expires
- Configurable lifetimes: minutes, hours, or days

✅ **Service Reload Automation**
- Agents automatically reload NGINX after certificate updates
- Graceful reloads: existing connections continue, new connections use new cert

✅ **Certificate Revocation (CRL)**
- step-ca publishes Certificate Revocation Lists
- Agents check CRL before renewal
- Revoked certificates trigger immediate renewal

✅ **Mutual TLS (mTLS)**
- Server and client certificates chain to same root CA
- Client certificate required for mTLS connections
- Demonstrates Zero Trust authentication

✅ **Full Observability**
- Structured JSON logging to stdout
- Fluentd → Loki → Grafana pipeline
- Real-time dashboards: certificate expiration, renewal rates, errors

✅ **Unified PKI Architecture**
- Single root CA (step-ca) for both ACME and EST
- Production-grade OpenXPKI EST server
- Complete trust chain shared between protocols

### Supported Protocols

**ACME (Automatic Certificate Management Environment)**
- RFC 8555 standard
- HTTP-01 challenge validation
- Best for: Web servers, load balancers, API gateways
- Made famous by: Let's Encrypt (3+ billion certificates issued)

**EST (Enrollment over Secure Transport)**
- RFC 7030 standard
- mTLS authentication with bootstrap certificates
- Best for: IoT devices, mobile clients, enterprise endpoints
- Made famous by: Cisco, Microsoft, Apple device enrollment

### Real-World Use Cases

- **Microservices:** Kubernetes pods get certificates on startup, renew automatically
- **IoT devices:** Factory equipment, medical devices, industrial sensors
- **Edge computing:** CDN nodes, 5G base stations, retail kiosks
- **Cloud workloads:** Auto-scaling groups, serverless functions
- **Zero Trust networks:** Every service-to-service connection uses mTLS

---

## 4. Quick Start

**Get running in 3 commands:**

```bash
# 1. Run complete integration test (initializes + starts + validates)
./integration-test.sh

# 2. Watch autonomous renewals in action
docker compose logs -f eca-acme-agent

# 3. Access Grafana dashboard
open http://localhost:4219  # admin/eca-admin
```

**Validate endpoints:**
```bash
curl -k https://localhost:4210/health  # step-ca
curl -k https://localhost:4213/.well-known/est/cacerts  # EST
curl -k https://localhost:4214  # Target server (NGINX)
```

**Expected output:**
- step-ca returns `{"status":"ok"}`
- EST returns base64-encoded CA certificates
- NGINX returns HTML welcome page

**Custom port range:** All external services use ports 4210-4230 to avoid conflicts with other development environments.

---

## 5. Architecture

### High-Level Component Diagram

```
┌─────────────────────────────────────────────────────────┐
│                Certificate Authority                     │
│                                                          │
│  ┌─────────────┐         ┌──────────────┐              │
│  │  step-ca    │         │  OpenXPKI    │              │
│  │  (ACME CA)  │         │  (EST Server)│              │
│  │  Port 4210  │         │  Port 4213   │              │
│  └──────┬──────┘         └──────┬───────┘              │
└─────────┼─────────────────────── ┼──────────────────────┘
          │                        │
          │ ACME                   │ EST (mTLS)
          │ (HTTP-01)              │ (Bootstrap cert)
          │                        │
┌─────────▼────────┐     ┌─────────▼────────┐
│  ACME Agent      │     │  EST Agent       │
│  (Server certs)  │     │  (Client certs)  │
│                  │     │                  │
│  • Monitors exp  │     │  • Monitors exp  │
│  • Renews auto   │     │  • Renews auto   │
│  • Reloads NGINX │     │  • Updates store │
└─────────┬────────┘     └─────────┬────────┘
          │                        │
          │ Installs cert          │ Uses cert
          ▼                        ▼
┌─────────────────┐      ┌─────────────────┐
│  Target Server  │◄────►│  Target Client  │
│  (NGINX)        │ mTLS │  (curl, app)    │
│  Port 4214      │      │                 │
└─────────────────┘      └─────────────────┘
          │
          │ Logs (JSON)
          ▼
┌─────────────────────────────────────────┐
│   Observability Stack                    │
│   Fluentd → Loki → Grafana              │
│   Port 4219 (Grafana)                    │
└─────────────────────────────────────────┘
```

### Key Components

| Component | Purpose | Technology | Port(s) |
|-----------|---------|------------|---------|
| **step-ca** | Certificate Authority providing ACME and EST intermediate CAs | Smallstep CA | 4210 (HTTPS), 4211 (CRL) |
| **OpenXPKI** | Production-grade EST server (RFC 7030 compliant) | OpenXPKI + MariaDB | 4212 (Web UI), 4213 (EST) |
| **ACME Agent** | PowerShell agent for server certificates | PowerShell 7+ | N/A (agent) |
| **EST Agent** | PowerShell agent for client/device certificates | PowerShell 7+ | N/A (agent) |
| **Target Server** | NGINX demonstrating automated cert deployment | NGINX | 4214 (HTTPS), 4215 (HTTP) |
| **Target Client** | Alpine-based client for mTLS testing | Alpine Linux | N/A (client) |
| **Fluentd** | Log collection and forwarding | Fluentd | 4217 |
| **Loki** | Log storage and indexing | Grafana Loki | 4218 |
| **Grafana** | Log visualization and dashboards | Grafana | 4219 |

> **Deep dive:** See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed component descriptions, data flows, design decisions, and security considerations.

---

## 6. Port Mappings

The ECA PoC uses the **4210-4230 port range** to avoid conflicts with common development tools.

### Complete Port Allocation Table

| Port | Service | Protocol | Purpose | External Access |
|------|---------|----------|---------|-----------------|
| **4210** | step-ca (PKI) | HTTPS | ACME/EST CA API, health checks | ✅ Localhost |
| **4211** | step-ca (CRL) | HTTP | Certificate Revocation List distribution | ✅ Localhost |
| **4212** | OpenXPKI Web | HTTP | PKI Web UI (admin interface) | ✅ Localhost |
| **4213** | OpenXPKI EST | HTTPS | EST Protocol endpoint (mTLS) | Internal only |
| **4214** | Target Server | HTTPS | NGINX with ACME cert (demo) | ✅ Localhost |
| **4215** | Target Server | HTTP | NGINX HTTP (ACME challenges) | Internal only |
| **4216** | Web UI | HTTP | React Dashboard (future) | Reserved |
| **4217** | Fluentd | TCP | Log ingestion endpoint | Internal only |
| **4218** | Loki | HTTP | Log storage API | Internal only |
| **4219** | Grafana | HTTP | Observability dashboard | ✅ Localhost |

### Why This Port Range?

- **Avoid Common Conflicts**: Stays clear of default dev tool ports (3000-3999, 8000-8999)
- **Memorable Pattern**: Sequential numbering (4210, 4211, 4212, etc.)
- **IANA Unassigned**: Falls in IANA unassigned port range
- **Consistent Grouping**: All ECA services in one range for easy firewall rules

> **Full details:** See [CONFIGURATION.md](CONFIGURATION.md) for customizing ports and all configuration options.

---

## 7. Setup & Installation

### Prerequisites

**Required:**
- Docker (20.10+) and Docker Compose v2
- step CLI (for PKI initialization)
- Bash (Linux/macOS) or PowerShell 7+ (Windows)
- 4GB RAM available for Docker

**Optional:**
- PowerShell 7+ (for running integration tests)
- curl (for manual endpoint testing)

**Verify installations:**
```bash
docker --version          # Should be 20.10+
docker compose version    # Should be v2.x
step version              # Should be 0.24+
pwsh --version            # Optional: PowerShell 7+
```

### Install step CLI

**macOS:**
```bash
brew install step
```

**Linux:**
```bash
wget https://dl.step.sm/gh-release/cli/docs-ca-install/v0.24.4/step_linux_0.24.4_amd64.tar.gz
tar -xf step_linux_0.24.4_amd64.tar.gz
sudo cp step_0.24.4/bin/step /usr/local/bin/
```

**Windows:**
```bash
choco install step
# OR download from https://smallstep.com/docs/step-cli/installation
```

### Installation Steps

**Option 1: Automated Testing (Recommended)**

Run the complete integration test suite:
```bash
./integration-test.sh
```

This will:
1. Check prerequisites
2. Initialize PKI volumes
3. Start all services
4. Validate endpoints
5. Run integration tests
6. Show results

**Option 2: Manual Setup**

```bash
# Step 1: Initialize PKI volumes (once per machine)
./integration-test.sh --init-only

# Step 2: Start all services
docker compose up -d

# Step 3: Verify everything works
./integration-test.sh --validate-only
```

**Option 3: Quick Mode (Skip Init if Already Done)**

```bash
# Faster subsequent runs
./integration-test.sh --quick
```

### Non-Interactive Initialization

For CI/CD or automated deployments:

```bash
# Linux/macOS
export ECA_CA_PASSWORD="your-secure-password"
./integration-test.sh

# PowerShell
$env:ECA_CA_PASSWORD = "your-secure-password"
.\integration-test.ps1
```

### Verification

**Check container status:**
```bash
docker compose ps
```
Expected: All containers showing `healthy` or `Up` status.

**Validate endpoints:**
```bash
# PKI (step-ca)
curl -k https://localhost:4210/health
# Expected: {"status":"ok"}

# EST
curl -k https://localhost:4213/.well-known/est/cacerts | base64 -d | openssl pkcs7 -inform der -print_certs
# Expected: Root CA + Intermediate CA certificates

# CRL
curl http://localhost:4211/crl/ca.crl | openssl crl -inform DER -text -noout
# Expected: Certificate Revocation List

# Target Server
curl -k https://localhost:4214
# Expected: NGINX welcome page

# Grafana Dashboard
open http://localhost:4219
# Username: admin, Password: eca-admin
```

**Watch agents in action:**
```bash
# ACME agent (server certificate renewal)
docker compose logs -f eca-acme-agent

# EST agent (client certificate enrollment)
docker compose logs -f eca-est-agent
```

---

## 8. Configuration

### Environment Variables (Basics)

**ACME Agent (Server Certificates):**
```bash
ACME_PKI_URL=https://pki:9000            # step-ca URL (internal)
ACME_DOMAIN_NAME=target-server           # Domain for certificate
ACME_CERT_PATH=/certs/server/server.crt  # Certificate output
ACME_KEY_PATH=/certs/server/server.key   # Private key output
ACME_RENEWAL_THRESHOLD_PCT=33            # Renew at 33% remaining lifetime
ACME_CHECK_INTERVAL_SEC=21600            # Check every 6 hours
```

**EST Agent (Client Certificates):**
```bash
EST_PKI_URL=https://openxpki-web:443     # OpenXPKI URL (internal)
EST_DEVICE_NAME=client-device-001        # Device identifier
EST_CERT_PATH=/certs/client/cert.pem     # Certificate output
EST_KEY_PATH=/certs/client/key.pem       # Private key output
EST_BOOTSTRAP_CERT_PATH=/home/step/bootstrap-certs/bootstrap-client.pem
EST_BOOTSTRAP_KEY_PATH=/home/step/bootstrap-certs/bootstrap-client.key
EST_CRL_ENABLED=true                     # Enable CRL validation
EST_CRL_URL=http://pki:4211/crl/ca.crl   # CRL distribution point
```

**Certificate Lifetimes:**
- **Root CA**: 10 years (configured during init-volumes.sh)
- **Intermediate CA**: 5 years (configured during init-volumes.sh)
- **Server Certificates (ACME)**: 24 hours (default)
- **Client Certificates (EST)**: 1 hour (default)

### Customizing Configuration

Edit `docker-compose.yml` to change environment variables:

```yaml
services:
  eca-acme-agent:
    environment:
      ACME_RENEWAL_THRESHOLD_PCT: 50  # Change renewal threshold to 50%
      ACME_CHECK_INTERVAL_SEC: 3600   # Check every hour
```

> **Full reference:** See [CONFIGURATION.md](CONFIGURATION.md) for:
> - All environment variables and valid ranges
> - Docker volumes and resource limits
> - Advanced tuning (performance, network, storage)
> - Production hardening checklist

---

## 9. Testing

### Run Full Test Suite

```bash
./integration-test.sh
```

**What it tests:**
- ✅ ACME enrollment and renewal
- ✅ EST enrollment with mTLS
- ✅ Certificate revocation (CRL)
- ✅ Service reloads (NGINX)
- ✅ Endpoint availability
- ✅ Observability pipeline

### Run Specific Tests

```bash
# Only validate endpoints (fast)
./integration-test.sh --validate-only

# Only run Pester tests
./integration-test.sh --test-only

# Skip initialization (faster subsequent runs)
./integration-test.sh --quick

# Keep stack running after tests
./integration-test.sh --no-cleanup
```

### Unit Tests

```bash
# Run unit tests in Docker
docker compose run --rm test-runner pwsh -Command "
    Invoke-Pester -Path ./tests/unit -Output Detailed
"

# Run specific module tests
docker compose run --rm test-runner pwsh -Command "
    Invoke-Pester -Path ./tests/unit/CrlValidator.Tests.ps1 -Output Detailed
"
```

### Manual Testing

**Test mTLS connection:**
```bash
# Client with valid certificate → SUCCESS
docker compose exec target-client curl --cert /certs/client/cert.pem \
  --key /certs/client/key.pem https://target-server

# Client without certificate → DENIED
curl https://localhost:4214
```

> **Complete testing guide:** See [TESTING.md](TESTING.md) for:
> - Test scenarios and expected outcomes
> - Manual validation procedures
> - Debugging tips
> - CI/CD integration examples

---

## 10. Observability

### Log Aggregation Pipeline

**Architecture:**
```
Agents → Fluentd → Loki → Grafana
```

All agents emit structured JSON logs to stdout, collected by Fluentd, indexed in Loki, and visualized in Grafana.

### Start Observability Stack

```bash
./scripts/observability.sh demo
```

This will:
1. Start Fluentd, Loki, and Grafana services
2. Provision Grafana dashboards automatically
3. Verify log ingestion
4. Print access details

**Verify log pipeline:**
```bash
./scripts/observability.sh verify
```

### Grafana Dashboard

**Access:** http://localhost:4219

**Credentials:**
- Username: `admin`
- Password: `eca-admin`

**Dashboards show:**
- Certificate expiration countdown
- Renewal success/failure rates
- Agent health status
- Error rates and trends
- HTTP-01 challenge success rates
- Service reload operations

### Query Logs with LogQL

**In Grafana → Explore:**
```logql
# All renewal events
{container_name=~"eca-.*-agent"} |= "renewal"

# Errors only
{container_name=~"eca-.*-agent"} | json | level="error"

# Certificate installations
{container_name=~"eca-.*-agent"} |= "Certificate installed"

# ACME challenges
{container_name="eca-acme-agent"} |= "HTTP-01 challenge"
```

### Direct Log Access

```bash
# View all agent logs
docker compose logs -f eca-acme-agent eca-est-agent

# View specific service logs
docker compose logs -f target-server

# Filter for errors
docker compose logs | grep -i error
```

---

## 11. Production Deployment

### Lumia 1.1 Production Considerations

**Windows Server Deployment:**
- **Platform**: Windows Server 2019/2022
- **Agents**: PowerShell 7+ modules running as Windows services
- **Web Server**: IIS (replaces NGINX in PoC)
- **PKI Integration**: Customer-provided PKI (replaces step-ca)
- **Certificate Storage**: Windows Certificate Store (replaces filesystem)

**IIS Integration for ACME:**
- IIS serves ACME HTTP-01 challenge files via virtual directory
- Virtual directory: `/.well-known/acme-challenge/` → filesystem location
- ACME agent writes challenge tokens, IIS serves them to CA
- No separate HTTP server needed

**Target Services:**
- **Mosquitto MQTT Broker** (TLS server certificates via ACME)
- **MinIO Object Storage** (HTTPS server certificates via ACME)
- **Device Communication Service** (mTLS client certificates via EST)
- **End of Run Service** (mTLS client certificates via EST)
- **Bct.Common.Auditing.Host** (mTLS client certificates via EST)

### What's Production-Ready

✅ **ACME and EST protocol implementations**
- RFC 8555 (ACME) and RFC 7030 (EST) compliant
- Proven interoperability with Smallstep and OpenXPKI

✅ **Agent architecture and error handling**
- Robust retry logic with exponential backoff
- Comprehensive error logging and diagnostics

✅ **Observability patterns**
- Structured JSON logging
- Integration with centralized log aggregation
- Real-time monitoring and alerting

✅ **Configuration management approach**
- Environment-based configuration (12-factor app)
- Sensible defaults, easy to customize

### What Needs Hardening for Production

⚠️ **PKI Security**
- Use HSM for CA private key protection
- Separate root CA (offline) from intermediate CA (online)
- Implement proper key ceremony and access controls

⚠️ **Secret Management**
- Use vault (HashiCorp Vault, Azure Key Vault, AWS KMS)
- Don't store passwords in environment variables

⚠️ **Network Segmentation**
- Isolate CA from agents (separate VLANs/subnets)
- Firewall rules limiting access to PKI endpoints
- mTLS for all agent-to-CA communication

⚠️ **High Availability**
- Multiple CA instances behind load balancer
- Database replication (MariaDB primary-replica)
- CRL distribution redundancy

⚠️ **Monitoring and Alerting**
- Production-grade observability (Prometheus, DataDog, Splunk)
- Alert on: renewal failures, certificate near expiry, agent failures
- PagerDuty integration for critical events

⚠️ **Disaster Recovery**
- Automated daily backups of PKI volumes
- Documented recovery procedures
- Regular disaster recovery drills

⚠️ **Compliance and Audit Logging**
- Tamper-proof audit logs
- Regulatory compliance (SOC 2, ISO 27001, PCI DSS)
- Certificate lifecycle audit trail

### Scaling Considerations

- **1-100 agents:** This architecture works as-is
- **100-1000 agents:** Add step-ca replicas, cache CRLs
- **1000+ agents:** Consider distributed CA, OCSP instead of CRL

---

## 12. Troubleshooting

### Common Issues

**"Docker daemon not running"**
```bash
sudo systemctl start docker  # Linux
# OR
open -a Docker  # macOS
```

**"step CLI not found"**
```bash
brew install step  # macOS
# OR see installation instructions in Setup section
```

**"Volume is in use"**
```bash
docker compose down
./integration-test.sh
```

**"Endpoint validation failed"**
```bash
# Check container logs
docker compose logs pki

# Check if services are healthy
docker compose ps

# Wait longer for services to start
sleep 30 && ./integration-test.sh --validate-only
```

**"Certificate renewal not happening"**
```bash
# Check agent logs
docker compose logs -f eca-acme-agent

# Verify certificate expiration time
docker compose exec target-server cat /certs/server/server.crt | openssl x509 -noout -enddate

# Check agent configuration
docker compose exec eca-acme-agent env | grep ACME_
```

**"Permission denied errors"**
```bash
# Fix Docker permissions (Linux)
sudo usermod -aG docker $USER
newgrp docker

# Fix file permissions in volumes
docker compose exec eca-acme-agent chmod 644 /certs/server/server.crt
docker compose exec eca-acme-agent chmod 600 /certs/server/server.key
```

> **More help:** See [FAQ.md](FAQ.md) for:
> - Comprehensive troubleshooting guide
> - Common error messages and solutions
> - Performance tuning tips
> - Known limitations

---

## 13. Documentation Map

This project includes comprehensive documentation covering all aspects of the ECA PoC.

### Essential Reading

| Document | Purpose | Who Should Read |
|----------|---------|----------------|
| **[README.md](README.md)** | Quick start, overview, setup | **Everyone** - You are here! |
| **[CERTIFICATES_101.md](CERTIFICATES_101.md)** | PKI fundamentals, ECA concept, Zero Trust | **Everyone** - Start here if new to PKI |
| **[ARCHITECTURE.md](ARCHITECTURE.md)** | Technical design, components, data flows | Architects, developers |
| **[CONFIGURATION.md](CONFIGURATION.md)** | All settings, ports, environment vars | Operators, developers |
| **[TESTING.md](TESTING.md)** | Testing guide, validation procedures | QA, CI/CD engineers |
| **[FAQ.md](FAQ.md)** | Troubleshooting, common issues | **Everyone** - When things go wrong |

### Suggested Reading Order

**For beginners:**
1. CERTIFICATES_101.md → README.md → TESTING.md → FAQ.md

**For operators:**
1. README.md → CONFIGURATION.md → TESTING.md → FAQ.md

**For architects:**
1. CERTIFICATES_101.md → ARCHITECTURE.md → CONFIGURATION.md → TESTING.md

**For developers:**
1. README.md → ARCHITECTURE.md → Testing locally → Contributing

### Quick Links

- 📖 **[PKI Fundamentals](CERTIFICATES_101.md)** - Understand digital certificates and Zero Trust
- 🏗️ **[Architecture Guide](ARCHITECTURE.md)** - Deep dive into system design
- ⚙️ **[Configuration Reference](CONFIGURATION.md)** - Customize agents and settings
- 🧪 **[Testing Guide](TESTING.md)** - Validate and debug the PoC
- ❓ **[FAQ & Troubleshooting](FAQ.md)** - Solve common problems

---

## 14. Contributing

### How to Extend This PoC

**Add a new protocol:**
1. Create new agent in `agents/{protocol}-agent/`
2. Implement protocol-specific enrollment logic
3. Add Pester unit tests in `tests/unit/`
4. Update `docker-compose.yml` with new service
5. Document in ARCHITECTURE.md

**Add a new service target:**
1. Define service in `docker-compose.yml`
2. Configure agent to manage its certificates
3. Add validation tests in `tests/integration/`
4. Document in CONFIGURATION.md

**Improve observability:**
1. Add custom Grafana dashboards in `grafana/provisioning/dashboards/`
2. Create Loki alerting rules in `loki-config.yml`
3. Add structured log events in agents
4. Document new metrics in ARCHITECTURE.md

**Enhance agents:**
1. Create PowerShell modules in `agents/common/modules/`
2. Add comprehensive Pester tests
3. Update agent scripts to import new modules
4. Document in code comments and ARCHITECTURE.md

### Development Workflow

```bash
# 1. Make changes to agent code or configuration
# 2. Run unit tests
./scripts/run-tests.sh -u

# 3. Build and start services
docker compose up -d --build

# 4. Run integration tests
./integration-test.sh --quick

# 5. Check logs for errors
docker compose logs -f eca-acme-agent

# 6. Iterate until tests pass
```

### Code Standards

- **PowerShell**: Follow PSScriptAnalyzer guidelines
- **Documentation**: Update relevant .md files with changes
- **Testing**: Add Pester tests for all new functionality
- **Logging**: Use structured JSON logging with consistent fields
- **Error Handling**: Robust try-catch with informative error messages

### Testing Your Changes

```bash
# Lint PowerShell code
pwsh -Command "Invoke-ScriptAnalyzer -Path agents/ -Recurse"

# Run all tests
./integration-test.sh

# Check for breaking changes
./integration-test.sh --validate-only
```

---

## 15. License & Credits

### License

This project is provided as a Proof of Concept for **Lumia 1.1** certificate management capabilities.

**Copyright © 2025**

### Technology Credits

This PoC leverages excellent open-source technologies:

**PKI Infrastructure:**
- **[Smallstep step-ca](https://github.com/smallstep/certificates)** - Modern CA with ACME/EST support
- **[OpenXPKI](https://www.openxpki.org/)** - Production-grade PKI framework

**Container Orchestration:**
- **[Docker](https://www.docker.com/)** - Container runtime
- **[Docker Compose](https://docs.docker.com/compose/)** - Multi-container orchestration

**Observability:**
- **[Grafana](https://grafana.com/)** - Visualization and dashboards
- **[Grafana Loki](https://grafana.com/oss/loki/)** - Log aggregation
- **[Fluentd](https://www.fluentd.org/)** - Log collection

**Web Server:**
- **[NGINX](https://nginx.org/)** - High-performance web server (PoC demo)

**Testing:**
- **[Pester](https://pester.dev/)** - PowerShell testing framework
- **[PowerShell](https://github.com/PowerShell/PowerShell)** - Cross-platform automation

### Standards Implemented

- **RFC 8555** - Automatic Certificate Management Environment (ACME)
- **RFC 7030** - Enrollment over Secure Transport (EST)
- **RFC 5280** - Internet X.509 Public Key Infrastructure Certificate and CRL Profile
- **RFC 6960** - X.509 Internet Public Key Infrastructure Online Certificate Status Protocol (OCSP)

### Acknowledgments

Special thanks to:
- **Smallstep** for excellent ACME CA implementation
- **OpenXPKI Community** for production-grade EST server
- **Let's Encrypt** for popularizing automated certificate management
- **IETF** for standardizing ACME and EST protocols

---

## Ready to Get Started?

**Run the PoC now:**
```bash
./integration-test.sh
```

**See autonomous certificate management in action!** 🚀🔒

Watch agents automatically:
- Enroll certificates using ACME and EST
- Renew certificates before expiration
- Reload services with zero downtime
- Validate against CRL for revocation
- Log all events to centralized observability stack

**Questions?** Check [FAQ.md](FAQ.md) or review the [documentation map](#13-documentation-map) above.

**New to PKI?** Start with [CERTIFICATES_101.md](CERTIFICATES_101.md) to learn the fundamentals.

---

**Welcome to Zero Trust infrastructure with autonomous certificate management!** 🎉
