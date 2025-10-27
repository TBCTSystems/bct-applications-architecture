# ECA Observability Workflow Guide

**Last Updated:** 2025-10-26
**Status:** ✅ Production Ready

---

## Overview

The ECA PoC includes a comprehensive observability stack (Fluentd → Loki → Grafana) that provides real-time monitoring, log aggregation, and visual dashboards for certificate lifecycle management. This guide documents the complete workflow from setup to daily operations.

---

## Quick Start

### One-Command Demo

```bash
# Linux/macOS/WSL
./scripts/observability.sh demo

# Windows PowerShell
.\scripts\observability.ps1 demo
```

This command:
1. Starts Fluentd, Loki, Grafana + ECA agents
2. Waits for all services to be healthy
3. Runs verification tests (14 checks)
4. Generates sample certificate events
5. Provides Grafana access URL

**Access Grafana:** http://localhost:3000
**Credentials:** `admin` / `eca-admin`

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  ECA Agents (PowerShell)                 │
│         ACME Agent              EST Agent                │
│              │                      │                    │
│              ▼                      ▼                    │
│         Structured JSON Logs (stdout)                    │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│                   FluentD (Port 24224)                   │
│   • Collects logs from Docker containers                │
│   • Parses JSON structure                               │
│   • Enriches with container metadata                    │
│   • Forwards to Loki                                    │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│                    Loki (Port 3100)                      │
│   • Stores logs with labels (agent_type, severity)      │
│   • Provides LogQL query interface                      │
│   • Retention: 720h (30 days)                           │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│                  Grafana (Port 3000)                     │
│   • 3 pre-configured dashboards                         │
│   • Real-time log streaming                             │
│   • Certificate lifecycle visualization                 │
└─────────────────────────────────────────────────────────┘
```

---

## Step-by-Step Workflow

### 1. Start the Observability Stack

#### Option A: Core Services Only (Fluentd, Loki, Grafana)

```bash
./scripts/observability.sh up
```

#### Option B: Full Stack with Agents

```bash
./scripts/observability.sh up --with-agents
```

**What Happens:**
- Docker Compose starts the selected services
- Health checks run automatically (120s timeout)
- Fluentd binds to port 24224
- Loki starts with BoltDB storage
- Grafana provisions datasources and dashboards

**Expected Output:**
```
Waiting for fluentd to report running...
  fluentd ready (running healthy)
Waiting for loki to report running...
  loki ready (running)
Waiting for grafana to report running...
  grafana ready (running healthy)
```

---

### 2. Verify Log Flow

```bash
# Linux/macOS/WSL
./scripts/verify-logging.sh

# With verbose output
./scripts/verify-logging.sh --verbose

# Windows PowerShell
.\scripts\verify-logging.ps1

# With verbose output
.\scripts\verify-logging.ps1 -Verbose
```

**Verification Checklist (14 Tests):**
1. ✅ Docker Compose is available
2. ✅ FluentD container is running
3. ✅ FluentD is healthy
4. ✅ Loki container is running
5. ✅ Loki API is responding (port 3100)
6. ✅ Loki has received logs
7. ✅ Grafana container is running
8. ✅ Grafana is healthy
9. ✅ Grafana API is responding (port 3000)
10. ✅ Loki datasource is configured
11. ✅ Certificate Lifecycle dashboard exists
12. ✅ Operations dashboard exists
13. ✅ Logs Explorer dashboard exists
14. ✅ End-to-end log flow verified

**Expected Result:**
```
✓ All tests passed! (14/14)
```

---

### 3. Access Dashboards

Open your browser to **http://localhost:3000**

#### Default Credentials
- **Username:** `admin`
- **Password:** `eca-admin`

#### Available Dashboards

**1. ECA - Certificate Lifecycle** (`/d/eca-cert-lifecycle`)
- ACME Certificate Days Remaining (gauge)
- EST Certificate Days Remaining (gauge)
- ACME Agent Heartbeat (seconds since last log)
- EST Agent Heartbeat (seconds since last log)
- Certificate Lifetime Elapsed % (time series)
- Certificate Operations Log Stream
- Certificate Status Table

**2. ECA - Operations** (`/d/eca-operations`)
- Log Severity Distribution (pie chart)
- Log Rate by Agent (time series)
- Log Volume Over Time by Severity (stacked bars)
- Error Logs Stream
- ACME Error Count (last 1h)
- EST Error Count (last 1h)

**3. ECA - Logs Explorer** (`/d/eca-logs-explorer`)
- Interactive log search with filters:
  - Agent Type (ACME, EST, other)
  - Severity (DEBUG, INFO, WARN, ERROR)
  - Free-text search
- Full log details on expansion

---

### 4. Monitor Certificate Events

The agents log structured events that appear in real-time:

#### Certificate Check Events
```json
{
  "timestamp": "2025-10-26T20:45:23Z",
  "severity": "INFO",
  "message": "Certificate check completed",
  "context": {
    "days_remaining": 0.15,
    "lifetime_elapsed_pct": 98.5,
    "cert_path": "/certs/server/server.crt"
  }
}
```

#### Renewal Events
```json
{
  "timestamp": "2025-10-26T20:46:15Z",
  "severity": "INFO",
  "message": "Certificate renewal initiated",
  "context": {
    "reason": "threshold_reached",
    "threshold_pct": 75
  }
}
```

#### Error Events
```json
{
  "timestamp": "2025-10-26T20:47:00Z",
  "severity": "ERROR",
  "message": "Certificate renewal failed",
  "context": {
    "error": "ACME challenge validation timeout",
    "challenge_type": "http-01"
  }
}
```

---

### 5. Query Logs with LogQL

Access Loki directly at http://localhost:3100/loki/api/v1/query

#### Common Queries

**All ACME logs:**
```logql
{agent_type="acme"}
```

**Recent errors from any agent:**
```logql
{severity="ERROR"} |= "certificate"
```

**Certificate renewals in the last hour:**
```logql
{agent_type=~"acme|est"} |= "renewal" | json
```

**Agent heartbeat check:**
```logql
(time() - timestamp(last_over_time({agent_type="acme"}[5m])))
```

---

### 6. Generate Test Events

#### Trigger ACME Renewal
```bash
docker compose restart eca-acme-agent
docker compose exec eca-acme-agent touch /tmp/force-renew
```

#### Trigger EST Enrollment
```bash
docker compose restart eca-est-agent
```

#### Simulate Error Scenario
```bash
# Stop PKI temporarily to create error logs
docker compose stop pki
sleep 30
docker compose start pki
```

---

## Daily Operations

### Check System Health

```bash
./scripts/observability.sh status
```

**Expected Output:**
```
NAME       IMAGE              STATUS         PORTS
fluentd    eca-fluentd       Up (healthy)   0.0.0.0:24224->24224/tcp
loki       grafana/loki      Up             0.0.0.0:3100->3100/tcp
grafana    grafana/grafana   Up (healthy)   0.0.0.0:3000->3000/tcp
```

### View Live Logs

```bash
./scripts/observability.sh logs
```

### Restart Observability Stack

```bash
./scripts/observability.sh down
./scripts/observability.sh up
```

---

## Troubleshooting

### Issue: FluentD Not Receiving Logs

**Symptoms:**
- Loki has 0 logs
- `verify-logging.sh` fails on test #6

**Solution:**
```bash
# Check FluentD logs
docker compose logs fluentd | tail -50

