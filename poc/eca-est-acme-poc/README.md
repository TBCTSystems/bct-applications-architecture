# Edge Certificate Agent (ECA) - Proof of Concept

## Overview

The Edge Certificate Agent (ECA) is a proof-of-concept system demonstrating automated certificate lifecycle management for edge devices and services. The system features autonomous PowerShell agents that handle certificate enrollment, renewal, and deployment using standard protocols (ACME for server certificates, EST for client certificates) without requiring external orchestration tools.

This PoC showcases file-based certificate distribution, service reload automation (NGINX), and end-to-end testing of mutual TLS (mTLS) connectivity in a containerized environment.

## Quickstart TL;DR

1. `./init-volumes.sh` (or `./init-volumes.ps1`) once per developer machine to seed step-ca, OpenXPKI, and Docker volumes.
2. `docker compose up -d` to launch ACME/EST agents, PKI services, target workloads, and optional observability.
3. `docker compose ps` and `docker compose logs -f eca-acme-agent` to confirm the stack is healthy and watch renewals in real time.
4. Hit `https://localhost:443` (target server), `https://localhost:9000` (step-ca), and `https://localhost:8443/.well-known/est/` (EST) to validate endpoints.

Need the full walkthrough with troubleshooting tips? See [QUICKSTART.md](QUICKSTART.md).

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
- Agents emit structured JSON logs to stdout so they can be inspected with `docker compose logs` or forwarded to your preferred aggregation stack.

> Need deeper detail? Read [docs/ECA_DEVELOPER_GUIDE.md](docs/ECA_DEVELOPER_GUIDE.md) for design diagrams, configuration schema guidance, testing strategy, and the extension checklist.

**Unified PKI Architecture:**
- ✅ Both ACME and EST certificates chain to the same step-ca Root CA
- ✅ Enables mutual TLS (mTLS) validation between server and client certificates
- ✅ Production-ready OpenXPKI EST implementation (fully automated setup)
- ✅ 100% automated initialization and configuration
- ✅ Zero manual steps required for deployment

## Documentation

### Core
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** – System overview and component responsibilities
- **[docs/ECA_DEVELOPER_GUIDE.md](docs/ECA_DEVELOPER_GUIDE.md)** – Configuration model, extension guidance, and internal design notes
- **[docs/PKI_INITIALIZATION.md](docs/PKI_INITIALIZATION.md)** – Step-by-step PKI + EST bootstrap reference
- **[docs/TESTING.md](docs/TESTING.md)** – Detailed testing strategy and expected outcomes

### Reference
- **[ACME Protocol Reference](docs/api/acme_protocol_reference.md)** – Condensed RFC 8555 primer
- **[EST Protocol Reference](docs/api/est_protocol_reference.md)** – Condensed RFC 7030 primer
- **[docs/OBSERVABILITY_WORKFLOW.md](docs/OBSERVABILITY_WORKFLOW.md)** – Fluentd → Loki → Grafana stack operations and dashboards
- Mermaid diagrams backing the architecture live in `docs/diagrams/` (render with https://mermaid.live).

## Testing

Run the test harness from the repository root:

```bash
# Unit tests only
./scripts/run-tests.sh -u

# Full suite: automatically start PKI/EST dependencies
./scripts/run-tests.sh --auto-start-integration
```

```powershell
pwsh -File scripts/run-tests.ps1 -UnitOnly
pwsh -File scripts/run-tests.ps1 -IntegrationOnly -AutoStartIntegration
```

Integration runs expect `pki`, `openxpki-db`, `openxpki-server`, `openxpki-client`, and `openxpki-web`. The auto-start flags spin them up and tear them down; otherwise, launch them manually with `docker compose up -d` before invoking the integration switch.

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

## Operations & Monitoring

All containers emit structured logs to stdout/stderr. Inspect them with standard Docker tooling:

```bash
docker compose logs -f eca-acme-agent
docker compose logs -f eca-est-agent
```

To verify artifacts, mount the published volumes locally:

```bash
docker run --rm -v server-certs:/data alpine ls -l /data
docker run --rm -v client-certs:/data alpine ls -l /data
```

Dedicated observability is available through Fluentd → Loki → Grafana:

- Start or refresh the stack with `./scripts/observability.sh demo` (PowerShell variant also available).
- Log in to Grafana at `http://localhost:3000` (`admin` / `eca-admin`) and open the **ECA** dashboards for aggregated agent logs and certificate insights.
- Use `./scripts/verify-logging.sh` / `.ps1` when you need to troubleshoot the log pipeline end-to-end.

## Troubleshooting

- `docs/PKI_INITIALIZATION.md` captures initialization pitfalls and recovery commands.
- `docs/ECA_DEVELOPER_GUIDE.md` covers configuration validation, renewal thresholds, and agent lifecycle details.
- `QUICKSTART.md` includes endpoint verification commands for ACME, EST, and the target workloads.

Typical checks:
- Verify agents can reach the PKI endpoints (`curl -k https://localhost:9000/health`, `curl -k https://localhost:8443/.well-known/est/cacerts`).
- Confirm certificates refresh on schedule by inspecting the `NotAfter` values in `server-certs/` and `client-certs/`.
- Ensure shared volumes (`server-certs`, `client-certs`, `challenge`) are mounted (`docker inspect <container>`).

---

**Project Status:** The PoC now ships only the components required for automated ACME + EST lifecycle management (step-ca, OpenXPKI, agents, target workloads, and tests).
