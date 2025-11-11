# Edge Certificate Agent (ECA) Proof of Concept

Autonomous certificate lifecycle management reference implementation for Zero Trust deployments.

---

## Table of Contents
1. [Introduction](#1-introduction)
2. [Background](#2-background)
3. [Scope and Capabilities](#3-scope-and-capabilities)
4. [Quick Start](#4-quick-start)
5. [Architecture](#5-architecture)
6. [Port Mappings](#6-port-mappings)
7. [Installation and Setup](#7-installation-and-setup)
8. [Configuration](#8-configuration)
9. [Testing](#9-testing)
10. [Observability](#10-observability)
11. [Production Readiness](#11-production-readiness)
12. [Troubleshooting](#12-troubleshooting)
13. [Documentation Map](#13-documentation-map)
14. [Contributing](#14-contributing)
15. [License and Credits](#15-license-and-credits)

---

## 1. Introduction

### Purpose

The Edge Certificate Agent (ECA) proof of concept demonstrates autonomous certificate enrollment, renewal, installation, and service reload across server and client workloads. The environment provides a contained laboratory for validating certificate automation patterns before adopting Lumia 1.1 in production.

### Lumia 1.1 Alignment

- **Production platform**: Windows Server 2019/2022 with PowerShell-based services and IIS.
- **Certificate authority integration**: Customer PKI, hardware-backed key protection, and Windows Certificate Store.
- **Target workloads**: Mosquitto MQTT, MinIO, Device Communication Service, End of Run Service, Bct.Common.Auditing.Host, and additional C# services that require mTLS.
- **ACME challenges**: IIS hosts the `/.well-known/acme-challenge/` virtual directory consumed by the agents; no standalone HTTP listener is required.

### Why It Matters

Manual certificate processes do not keep pace with microservices, IoT, or edge deployments. Typical pain points include:
- Expiration-related outages (LinkedIn 2023, Microsoft Teams 2020, Equifax 2017).
- Year-long credentials that increase the blast radius of key compromise.
- Inability to rotate secrets at the scale demanded by Zero Trust programs.

The PoC validates how Lumia 1.1 replaces manual steps with short-lived certificates, proactive renewals, and automated reloads. If you are new to PKI or Zero Trust concepts, review `CERTIFICATES_101.md` before diving in.

---

## 2. Background

### Traditional Certificate Workflow

1. Generate a private key.
2. Create and submit a CSR.
3. Wait for manual validation and issuance.
4. Transfer certificates to the target host.
5. Configure web servers and clients.
6. Track renewals in spreadsheets or calendars.

### Resulting Challenges

- **Operational risk**: Human error causes outages when certificates expire.
- **Security debt**: Long-lived credentials remain valid after theft.
- **Scale limitations**: Hundreds of services or thousands of devices overwhelm manual teams.
- **Poor hygiene**: Keys land in shared drives, chat threads, or wiki snippets without auditing.

`CERTIFICATES_101.md` explains the underlying PKI mechanics and how ECA closes these gaps.

---

## 3. Scope and Capabilities

### Core Capabilities

- Automated ACME (server) and EST (client) enrollments with no manual CSR handling.
- Proactive renewals when one-third of the certificate lifetime remains (configurable).
- Zero-downtime service reloads (NGINX), with hooks for other targets.
- CRL awareness and revocation-driven re-enrollment.
- Mutual TLS between target server and target client workloads.
- Unified observability through Fluentd, Loki, and Grafana.

### Supported Protocols

| Protocol | Standard | Primary Use | Implementation Notes |
|----------|----------|-------------|----------------------|
| ACME | RFC 8555 | Server certificates, HTTP-01 validation | step-ca provides the CA, PowerShell agent performs challenges |
| EST | RFC 7030 | Client certificates and device enrollment | OpenXPKI terminates mTLS; PowerShell agent manages bootstrap credentials |

### Representative Use Cases

- Automated certificates for API gateways, load balancers, and web servers.
- mTLS for device fleets or service-to-service calls.
- Edge workloads that need short-lived credentials with minimal operational overhead.
- Pre-production validation for Zero Trust migration programs.

---

## 4. Quick Start

```bash
# Run the end-to-end integration workflow (initialization, startup, validation, tests)
./integration-test.sh

# Observe autonomous renewals
docker compose logs -f eca-acme-agent

# Explore dashboards
open http://localhost:4219   # Username: admin, Password: eca-admin
```

### Endpoint Checks

```bash
curl -k https://localhost:4210/health                       # step-ca
curl -k https://localhost:4213/.well-known/est/cacerts      # EST ca-certs
curl -k https://localhost:4214                              # Target server (NGINX)
```

Expected results: `step-ca` returns `{"status":"ok"}`, the EST endpoint streams the CA bundle, and NGINX serves the welcome page. External ports stay within the 4210–4230 range to avoid clashes with other tooling.

---

## 5. Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────┐
│                 Certificate Authority                    │
│                                                         │
│   ┌─────────────┐       ┌──────────────┐                │
│   │  step-ca    │       │  OpenXPKI    │                │
│   │  (ACME CA)  │       │  (EST Server)│                │
│   │  Port 4210  │       │  Port 4213   │                │
│   └──────┬──────┘       └──────┬───────┘                │
└──────────┼─────────────────────┼────────────────────────┘
           │ ACME (HTTP-01)      │ EST (mTLS)
┌──────────▼────────┐    ┌───────▼─────────┐
│   ACME Agent      │    │   EST Agent     │
│   Server certs    │    │   Client certs  │
└─────────┬─────────┘    └────────┬────────┘
          │ Certificates           │ Credentials
┌─────────▼────────┐    mTLS     ┌─▼────────────┐
│  Target Server   │◄───────────►│ Target Client│
│  NGINX, 4214     │             │ curl/app     │
└─────────┬────────┘             └──────────────┘
          │ JSON logs
          ▼
┌───────────────────────────────┐
│ Fluentd → Loki → Grafana      │
│ Port 4219 (Grafana)           │
└───────────────────────────────┘
```

### Key Components

| Component | Role | Technology | Port(s) |
|-----------|------|------------|---------|
| step-ca | ACME/EST CA and CRL distribution | Smallstep | 4210 (HTTPS), 4211 (CRL) |
| OpenXPKI | EST enrollment server + admin UI | OpenXPKI + MariaDB | 4212 (web), 4213 (EST) |
| ACME agent | Server certificate automation | PowerShell 7+ | n/a |
| EST agent | Client certificate automation | PowerShell 7+ | n/a |
| Target server | TLS workload (NGINX) | NGINX | 4214 (HTTPS), 4215 (HTTP) |
| Target client | mTLS validation container | Alpine Linux | n/a |
| Fluentd | Log collection | Fluentd | 4217 |
| Loki | Log storage | Grafana Loki | 4218 |
| Grafana | Dashboarding | Grafana | 4219 |

`ARCHITECTURE.md` contains detailed data flows, sequencing, and security reasoning.

---

## 6. Port Mappings

| Port | Service | Protocol | Purpose | External Access |
|------|---------|----------|---------|-----------------|
| 4210 | step-ca | HTTPS | CA API and health checks | Yes (localhost) |
| 4211 | step-ca CRL | HTTP | CRL distribution | Yes (localhost) |
| 4212 | OpenXPKI Web | HTTP | PKI administration UI | Yes (localhost) |
| 4213 | OpenXPKI EST | HTTPS | EST enrollment endpoint | Internal |
| 4214 | Target server | HTTPS | NGINX with ACME-issued cert | Yes (localhost) |
| 4215 | Target server | HTTP | ACME HTTP-01 challenge host | Internal |
| 4216 | Web UI | HTTP | Reserved for future React UI | Reserved |
| 4217 | Fluentd | TCP | Log ingestion | Internal |
| 4218 | Loki | HTTP | Log storage API | Internal |
| 4219 | Grafana | HTTP | Observability dashboards | Yes (localhost) |

The sequential 421x range keeps firewall rules predictable and minimizes conflicts with standard developer ports.

---

## 7. Installation and Setup

### Prerequisites

- Docker 20.10+ and Docker Compose v2.
- step CLI 0.24+.
- Bash (Linux/macOS) or PowerShell 7+ (Windows).
- At least 4 GiB of free RAM for Docker workloads.
- Optional: curl for manual endpoint checks.

Validate tooling:

```bash
docker --version
docker compose version
step version
pwsh --version    # optional
```

### Installing step CLI

- **macOS**: `brew install step`
- **Linux**:
  ```bash
  wget https://dl.step.sm/gh-release/cli/docs-ca-install/v0.24.4/step_linux_0.24.4_amd64.tar.gz
  tar -xf step_linux_0.24.4_amd64.tar.gz
  sudo cp step_0.24.4/bin/step /usr/local/bin/step
  ```
- **Windows**: `choco install step` or download from the Smallstep documentation site.

### Setup Paths

| Option | Description |
|--------|-------------|
| `./integration-test.sh` | Initializes PKI volumes, starts the stack, validates endpoints, and runs integration tests. |
| `./integration-test.sh --init-only` | Creates PKI material without starting containers (run once per machine). |
| `docker compose up -d` | Starts services after initialization. |
| `./integration-test.sh --validate-only` | Confirms services respond as expected. |
| `./integration-test.sh --quick` | Skips initialization for faster subsequent iterations. |

### Non-Interactive Runs

Set `ECA_CA_PASSWORD` (Linux/macOS) or `$env:ECA_CA_PASSWORD` (PowerShell) before executing the integration script to avoid prompts. This is required for CI and automated environments.

### Verification Checklist

1. `docker compose ps` reports each service as `Up` or `healthy`.
2. Curl checks return expected payloads (see Quick Start).
3. `docker compose logs eca-acme-agent` and `eca-est-agent` show successful enrollment and renewal cycles.

---

## 8. Configuration

### ACME Agent (Server Certificates)

| Variable | Default | Description |
|----------|---------|-------------|
| `ACME_PKI_URL` | `https://pki:9000` | Internal URL for step-ca. |
| `ACME_DOMAIN_NAME` | `target-server` | Certificate subject and SAN. |
| `ACME_CERT_PATH` | `/certs/server/server.crt` | Certificate output path. |
| `ACME_KEY_PATH` | `/certs/server/server.key` | Private key output path. |
| `ACME_RENEWAL_THRESHOLD_PCT` | `33` | Renew when remaining lifetime drops below threshold. |
| `ACME_CHECK_INTERVAL_SEC` | `21600` | Renewal check cadence in seconds. |

### EST Agent (Client Certificates)

| Variable | Default | Description |
|----------|---------|-------------|
| `EST_PKI_URL` | `https://openxpki-web:443` | Internal OpenXPKI endpoint. |
| `EST_DEVICE_NAME` | `client-device-001` | Device identifier used for enrollment. |
| `EST_CERT_PATH` | `/certs/client/cert.pem` | Client certificate output path. |
| `EST_KEY_PATH` | `/certs/client/key.pem` | Client private key output path. |
| `EST_BOOTSTRAP_CERT_PATH` | `/home/step/bootstrap-certs/bootstrap-client.pem` | Bootstrap certificate for first enrollment. |
| `EST_BOOTSTRAP_KEY_PATH` | `/home/step/bootstrap-certs/bootstrap-client.key` | Bootstrap private key. |
| `EST_CRL_ENABLED` | `true` | Enables CRL checking. |
| `EST_CRL_URL` | `http://pki:4211/crl/ca.crl` | CRL distribution point. |

### Certificate Lifetimes

- Root CA: 10 years (configured during `init-volumes.sh`).
- Intermediate CA: 5 years.
- ACME-issued server certificates: 24 hours (default).
- EST-issued client certificates: 1 hour (default).

Override environment variables inside `docker-compose.yml` or via `.env` files to align with your test scenarios. See `CONFIGURATION.md` for a comprehensive reference.

---

## 9. Testing

| Command | Purpose |
|---------|---------|
| `./integration-test.sh` | Full initialization, service startup, validation, and Pester suites. |
| `./integration-test.sh --validate-only` | Endpoint checks only (used after services already running). |
| `./integration-test.sh --test-only` | Executes Pester suites without touching Docker. |
| `./integration-test.sh --quick` | Skips expensive initialization phases. |

The integration workflow confirms:
- ACME enrollment, renewal, and HTTP-01 challenge handling.
- EST bootstrap, issuance, and CRL validation.
- NGINX reload after certificate updates.
- Target client mTLS connectivity.
- Fluentd → Loki → Grafana pipeline readiness.

---

## 10. Observability

### Dashboards

Grafana (port 4219) ships with dashboards that highlight certificate expiration windows, renewal success rates, agent health, HTTP-01 challenge outcomes, and error trends. Login with `admin / eca-admin`.

### LogQL Examples

```
{container_name=~"eca-.*-agent"} |= "renewal"
{container_name=~"eca-.*-agent"} | json | level="error"
{container_name="eca-acme-agent"} |= "HTTP-01 challenge"
```

### Direct Log Access

```bash
docker compose logs -f eca-acme-agent eca-est-agent
docker compose logs -f target-server
docker compose logs | grep -i error
```

Extend dashboards or alerting rules under `grafana/` and `loki/` as required for your environment.

---

## 11. Production Readiness

### Lumia 1.1 Deployment Model

| Area | PoC Implementation | Production Direction |
|------|-------------------|----------------------|
| Platform | Docker containers (Linux) | Windows Server, agents as services |
| Web server | NGINX | IIS via native modules |
| Certificate targets | Demo workloads | Mosquitto, MinIO, Lumia services |
| PKI | step-ca + OpenXPKI | Customer PKI with HSM-backed keys |
| Storage | Filesystem volumes | Windows Certificate Store / secrets management |

### Already Validated

- Standards-compliant ACME and EST interactions.
- Agent retry, error handling, and structured logging.
- Environment-based configuration with sensible defaults.
- Observability pipeline patterns.

### Hardening Roadmap

| Area | Recommendation |
|------|----------------|
| PKI security | Offline root, HSM-backed intermediates, documented ceremonies. |
| Secret management | Vault-backed credentials instead of environment variables. |
| Network segmentation | Dedicated VLANs and firewall policies; enforce mTLS everywhere. |
| High availability | Redundant CA instances, database replication, resilient CRL distribution. |
| Monitoring | Production-grade metrics and alerting (Prometheus, DataDog, Splunk, etc.). |
| Disaster recovery | Automated backups, tested restoration procedures. |
| Compliance | Immutable audit logs and evidence for SOC 2 / ISO 27001 / PCI DSS. |

### Scaling Guidance

- 1–100 agents: PoC architecture suffices.
- 100–1000 agents: Add CA replicas, cache CRLs, tune polling intervals.
- 1000+ agents: Consider distributed CA tiers and OCSP.

---

## 12. Troubleshooting

| Symptom | Suggested Actions |
|---------|------------------|
| Docker daemon unavailable | `sudo systemctl start docker` (Linux) or launch Docker Desktop (macOS/Windows). |
| `step` CLI missing | Install via Homebrew, Chocolatey, or manual download as described above. |
| Volume or file in use | `docker compose down` followed by `./integration-test.sh`. |
| Endpoint validation fails | Inspect `docker compose logs pki`, ensure services are healthy, and rerun validation after a short delay. |
| Renewals not occurring | Tail `docker compose logs -f eca-acme-agent`, confirm expiration time with `openssl x509 -noout -enddate`, verify agent environment variables. |
| Permission errors | Add your user to the Docker group (Linux) and ensure certificate files have 644/600 permissions as appropriate. |

`FAQ.md` provides a deeper catalogue of known issues and remediation steps.

---

## 13. Documentation Map

| Document | Purpose | Audience |
|----------|---------|----------|
| `README.md` | Operational overview and quick start | Everyone |
| `CERTIFICATES_101.md` | PKI fundamentals and Zero Trust context | Anyone new to PKI |
| `ARCHITECTURE.md` | Detailed design and security model | Architects, developers |
| `CONFIGURATION.md` | Environment variables, ports, tuning | Operators, developers |
| `TESTING.md` | Test strategy and execution guide | QA, CI/CD engineers |
| `FAQ.md` | Troubleshooting reference | Everyone |

Suggested reading order:
- **New contributors**: `CERTIFICATES_101.md` → `README.md` → `TESTING.md` → `FAQ.md`
- **Operators**: `README.md` → `CONFIGURATION.md` → `TESTING.md`
- **Architects**: `CERTIFICATES_101.md` → `ARCHITECTURE.md` → `CONFIGURATION.md`
- **Developers**: `README.md` → `ARCHITECTURE.md` → local testing guidance.

---

## 14. Contributing

### Extending the PoC

| Task | Outline |
|------|---------|
| Add a protocol | Create an agent under `agents/<protocol>-agent`, implement enrollment logic, cover with Pester tests, update `docker-compose.yml`, document changes. |
| Add a service target | Define the service in `docker-compose.yml`, update the relevant agent, add integration validation, document configuration. |
| Improve observability | Add Grafana dashboards (`grafana/provisioning/dashboards`), Loki rules, and structured log fields. |
| Enhance agents | Share modules in `agents/common/modules`, enforce PSScriptAnalyzer guidance, expand test coverage. |

### Suggested Workflow

```bash
./scripts/run-tests.sh -u          # Unit tests
docker compose up -d --build       # Start/rebuild services
./integration-test.sh --quick      # Integration tests
docker compose logs -f <service>   # Diagnostics
```

Use `pwsh -Command "Invoke-ScriptAnalyzer -Path agents/ -Recurse"` before opening pull requests and keep documentation synchronized with code changes.

---

## 15. License and Credits

### License

This repository is provided as a Lumia 1.1 proof of concept. © 2025 BCT. All rights reserved.

### Technology Credits

- Smallstep `step-ca` – ACME/EST certificate authority.
- OpenXPKI – EST server and administration tooling.
- Docker and Docker Compose – container runtime and orchestration.
- NGINX – TLS workload for the PoC.
- Fluentd, Grafana Loki, Grafana – log pipeline and visualization.
- PowerShell and Pester – cross-platform automation and test framework.

### Standards Implemented

- RFC 8555 (ACME)
- RFC 7030 (EST)
- RFC 5280 (X.509 PKI and CRL profile)
- RFC 6960 (OCSP)

### Acknowledgments

Thanks to the Smallstep and OpenXPKI communities for high-quality PKI tooling and to the IETF working groups that standardized the underlying protocols.

---

Run `./integration-test.sh` to initialize the environment, then explore Grafana to observe autonomous certificate management end-to-end.
