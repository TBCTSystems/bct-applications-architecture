# ECA Observability with FluentD + Loki + Grafana

## Overview

This document describes the observability stack for the Edge Certificate Agent (ECA) PoC, providing centralized log aggregation, storage, and visualization using FluentD, Grafana Loki, and Grafana.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  ECA Observability Stack                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ACME Agent → JSON Logs → FluentD → Loki → Grafana         │
│  EST Agent  → JSON Logs → FluentD → Loki → Grafana         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Components

1. **FluentD** (Port 24224)
   - Log collection from Docker containers
   - JSON parsing and enrichment
   - Routing to Loki

2. **Grafana Loki** (Port 3100)
   - Lightweight log storage (no indexing)
   - 30-day retention
   - LogQL query language

3. **Grafana** (Port 3000)
   - Visualization and dashboards
   - Log exploration UI
   - Alert management

## Quick Start

### 1. Start the Observability Stack

```bash
cd poc

# Start all services (including observability stack)
docker compose up -d

# Verify services are running
docker compose ps

# Expected output should show:
# - eca-fluentd (running)
# - eca-loki (running, healthy)
# - eca-grafana (running, healthy)
# - eca-acme-agent (running, with FluentD logging)
# - eca-est-agent (running, with FluentD logging)
```

### 2. Access Grafana

1. Open browser: **http://localhost:3000**
2. Login credentials:
   - Username: `admin`
   - Password: `eca-admin`
3. Navigate to **Dashboards** → **ECA PoC** folder

### 3. View Dashboards

Three pre-configured dashboards are available:

#### Dashboard 1: ECA - Certificate Lifecycle
- Certificate days remaining (gauges for ACME and EST)
- Certificate lifetime elapsed percentage timeline
- Certificate operations log stream
- Certificate status table

#### Dashboard 2: ECA - Operations
- Log severity distribution (pie chart)
- Log rate by agent (time series)
- Log volume over time by severity
- Error logs stream

#### Dashboard 3: ECA - Logs Explorer
- Full log search with filters
- Variables: Agent Type, Severity, Search text
- Live tail mode (auto-refresh every 5 seconds)

## Log Format

### JSON Structure

Agents output structured JSON logs:

```json
{
  "timestamp": "2025-10-26T15:30:45Z",
  "severity": "INFO",
  "message": "Certificate renewal completed successfully",
  "context": {
    "domain": "target-server",
    "lifetime_elapsed_pct": 78.5,
    "days_remaining": 2.3,
    "status": "success",
    "duration_seconds": 12.4
  }
}
```

### Log Severity Levels

- **DEBUG**: Detailed diagnostic information
- **INFO**: General informational messages
- **WARN**: Warning messages (non-critical issues)
- **ERROR**: Error messages (failures requiring attention)

### Key Log Events

#### Certificate Check
```json
{
  "message": "Certificate check: 78% elapsed",
  "context": {
    "cert_path": "/certs/server/cert.pem",
    "lifetime_elapsed_pct": 78.5,
    "days_remaining": 2.3,
    "not_after": "2025-10-29T00:00:00Z"
  }
}
```

#### Renewal Triggered
```json
{
  "message": "Renewal triggered",
  "context": {
    "domain": "target-server",
    "lifetime_elapsed_pct": 80,
    "renewal_threshold_pct": 75
  }
}
```

#### Renewal Completed
```json
{
  "message": "Certificate renewal completed successfully",
  "context": {
    "status": "success",
    "duration_seconds": 12.4
  }
}
```

## LogQL Query Examples

### Basic Queries

```logql
# All logs from ACME agent
{agent_type="acme"}

# All logs from both agents
{agent_type=~"acme|est"}

# Error logs only
{severity="ERROR"}

# Logs containing "renewal"
{agent_type="acme"} |= "renewal"

# Logs NOT containing "check"
{agent_type="acme"} != "check"
```

### Filtering and Parsing

```logql
# Parse JSON and extract fields
{agent_type="acme"} | json

# Filter by context field
{agent_type="acme"} | json | lifetime_elapsed_pct > 75

# Extract specific field
{agent_type="acme"} |= "Certificate check" | json | line_format "{{.context.days_remaining}}"
```

### Aggregations

