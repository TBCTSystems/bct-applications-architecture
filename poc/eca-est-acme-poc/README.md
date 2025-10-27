# Edge Certificate Agent (ECA) - Proof of Concept

## Overview

The Edge Certificate Agent (ECA) is a proof-of-concept system demonstrating automated certificate lifecycle management for edge devices and services. The system features autonomous PowerShell agents that handle certificate enrollment, renewal, and deployment using standard protocols (ACME for server certificates, EST for client certificates) without requiring external orchestration tools.

This PoC showcases file-based certificate distribution, service reload automation (NGINX), and end-to-end testing of mutual TLS (mTLS) connectivity in a containerized environment.

## Setup

### Prerequisites

- Docker and Docker Compose installed
- `step` CLI installed on your host machine (see [PKI Initialization Guide](docs/PKI_INITIALIZATION.md))
- Git (for cloning the repository)

### Quick Start

**Run the initializer once per developer machine:**

```bash
./init-volumes.sh
```

```powershell
.\init-volumes.ps1
```

This script bootstraps every Docker volume the PoC needs:
- Seeds `pki-data` with a fully configured step-ca hierarchy (root + ACME + EST)  
- Initializes OpenXPKI (config, database schema, certificates) so EST works out of the box  
- Wires the shared trust chain between step-ca and OpenXPKI

> Non-interactive environments can pass `ECA_CA_PASSWORD=... ./init-volumes.sh < /dev/null` (Linux/macOS) or `$env:ECA_CA_PASSWORD="..." ; .\init-volumes.ps1 -Force` (Windows/PowerShell).

**Bring the stack online:**

```bash
docker compose up -d
```

That’s it. ACME + EST agents start automatically and begin managing certificates for the target server/client.

**Verify everything is working:**

```bash
# Check all services
docker compose ps

# Test ACME endpoint
curl -k https://localhost:9000/health

# Test EST endpoint
curl -k https://localhost:8443/.well-known/est/cacerts | base64 -d | openssl pkcs7 -inform der -print_certs

# Test target server
curl -k https://localhost:443
```

**Monitor certificate lifecycle:**

```bash
# Watch ACME agent (auto-renewal)
docker compose logs -f eca-acme-agent

# Watch EST agent (enrollment)
docker compose logs -f eca-est-agent
```

Need more detail? Jump to [QUICKSTART.md](QUICKSTART.md) for screenshots, troubleshooting tips, and platform-specific notes.

## Architecture

The ECA PoC demonstrates a **unified PKI architecture** using industry-standard certificate enrollment protocols:

