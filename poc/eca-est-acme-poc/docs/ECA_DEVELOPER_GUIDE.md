# ECA Developer Guide

This guide explains how the Edge Certificate Agent (ECA) proof of concept is put together, how it is configured, how the test harness works, and what it takes to extend the platform with a new agent type. Share it with anyone who needs to maintain or evolve the PoC.

---

## 1. System Design

### 1.1 High-Level Topology

```
┌────────────────────────────────────────────────────────────────────┐
│                            Docker Network                           │
│                                                                    │
│  step-ca (pki-data volume) ─────┐                                   │
│                                 │                                   │
│                      ┌──────────▼──────────┐                        │
│                      │  ACME Agent (PS)   │                        │
│                      │  agents/acme/*     │                        │
│                      └──────────┬─────────┘                        │
│                                 │                                   │
│                  ┌──────────────▼──────────────┐                   │
│                  │ Target Server (NGINX)       │                   │
│                  │ /certs/server volume        │                   │
│                  └─────────────────────────────┘                   │
│                                                                    │
│  step-ca + OpenXPKI ───────────┐                                   │
│                                 │                                   │
│                      ┌──────────▼──────────┐                        │
│                      │  EST Agent (PS)    │                        │
│                      │  agents/est/*      │                        │
│                      └──────────┬─────────┘                        │
│                                 │                                   │
│                   ┌─────────────▼─────────────┐                   │
│                   │ Target Client (mTLS)      │                   │
│                   │ /certs/client volume      │                   │
│                   └───────────────────────────┘                   │
│                                                                    │
│  Fluentd → Loki → Grafana  (observability stack)                   │
└────────────────────────────────────────────────────────────────────┘
```

- **PKI**: `step-ca` seeds both ACME and EST CAs. `init-volumes.sh` / `init-volumes.ps1` prepare `pki-data` so the container starts ready to serve both protocols.
- **OpenXPKI**: Provides EST automation. The init-volumes scripts provision the configuration volume and database once.
- **Agents**: PowerShell services that run inside containers. They share code under `agents/common/` for config parsing, logging, crypto, CRL validation, etc.
- **Targets**: `target-server` (NGINX) models an edge service relying on server certificates; `target-client` models a device performing mTLS using EST-issued credentials.
- **Observability**: Fluentd collects container logs, Loki stores them, Grafana visualises them. Dashboards are pre-provisioned for demo readiness.

### 1.2 Agent Lifecycle

Both agents follow the same control loop implemented in `agents/common/ConfigManager.psm1` + agent-specific orchestration:

1. Load defaults from `/agent/config.yaml`.
2. Apply environment overrides (prefixed first, then legacy fallbacks).
3. Validate against `config/agent_config_schema.json`.
4. Build protocol-specific clients (`agents/acme/AcmeClient.psm1`, `agents/est/EstClient.psm1`).
5. Check current certificate/key pair and decide whether to enroll/renew.
6. Write results atomically to the shared volume and emit structured logs.
7. Sleep for `check_interval_sec` and repeat.

The ACME agent additionally performs HTTP-01 challenge handling and triggers NGINX reloads; the EST agent coordinates bootstrap-token enrollment and mTLS re-enrollment.

---

## 2. Configuration Model

Configuration lives in layered sources (lowest precedence first):

1. `/agent/config.yaml` baked into the container image.
2. Overrides from mounted config files (optional).
3. Environment variables (prefix-aware).

### 2.1 Schema

- Defined in `config/agent_config_schema.json`.
- Validated on startup; invalid config aborts the agent with actionable errors.
- Key fields:
  - `pki_url`, `cert_path`, `key_path` – mandatory for both agents.
  - `domain_name` (ACME), `device_name` (EST), `bootstrap_token` (EST initial enrollments).
  - `renewal_threshold_pct`, `check_interval_sec`, `log_level`, `metrics_enabled`.
  - `agent_env_prefix`/`agent_name` (for env namespace) — usually set via environment variables, not YAML.

### 2.2 Environment Overrides & Prefixing

The override logic is central to running multiple agents on one host and is handled by `ConfigManager.psm1`.

- Set `AGENT_ENV_PREFIX=MY_AGENT_` to scope overrides. Every config key can then be overridden via `MY_AGENT_<UPPER_SNAKE_CASE>`.
- Alternatively, set `AGENT_NAME=my_agent`; the prefix becomes `my_agent_`.
- Prefixed value wins. If missing, the agent falls back to the unprefixed variant (legacy compatibility).
- Startup logs enumerate which overrides were applied (search for `"source": "env"` entries in the JSON logs).

**Example (ACME agent):**

```bash
export AGENT_ENV_PREFIX=EDGE_WEB_
export EDGE_WEB_PKI_URL="https://pki:9000"
export EDGE_WEB_DOMAIN_NAME="web.edge.local"
export EDGE_WEB_RENEWAL_THRESHOLD_PCT=70
```

**Example (EST agent):**

```bash
export AGENT_ENV_PREFIX=EDGE_DEVICE_
export EDGE_DEVICE_PKI_URL="https://pki:9000"
export EDGE_DEVICE_DEVICE_NAME="client-device-001"
export EDGE_DEVICE_BOOTSTRAP_TOKEN="$(cat /secrets/bootstrap.token)"
```