```logql
# Count logs per agent
sum by (agent_type) (count_over_time({agent_type=~"acme|est"}[5m]))

# Rate of logs per second
rate({agent_type="acme"}[1m])

# Error count in last hour
count_over_time({severity="ERROR"}[1h])
```

### Advanced Queries

```logql
# Extract renewal duration and calculate average
{agent_type="acme"}
  |= "renewal operation completed"
  | json
  | unwrap duration_seconds
  | avg_over_time[5m]

# Find renewal failures
{agent_type=~"acme|est"}
  |= "renewal"
  | json
  | status != "success"

# Certificate expiry warnings (< 2 days)
{agent_type=~"acme|est"}
  |= "Certificate check"
  | json
  | days_remaining < 2
```

## Troubleshooting

### Logs Not Appearing in Grafana

**Check FluentD is receiving logs:**
```bash
# View FluentD logs
docker logs eca-fluentd

# Check FluentD metrics
curl http://localhost:24220/api/plugins.json
```

**Check Loki is receiving data:**
```bash
# Query Loki directly
curl -G http://localhost:3100/loki/api/v1/query --data-urlencode 'query={agent_type="acme"}' | jq

# Check Loki health
curl http://localhost:3100/ready
```

**Verify Docker logging driver:**
```bash
# Inspect ACME agent container
docker inspect eca-acme-agent | grep -A 10 LogConfig

# Expected output should show:
# "Type": "fluentd",
# "Config": {
#   "fluentd-address": "localhost:24224",
#   "tag": "docker.{{.Name}}"
# }
```

### FluentD Connection Errors

If agents fail to start with FluentD connection errors:

```bash
# Start FluentD first
docker compose up -d fluentd

# Wait for FluentD to be ready
docker logs -f eca-fluentd

# Then start agents
docker compose up -d eca-acme-agent eca-est-agent
```

### Grafana Datasource Not Working

```bash
# Check Loki is accessible from Grafana
docker exec eca-grafana wget -O- http://loki:3100/ready

# If failed, check network
docker network inspect eca-poc-network
```

### FluentD Buffer Growing

If `/var/log/fluentd/buffer/` is growing:

```bash
# Check Loki is healthy
docker logs eca-loki

# Check disk space
df -h

# Clear buffer (WARNING: loses buffered logs)
docker exec eca-fluentd rm -rf /var/log/fluentd/buffer/*
docker restart eca-fluentd
```

### High Memory Usage (Loki)

```bash
# Check Loki memory usage
docker stats eca-loki

# Reduce retention if needed (edit loki/loki-config.yml)
# Change retention_period from 720h (30d) to 168h (7d)

# Restart Loki
docker restart eca-loki
```

## Performance Considerations

### Resource Usage

**Typical resource consumption:**

- FluentD: ~50-100MB RAM, minimal CPU
- Loki: ~200-500MB RAM, minimal CPU
- Grafana: ~150-300MB RAM, minimal CPU

**Total overhead:** ~400-900MB RAM for complete observability stack

### Log Volume

**Expected log volume:**

- ACME agent: ~1 log/minute (status checks) + burst during renewals
- EST agent: ~1 log/minute (status checks) + burst during enrollment
- Average: ~50-100 log lines per hour per agent
- Daily volume: ~5-10MB uncompressed

**Retention:**

- 30 days retention = ~150-300MB storage
- Loki compression typically achieves 5-10x compression

### Optimization Tips

1. **Reduce scrape interval** if logs are too frequent:
   ```yaml
   # In docker-compose.yml, increase CHECK_INTERVAL_SEC
   CHECK_INTERVAL_SEC: 300  # Check every 5 minutes instead of 60 seconds
   ```

2. **Adjust Loki retention** for less storage:
   ```yaml
   # In loki/loki-config.yml
   limits_config:
     retention_period: 168h  # 7 days instead of 30
   ```

3. **Disable DEBUG logs** in production:
   ```yaml
   # In agent environment
   LOG_LEVEL: INFO  # Only INFO, WARN, ERROR
   ```

## Testing and Validation

### Test 1: Verify Log Flow

```bash
# Trigger a certificate check by restarting agent
docker restart eca-acme-agent

# Wait 10 seconds, then query Loki
curl -G http://localhost:3100/loki/api/v1/query \
  --data-urlencode 'query={agent_type="acme"} |= "Agent started"' \
  | jq '.data.result[0].values'

# Expected: Log entries with "Agent started" message
```