```
┌─────────────────────────────────────────────────────────────────┐
│                    ECA PoC Architecture                          │
│                   (Unified PKI with step-ca)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│          step-ca Root CA (Port 9000)                            │
│                      │                                           │
│         ┌────────────┴────────────┐                             │
│         ↓                         ↓                             │
│  ACME Intermediate         EST Intermediate CA                  │
│         │                         │                             │
│         ↓                         ↓                             │
│  ACME Protocol            OpenXPKI EST Server                   │
│  (RFC 8555)              (RFC 7030, Port 8443)                  │
│         │                         │                             │
│         ↓                         ↓                             │
│  ACME Agent                 EST Agent                           │
│         │                         │                             │
│         ↓                         ↓                             │
│  Target Server             Target Client                        │
│  (NGINX, HTTPS)            (Alpine, mTLS)                       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Key components:**
- **step-ca**: Root certificate authority providing both ACME and EST intermediate CAs
- **ACME Protocol**: Automated server certificate lifecycle (enrollment, renewal)
- **OpenXPKI EST Server**: Production-grade EST implementation with unified PKI
- **ACME Agent**: Autonomous PowerShell agent for server certificates
- **EST Agent**: Autonomous PowerShell agent for client certificates
- **Target Server**: NGINX with automated certificate deployment
- **Target Client**: Alpine-based client for mTLS testing

## ECA Design & Internals

- Shared PowerShell modules live under `agents/common/` for configuration management, logging, file operations, crypto utilities, and CRL handling.
- `agents/acme/agent.ps1` + `AcmeClient.psm1` implement the ACME renewal loop; `agents/est/agent.ps1` + `EstClient.psm1` implement EST bootstrap/enrollment.
- The control loop is consistent: load config → apply environment overrides → validate → decide → enroll/renew → atomically publish cert/key → log → sleep.
- `init-volumes.sh` / `init-volumes.ps1` seed step-ca, OpenXPKI config, and the MariaDB schema once so `docker compose up` is deterministic.
- Observability is baked in: every agent log event is structured JSON shipped via Fluentd → Loki → Grafana for dashboards and troubleshooting.

> Need deeper detail? Read [docs/ECA_DEVELOPER_GUIDE.md](docs/ECA_DEVELOPER_GUIDE.md) for design diagrams, configuration schema guidance, testing strategy, and the extension checklist.

**Unified PKI Architecture:**
- ✅ Both ACME and EST certificates chain to the same step-ca Root CA
- ✅ Enables mutual TLS (mTLS) validation between server and client certificates
- ✅ Production-ready OpenXPKI EST implementation (fully automated setup)
- ✅ 100% automated initialization and configuration
- ✅ Zero manual steps required for deployment

## Documentation

Complete documentation is available in the `docs/` directory:

### 📘 Core Documentation
- **[HANDOVER.md](HANDOVER.md)** - Complete project handover (start here!)
- **[ROADMAP.md](ROADMAP.md)** - Development roadmap and milestones (M1-M6)
- **[ECA_DEVELOPER_GUIDE.md](docs/ECA_DEVELOPER_GUIDE.md)** - Design, configuration, testing, and extension guide
- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - System architecture and design patterns
- **[PKI_INITIALIZATION.md](docs/PKI_INITIALIZATION.md)** - PKI setup and initialization guide
- **[CHANGELOG.md](CHANGELOG.md)** - Complete project history and changes

### 🔧 Deployment & Operations
- **[WINDOWS_DEPLOYMENT.md](docs/WINDOWS_DEPLOYMENT.md)** - Windows Server deployment guide (M3)
- **[OBSERVABILITY_WORKFLOW.md](docs/OBSERVABILITY_WORKFLOW.md)** - Observability operations guide (M2)
- **[CRL_IMPLEMENTATION.md](docs/CRL_IMPLEMENTATION.md)** - CRL/revocation implementation (M5)
- **[TESTING_QUICKSTART.md](TESTING_QUICKSTART.md)** - Testing guide

### 🌐 Web UI & Dashboards
- **[web-ui/README.md](web-ui/README.md)** - Interactive Web UI documentation (M4)
- **[web-ui/TESTING_INSTRUCTIONS.md](web-ui/TESTING_INSTRUCTIONS.md)** - Web UI testing guide
- **Web UI Access:** http://localhost:8888 (after running `web-ui/quickstart.sh`)

### 🔐 PKI & Protocols
- **[HANDOVER_UNIFIED_PKI.md](docs/HANDOVER_UNIFIED_PKI.md)** - Unified PKI integration
- **[EST_AUTOMATION_COMPLETE.md](docs/EST_AUTOMATION_COMPLETE.md)** - EST automation
- **[ACME Protocol Reference](docs/api/acme_protocol_reference.md)** - RFC 8555 details
- **[EST Protocol Reference](docs/api/est_protocol_reference.md)** - RFC 7030 details

## Testing

**Status (Oct 2025):**
- ✅ **Unit suite (108/108 tests)** passes via `./scripts/run-tests.sh -u`
- ✅ **Integration suite (9/9 tests)** runs via `./scripts/run-tests.sh --auto-start-integration` (auto-starts required PKI/EST stack)
- ✅ **GitHub Actions** (`.github/workflows/test.yml`) runs unit + integration tests on every push
- ✅ **Coverage**: 100% of critical paths tested with comprehensive unit test coverage

**Run it yourself**

```bash
# Fast path: unit tests only
./scripts/run-tests.sh -u

# Full suite: automatically start PKI/EST services via docker compose
./scripts/run-tests.sh --auto-start-integration