### 2.3 Updating the Schema

When you introduce a new setting:

1. Add it to the schema with a description, examples, and defaults.
2. Extend `agents/common/ConfigManager.psm1` to map the new field into runtime settings.
3. Document it in `docs/OBSERVABILITY_WORKFLOW.md` or other relevant guides if it impacts operations.
4. Add tests covering both default and override behaviour.

---

## 3. Testing Strategy

All tests run via Pester (PowerShell) with helper scripts for both Bash and PowerShell environments.

- **Unit Tests** (`tests/unit/*`):
  - Validate protocol clients, config manager, CRL validator, logging, etc.
  - Run with `./scripts/run-tests.sh -u` or `.\scripts\run-tests.ps1 -UnitOnly`.
- **Integration Tests** (`tests/integration/*`):
  - Require PKI stack services.
  - Run with `./scripts/run-tests.sh --auto-start-integration` or `.\scripts\run-tests.ps1 -AutoStartIntegration`.
- **Docker Harness**:
  - `./scripts/run-tests-docker.sh` mirrors the CI pipeline (no local PowerShell needed).
- **CI Workflow**:
  - `.github/workflows/test.yml` executes both suites on push/pull-request.
- **Logging Verification**:
  - `./scripts/verify-logging.sh` validates Fluentd → Loki → Grafana connectivity and dashboards.

Every test run emits coverage to `tests/coverage.xml`. Unit tests complete in ~30s, integration in ~2 minutes when infrastructure is already running.

---

## 4. Extending the Platform: Adding a New Agent

Use this checklist to introduce a new agent type (e.g., SCEP, proprietary API, etc.).

1. **Bootstrap the module**
   - Create `agents/<new-agent>/` with:
     - `agent.ps1` entry point (copy one of the existing agents as starter).
     - Protocol-specific module(s) (e.g., `NewAgentClient.psm1`).
     - `Dockerfile` and `config.yaml`.
   - Reference `agents/common/*` for shared utilities (logging, files, crypto).

2. **Configuration**
   - Update `config/agent_config_schema.json` with new fields.
   - Decide on required vs optional settings. Provide defaults where sensible.
   - Document overrides in this guide and in `README.md` under *Agent Configuration Overrides*.

3. **Environment Prefix**
   - Ensure the Docker compose service sets `AGENT_ENV_PREFIX` (e.g., `NEWAGENT_`).
   - If the agent will be hosted as a Windows Service, document the prefix in `docs/WINDOWS_DEPLOYMENT.md`.

4. **Docker Compose**
   - Add a new service definition reusing the existing volume layout or introducing new ones as needed.
   - Wire dependencies (PKI, targets) and logging driver configuration.

5. **Testing**
   - Create `tests/unit/<NewAgent>.Tests.ps1` covering config parsing, protocol flows, and failure cases.
   - If the agent interacts with external services, add integration tests using dockerised fixtures.
   - Update `scripts/run-tests.sh` if additional prerequisites are needed.

6. **Documentation**
   - Update `README.md` and `docs/` references (architecture diagram, quickstarts).
   - Capture operational notes (how to force renewals, how to simulate failures).

7. **Observability**
   - Emit structured logs compatible with Fluentd/Loki (use `Logger.psm1`).
   - Extend Grafana dashboards if new metrics/log streams are introduced.

Following this process keeps the codebase schema-valid, testable, and demo-ready.

---

## 5. Observability & Grafana Access

1. Start the observability stack and populate sample data:

   ```bash
   ./scripts/observability.sh demo
   # or on Windows
   .\scripts\observability.ps1 demo
   ```

   The script starts Fluentd, Loki, Grafana, restarts agents, and runs `verify-logging` to ensure data is flowing.

2. Log in to Grafana:
   - URL: `http://localhost:3000`
   - Username: `admin`
   - Password: `eca-admin` (change it via the UI if you expose the stack beyond local demos).

3. Navigate to **Dashboards → ECA PoC** and explore:
   - **ECA - Certificate Lifecycle**
   - **ECA - Operations**
   - **ECA - Logs Explorer**
   - **ECA - CRL Monitoring**

4. Troubleshooting:
   - Re-run `./scripts/observability.sh verify -v` for rich diagnostics.
   - Inspect container logs with `docker compose logs loki` etc.
   - See `docs/OBSERVABILITY_WORKFLOW.md` for in-depth guidance.

---

## 6. Reference Materials

- `README.md` — Quick start, configuration snippets, observability overview.
- `QUICKSTART.md` — Hands-on setup walkthrough.
- `docs/ARCHITECTURE.md` — Detailed architecture notes and diagrams.
- `docs/OBSERVABILITY_WORKFLOW.md` — Operations guide for logging stack.
- `docs/WINDOWS_DEPLOYMENT.md` — Service installation and prefix guidance on Windows.
- `config/agent_config_schema.json` — Authoritative config reference.
- `tests/` — Unit/integration suites (great examples for new tests).

Use this guide as the canonical orientation document for the PoC; keep it updated as new capabilities land.