### Test 2: Verify Dashboard Data

1. Open Grafana: http://localhost:3000
2. Navigate to **ECA - Certificate Lifecycle** dashboard
3. Verify gauges show certificate days remaining
4. Verify timeline shows lifetime elapsed percentage

### Test 3: Search for Specific Log

1. Open **ECA - Logs Explorer** dashboard
2. Set **Severity** filter to `ERROR`
3. Set **Search** to `renewal`
4. Verify error logs are displayed (if any exist)

### Test 4: Generate Test Logs

```bash
# Force renewal to generate logs
docker exec eca-acme-agent touch /tmp/force-renew

# Monitor logs in Grafana
# Open "ECA - Operations" dashboard
# Watch "Error Logs" panel for renewal operation logs
```

## Alerting (Future Enhancement)

Grafana supports alerts based on LogQL queries. Example alert configurations:

### Alert: Certificate Expiring Soon

```yaml
# Alert when certificate has < 2 days remaining
expr: |
  count_over_time({agent_type=~"acme|est"}
    |= "Certificate check"
    | json
    | days_remaining < 2 [5m]) > 0
for: 5m
labels:
  severity: warning
annotations:
  summary: "Certificate expiring in < 2 days"
```

### Alert: High Error Rate

```yaml
# Alert when error rate exceeds 5 errors in 5 minutes
expr: |
  count_over_time({severity="ERROR"}[5m]) > 5
for: 2m
labels:
  severity: critical
annotations:
  summary: "High error rate detected"
```

## Backup and Recovery

### Backup Loki Data

```bash
# Stop Loki
docker stop eca-loki

# Backup Loki volume
docker run --rm \
  -v loki-data:/data \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/loki-backup-$(date +%Y%m%d).tar.gz /data

# Restart Loki
docker start eca-loki
```

### Restore Loki Data

```bash
# Stop Loki
docker stop eca-loki

# Restore from backup
docker run --rm \
  -v loki-data:/data \
  -v $(pwd)/backups:/backup \
  alpine tar xzf /backup/loki-backup-YYYYMMDD.tar.gz -C /

# Restart Loki
docker start eca-loki
```

### Backup Grafana Dashboards

Dashboards are stored in `grafana/dashboards/` directory and version-controlled in Git.

To export a modified dashboard:

```bash
# Export dashboard via API
curl -u admin:eca-admin \
  http://localhost:3000/api/dashboards/uid/eca-cert-lifecycle \
  | jq '.dashboard' > grafana/dashboards/eca-certificate-lifecycle.json
```

## Security Considerations

### Access Control

- Grafana admin password should be changed in production:
  ```yaml
  # In docker-compose.yml
  GF_SECURITY_ADMIN_PASSWORD: <strong-password>
  ```

- Consider enabling authentication for Loki:
  ```yaml
  # In loki/loki-config.yml
  auth_enabled: true
  ```

### Network Exposure

- FluentD port 24224 is exposed on localhost only
- Loki port 3100 is internal (not exposed to host)
- Grafana port 3000 is exposed for web access

### Log Redaction

Ensure sensitive data is never logged:
- Private keys
- Bootstrap tokens
- Passwords

The Logger module does NOT automatically redact sensitive data.

## Appendix

### Service Endpoints

- **Grafana UI**: http://localhost:3000
- **Loki API**: http://localhost:3100 (internal only)
- **FluentD Forward**: tcp://localhost:24224
- **FluentD Metrics**: http://localhost:24220/api/plugins.json

### Useful Commands

```bash
# View real-time logs from FluentD
docker logs -f eca-fluentd

# View real-time logs from Loki
docker logs -f eca-loki

# Restart observability stack
docker restart eca-fluentd eca-loki eca-grafana

# View FluentD buffer size
docker exec eca-fluentd du -sh /var/log/fluentd/buffer

# Query Loki label values
curl http://localhost:3100/loki/api/v1/label/agent_type/values | jq
```

### References

- [FluentD Documentation](https://docs.fluentd.org/)
- [Grafana Loki Documentation](https://grafana.com/docs/loki/latest/)
- [LogQL Query Language](https://grafana.com/docs/loki/latest/logql/)
- [Grafana Dashboards](https://grafana.com/docs/grafana/latest/dashboards/)