# Within Docker (consistent CI parity)
./scripts/run-tests-docker.sh -u
```

> **Heads-up:** Integration tests need the following services running: `pki openxpki-db openxpki-server openxpki-client openxpki-web`. The `--auto-start-integration` flag manages them for you; otherwise run `docker compose up -d ...` manually before `./scripts/run-tests.sh -i`.

Legacy validation artifacts remain under `docs/testing/validation_results.md`, but they pre-date the new roadmap work.

## Agent Configuration Overrides

- Both agents load `/agent/config.yaml` and then apply environment overrides. Overrides are evaluated first with an agent-specific prefix, then the legacy (unprefixed) variable name to preserve backward compatibility.
- Set `AGENT_ENV_PREFIX` (or `AGENT_NAME`, which automatically becomes `<AGENT_NAME>_`) to namespace overrides per deployment. This is critical on Windows Server where services often share the same environment block.
- Example (ACME agent):  
  ```bash
  export AGENT_ENV_PREFIX=mosquitto_eca_jwk_
  export mosquitto_eca_jwk_PKI_URL="https://pki.demo.lan:9443"
  export mosquitto_eca_jwk_DOMAIN_NAME="edge-gateway-01"
  ```
  The agent now reads the namespaced variables without colliding with other services.
- All documented overrides follow the `<prefix><UPPER_SNAKE_CASE>` pattern (e.g., `ACME_CERT_PATH`, `EST_DEVICE_NAME`, `mosquitto_eca_jwk_EST_BOOTSTRAP_TOKEN`).
- Need to onboard a new agent? Follow the checklist in [docs/ECA_DEVELOPER_GUIDE.md](docs/ECA_DEVELOPER_GUIDE.md#4-extending-the-platform-adding-a-new-agent) to define config keys, prefixes, Docker services, and tests without breaking existing deployments.

## Observability Stack

The ECA PoC includes a **production-ready observability stack** (Fluentd → Loki → Grafana) with 4 pre-configured dashboards:

1. **ECA - Certificate Lifecycle** - Agent heartbeats, certificate age, lifecycle events
2. **ECA - Operations** - Log severity distribution, error counts, log volume trends
3. **ECA - Logs Explorer** - Interactive log search with filters
4. **ECA - CRL Monitoring** - CRL age, revoked certificates, validation events (M5)

**Quick Start:**
```bash
# Linux/macOS/WSL
./scripts/observability.sh demo               # Full demo: start stack, verify, generate sample logs
./scripts/observability.sh verify -v          # Re-run verification only
```
```powershell
# Windows PowerShell
.\scripts\observability.ps1 demo
.\scripts\observability.ps1 verify -- -Verbose   # Pass-thru args after `--`
```

**Grafana Access:**
- URL: http://localhost:3000
- Username: `admin`
- Password: `eca-admin`
- Change the password via the Grafana UI before sharing the stack outside of local demos.

**Documentation:**
- **[docs/OBSERVABILITY_WORKFLOW.md](docs/OBSERVABILITY_WORKFLOW.md)** - Deep-dive on architecture, operations, and troubleshooting
- **[OBSERVABILITY_QUICKSTART.md](OBSERVABILITY_QUICKSTART.md)** - Five-minute setup checklist (keep handy for demos)

## Troubleshooting

Common issues and solutions are documented in the following guides:

- **[OBSERVABILITY_WORKFLOW.md](docs/OBSERVABILITY_WORKFLOW.md)** - Observability stack troubleshooting
- **[WINDOWS_DEPLOYMENT.md](docs/WINDOWS_DEPLOYMENT.md)** - Windows-specific issues
- **[CRL_IMPLEMENTATION.md](docs/CRL_IMPLEMENTATION.md)** - CRL and revocation troubleshooting
- **[HANDOVER.md](HANDOVER.md)** - Comprehensive troubleshooting guide (section 12)

Common issues:
- **Certificate expiration**: Check agent logs, verify PKI connectivity, review renewal thresholds
- **Service connectivity**: Verify Docker network, check firewall rules, test PKI endpoints
- **Agent logging**: Use `docker compose logs -f <agent>`, verify Fluentd → Loki pipeline
- **PKI configuration**: Review `pki/config/`, check step-ca logs, validate provisioners

---

**Project Status:** ✅ Production-Ready PoC (All Milestones M1-M6 Complete)

For detailed information about the project structure, see the directory layout in `docs/` or refer to the CodeMachine artifacts in `.codemachine/artifacts/plan/`.