# Verify FluentD config syntax
docker compose exec fluentd fluentd --dry-run -c /fluentd/etc/fluent.conf

# Restart FluentD
docker compose restart fluentd
```

---

### Issue: Grafana Dashboards Empty

**Symptoms:**
- Dashboards load but show "No data"
- Loki has logs but Grafana shows nothing

**Solution:**
```bash
# Verify Loki datasource
curl http://localhost:3000/api/datasources

# Check Loki is reachable from Grafana
docker compose exec grafana curl http://loki:3100/ready

# Verify time range (default: last 15 minutes)
# Change in Grafana UI: Top-right time picker
```

---

### Issue: Port Conflicts

**Symptoms:**
```
Error: port 3000 is already in use
```

**Solution:**
```bash
# Find conflicting process
lsof -i :3000                    # macOS/Linux
netstat -ano | findstr :3000     # Windows

# Stop conflicting service or change port in docker-compose.yml
```

---

## Key Performance Indicators (KPIs)

### Certificate Health
- **Days Remaining:** >7 days = green, 2-7 = yellow, <2 = red
- **Lifetime Elapsed:** <75% = green, 75-90% = yellow, >90% = red

### Agent Health
- **Heartbeat:** <120s = green, 120-300s = yellow, >300s = red
- **Error Rate:** 0/hour = green, 1-5/hour = yellow, >5/hour = red

### System Health
- **Log Ingestion Rate:** 10-100 logs/min (normal)
- **Loki Storage:** <1GB (typical for 30-day retention)
- **Grafana Response Time:** <500ms (dashboard load)

---

## Best Practices

### 1. Monitor Regularly
- Check dashboards daily during development
- Set up alerts for production (see M2 milestone for alert examples)

### 2. Retain Logs Appropriately
- Development: 7-14 days sufficient
- Production: 30-90 days recommended
- Adjust in `loki/loki-config.yaml` → `retention_period`

### 3. Use Structured Logging
- All agent logs already use JSON format
- Include context fields for filtering
- Redact sensitive data (tokens, passwords)

### 4. Leverage Labels
- `agent_type`: acme, est
- `severity`: DEBUG, INFO, WARN, ERROR
- `container_name`: eca-acme-agent, eca-est-agent

---

## Integration with CI/CD

The observability stack can be used in CI/CD pipelines:

```bash
# Start stack
./scripts/observability.sh up --with-agents

# Run tests
./scripts/run-tests.sh --auto-start-integration

# Verify logs
./scripts/observability.sh verify

# Export logs for analysis
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={agent_type=~"acme|est"}' \
  > test-logs.json

# Cleanup
./scripts/observability.sh down
```

---

## Advanced Configuration

### Custom Log Retention

Edit `loki/loki-config.yaml`:

```yaml
limits_config:
  retention_period: 720h  # Change to desired hours (e.g., 2160h = 90 days)
```

### Custom Grafana Dashboards

1. Create dashboard in Grafana UI
2. Export JSON via "Share" → "Export"
3. Save to `grafana/dashboards/custom-dashboard.json`
4. Restart Grafana to auto-provision

### Add Alert Rules

Edit `loki/loki-config.yaml`:

```yaml
ruler:
  storage:
    type: local
    local:
      directory: /loki/rules
  rule_path: /loki/rules-temp
  alertmanager_url: http://alertmanager:9093
```

---

## Related Documentation

- [OBSERVABILITY_QUICKSTART.md](../OBSERVABILITY_QUICKSTART.md) - Initial setup guide
- [scripts/README.md](../scripts/README.md) - Script reference
- [docs/OBSERVABILITY_FLUENTD.md](OBSERVABILITY_FLUENTD.md) - FluentD configuration details

---

**Questions or Issues?** See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) or review container logs with `docker compose logs <service>`.
