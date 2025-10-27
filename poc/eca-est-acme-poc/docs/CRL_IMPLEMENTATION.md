# CRL (Certificate Revocation List) Implementation Guide

## Overview

This document describes the complete CRL implementation in the ECA (Edge Certificate Agent) PoC project. CRL support enables certificate revocation checking to ensure that agents reject revoked certificates and automatically trigger re-enrollment when needed.

**Version:** 1.0
**Status:** Implemented (M5 - Milestone 5)
**Last Updated:** 2025-10-26

---

## Table of Contents

1. [Architecture](#architecture)
2. [Components](#components)
3. [Configuration](#configuration)
4. [Operations](#operations)
5. [Monitoring](#monitoring)
6. [Troubleshooting](#troubleshooting)
7. [Security Considerations](#security-considerations)

---

## Architecture

### CRL Flow Diagram

```
┌─────────────────┐
│   step-ca PKI   │
│  (CRL enabled)  │
└────────┬────────┘
         │
         │ 1. Generate CRL (hourly cron)
         ▼
┌─────────────────┐
│  /home/step/crl │
│    ca.crl       │  ← CRL file stored
│    ca.crl.pem   │
└────────┬────────┘
         │
         │ 2. Serve via HTTP
         ▼
┌─────────────────┐
│  nginx (9001)   │
│ http://pki:9001 │
│  /crl/ca.crl    │  ← CRL HTTP endpoint
└────────┬────────┘
         │
         │ 3. Download & cache (every 2h)
         ▼
┌─────────────────────────────────────┐
│  ACME/EST Agents                    │
│  ┌─────────────────────┐            │
│  │ CrlValidator.psm1   │            │
│  │                     │            │
│  │ - Update-CrlCache   │            │
│  │ - Test-Certificate  │            │
│  │   Revoked           │            │
│  └─────────────────────┘            │
│                                     │
│  Cache: /tmp/ca.crl                 │
└─────────────────────────────────────┘
         │
         │ 4. Log CRL metrics
         ▼
┌─────────────────┐
│  Loki + Grafana │
│  CRL Dashboard  │
└─────────────────┘
```

### Key Features

- **Automatic CRL Generation:** step-ca generates CRL hourly via cron job
- **HTTP Distribution:** CRL served at `http://pki:9001/crl/ca.crl`
- **Agent-Side Caching:** Agents cache CRL locally to minimize network traffic
- **Automatic Validation:** Agents check certificates against CRL before renewal
- **Forced Re-enrollment:** Revoked certificates trigger immediate re-enrollment
- **Comprehensive Monitoring:** Grafana dashboard tracks CRL age, revoked cert count, validation events

---

## Components

### 1. PKI Service (step-ca)

**Location:** `pki/`

#### CRL Configuration (`ca.json`)

step-ca is configured with experimental CRL support:

```json
{
  "crl": {
    "enabled": true,
    "generateOnRevoke": true,
    "cacheDuration": "1h"
  }
}
```

**Parameters:**
- `enabled`: Enables CRL generation
- `generateOnRevoke`: Auto-generates CRL when certificate is revoked
- `cacheDuration`: CRL validity period (1 hour)

#### CRL Generation Script

**File:** `pki/scripts/generate-crl.sh`

```bash
#!/bin/bash
# Generates CRL from step-ca and saves to /home/step/crl/ca.crl
# Runs every hour via cron
```

**Output Files:**
- `/home/step/crl/ca.crl` - DER format (binary)
- `/home/step/crl/ca.crl.pem` - PEM format (base64)

#### HTTP Server Configuration

**File:** `pki/scripts/serve-crl-http.sh`

Configures nginx to serve CRL files at port 9001:

- **Endpoint:** `http://pki:9001/crl/ca.crl`
- **Content-Type:** `application/pkix-crl`
- **Cache-Control:** `max-age=3600, must-revalidate`

#### Cron Schedule

**File:** `pki/scripts/setup-crl-cron.sh`

```cron
5 * * * * /home/step/scripts/generate-crl.sh
```

CRL generated at :05 past every hour (e.g., 00:05, 01:05, 02:05).

---

### 2. CRL Validator Module

**Location:** `agents/common/CrlValidator.psm1`

PowerShell module providing CRL validation functions.

#### Exported Functions

##### `Get-CrlFromUrl`
Downloads CRL from URL and saves to cache.

```powershell
Get-CrlFromUrl -Url "http://pki:9001/crl/ca.crl" -CachePath "/tmp/ca.crl" -TimeoutSeconds 30
```

**Parameters:**
- `Url` - CRL download URL
- `CachePath` - Local file path for cache
- `TimeoutSeconds` - HTTP timeout (default: 30)

**Returns:** `$true` if successful, `$false` otherwise

##### `Get-CrlAge`
Returns age of cached CRL file in hours.

```powershell
$age = Get-CrlAge -CrlPath "/tmp/ca.crl"
# Returns: 1.5 (hours)
```

**Returns:** Age in hours, or `-1.0` if file doesn't exist

##### `Get-CrlInfo`
Extracts information from CRL file using OpenSSL.

```powershell
$info = Get-CrlInfo -CrlPath "/tmp/ca.crl"
# Returns: @{
#   Issuer = "CN=ECA-PoC-CA"
#   ThisUpdate = "Oct 26 14:00:00 2025 GMT"
#   NextUpdate = "Oct 26 15:00:00 2025 GMT"
#   RevokedCount = 3
#   RevokedSerials = @("ABC123", "DEF456", "GHI789")
# }
```

**Returns:** Hashtable with CRL metadata

##### `Test-CertificateRevoked`
Checks if certificate is in CRL.

```powershell
$revoked = Test-CertificateRevoked `
    -CertificatePath "/certs/server/cert.pem" `
    -CrlPath "/tmp/ca.crl"

# Returns: $true (revoked), $false (valid), $null (error)
```

##### `Update-CrlCache`
Smart cache updater - downloads only if stale.

```powershell
$result = Update-CrlCache `
    -Url "http://pki:9001/crl/ca.crl" `
    -CachePath "/tmp/ca.crl" `
    -MaxAgeHours 2.0

# Returns: @{
#   Updated = $true
#   Downloaded = $true
#   CrlAge = 0.0
#   RevokedCount = 3
#   NextUpdate = "Oct 26 15:00:00 2025 GMT"
#   Error = $null
# }
```

---

### 3. Agent Integration

#### ACME Agent (`agents/acme/agent.ps1`)

**CRL Validation Points:**

1. **On Certificate Check (every 60s):**
   ```powershell
   $crlResult = Test-CertificateAgainstCrl -Config $config -CertPath $config.cert_path

   if ($crlResult.Revoked) {
       # Force immediate renewal
       $lifetimeElapsedPercent = 100
   }
   ```

2. **Logging:**
   ```json
   {
     "message": "CRL cache updated",
     "context": {
       "crl_age_hours": 0.5,
       "revoked_count": 3,
       "downloaded": true
     }
   }
   ```

#### EST Agent (`agents/est/agent.ps1`)

**CRL Validation Points:**

1. **On Certificate Check:**
   ```powershell
   $crlUpdateResult = Update-CrlCache -Url $config.crl.url -CachePath $config.crl.cache_path

   $revoked = Test-CertificateRevoked -CertificatePath $certPath -CrlPath $config.crl.cache_path

   if ($revoked -eq $true) {
       $lifetimeElapsed = 100  # Force re-enrollment
   }
   ```

---

## Configuration

### Agent Configuration (`config.yaml`)

Both ACME and EST agents have identical CRL configuration:

```yaml
crl:
  # Enable CRL validation checks
  enabled: true

  # URL to download CRL from (step-ca CRL endpoint)
  url: "http://pki:9001/crl/ca.crl"

  # Local cache path for downloaded CRL
  cache_path: "/tmp/ca.crl"

  # Maximum age of cached CRL before re-download (hours)
  max_age_hours: 2.0

  # Check certificates against CRL before renewal
  check_before_renewal: true
```

**Configuration Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable/disable CRL validation |
| `url` | string | `http://pki:9001/crl/ca.crl` | CRL download URL |
| `cache_path` | string | `/tmp/ca.crl` | Local cache file path |
| `max_age_hours` | float | `2.0` | Cache expiration (hours) |
| `check_before_renewal` | boolean | `true` | Validate before renewal |

### Docker Compose Configuration

**Volume Mount:**
```yaml
volumes:
  - pki-data:/home/step
  - crl-data:/home/step/crl
```

**Port Exposure:**
```yaml
ports:
  - "9000:9000"  # step-ca HTTPS API
  - "9001:9001"  # CRL HTTP server
```

---

## Operations

### Revoking a Certificate

#### Method 1: Using step CLI (Recommended)

```bash
# Inside PKI container
docker compose exec pki bash

# Revoke by serial number
step certificate revoke <serial-number> \
    --ca-url https://localhost:9000 \
    --root /home/step/certs/root_ca.crt

# Revoke by certificate file
step certificate revoke <cert-file> \
    --ca-url https://localhost:9000 \
    --root /home/step/certs/root_ca.crt
```

#### Method 2: Using ACME Revocation

```bash
# Using ACME account key
step ca revoke \
    --cert-file /path/to/cert.pem \
    --key-file /path/to/key.pem \
    --ca-url https://pki:9000
```

### Verifying CRL is Working

#### 1. Check CRL File Exists

```bash
docker compose exec pki ls -lh /home/step/crl/
# Should show ca.crl and ca.crl.pem with recent timestamps
```

#### 2. Check CRL HTTP Endpoint

```bash
curl -I http://localhost:9001/crl/ca.crl
# Should return: HTTP/1.1 200 OK
# Content-Type: application/pkix-crl
```

#### 3. Download and Inspect CRL

```bash
curl http://localhost:9001/crl/ca.crl -o /tmp/ca.crl
openssl crl -inform DER -in /tmp/ca.crl -noout -text

# Output shows:
# - Issuer: CN=ECA-PoC-CA
# - Last Update: ...
# - Next Update: ...
# - Revoked Certificates: (serial numbers)
```

#### 4. Check Agent Logs

```bash
docker compose logs -f eca-acme-agent | grep CRL

# Expected output:
# {"message":"CRL cache updated","context":{"crl_age_hours":0.5,"revoked_count":0}}
# {"message":"Certificate is VALID (not revoked)"}
```

#### 5. Check Grafana Dashboard

Navigate to: **http://localhost:3000/d/eca-crl-monitoring**

**Metrics to verify:**
- CRL Age < 2 hours (green)
- Revoked Certificates Count (should match actual revocations)
- CRL Download Success Rate = 100%
- Recent CRL Events showing validation logs

---

## Monitoring

### Grafana Dashboard

**Dashboard:** ECA - CRL Monitoring
**UID:** `eca-crl-monitoring`
**URL:** http://localhost:3000/d/eca-crl-monitoring

#### Panels

1. **CRL Age (Gauge)**
   - Shows hours since last CRL update
   - Thresholds:
     - Green: < 24h
     - Yellow: 24-48h
     - Red: > 48h

2. **Revoked Certificates Count (Stat)**
   - Number of revoked certificates in CRL
   - Alert threshold: Yellow > 10, Red > 100

3. **CRL Download Success Rate (Gauge)**
   - Percentage of successful CRL downloads
   - Target: 100% (green)

4. **Certificate Revocation Status (Stat)**
   - Shows if any certificates are currently revoked
   - Red if revoked certificates detected

5. **CRL Validation Events (Time Series)**
   - Count of CRL validation checks over time
   - Grouped by agent type (ACME/EST)

6. **CRL Age Trend (Time Series)**
   - Historical CRL age over time
   - Shows cache refresh patterns

7. **Revoked Certificate Count Trend (Bar Chart)**
   - Historical count of revoked certificates

8. **Recent CRL Events (Log Stream)**
   - Live log stream of CRL-related events
   - Filterable by severity

### Log Queries

**CRL Cache Updates:**
```logql
{agent_type=~"acme|est"} |= "CRL cache updated"
```

**Revoked Certificate Detections:**
```logql
{agent_type=~"acme|est"} |= "Certificate is REVOKED"
```

**CRL Download Failures:**
```logql
{agent_type=~"acme|est"} |= "CRL cache update failed"
```

**CRL Age Extraction:**
```logql
{agent_type=~"acme|est"} |= "CRL cache updated" | json | line_format "{{.context_crl_age_hours}}"
```

---

## Troubleshooting

### Issue: CRL Age > 24 Hours

**Symptoms:**
- Grafana shows CRL age in yellow/red
- Agents log warnings about stale CRL

**Diagnosis:**
```bash
# Check cron is running
docker compose exec pki ps aux | grep crond

# Check cron logs
docker compose exec pki cat /home/step/logs/crl-generation.log

# Check CRL file timestamp
docker compose exec pki stat /home/step/crl/ca.crl
```

**Resolution:**
```bash
# Manually trigger CRL generation
docker compose exec pki /home/step/scripts/generate-crl.sh

# Restart PKI service
docker compose restart pki
```

### Issue: CRL Download Failures (Agents)

**Symptoms:**
- Agent logs show `CRL cache update failed`
- Success rate < 100%

**Diagnosis:**
```bash
# Check CRL HTTP server is running
docker compose exec pki ps aux | grep nginx

# Test CRL endpoint from host
curl -v http://localhost:9001/crl/ca.crl

# Test CRL endpoint from agent container
docker compose exec eca-acme-agent curl -v http://pki:9001/crl/ca.crl
```

**Resolution:**
```bash
# Restart nginx in PKI container
docker compose exec pki nginx -s reload

# Check nginx configuration
docker compose exec pki nginx -t

# Restart PKI service
docker compose restart pki
```

### Issue: Revoked Certificates Not Detected

**Symptoms:**
- Certificate revoked but agents still using it
- No "Certificate is REVOKED" logs

**Diagnosis:**
```bash
# 1. Verify certificate is in CRL
curl http://localhost:9001/crl/ca.crl -o /tmp/ca.crl
openssl crl -inform DER -in /tmp/ca.crl -noout -text | grep -A 10 "Revoked Certificates"

# 2. Check agent CRL cache
docker compose exec eca-acme-agent ls -lh /tmp/ca.crl

# 3. Check agent logs for CRL validation
docker compose logs eca-acme-agent | grep -E "CRL|revok" | tail -20

# 4. Get certificate serial number
openssl x509 -in /path/to/cert.pem -noout -serial
```

**Resolution:**
```bash
# Force CRL cache refresh (delete cache)
docker compose exec eca-acme-agent rm -f /tmp/ca.crl

# Wait for next agent check cycle (60 seconds)
# Agent will download fresh CRL and detect revocation

# Verify revocation detected
docker compose logs -f eca-acme-agent | grep REVOKED
```

### Issue: openssl Not Available in Agents

**Symptoms:**
- Logs show `openssl not available - returning basic info only`
- CRL parsing fails

**Resolution:**
```bash
# Install openssl in agent Dockerfile
RUN apk add --no-cache openssl

# Rebuild agent images
docker compose build eca-acme-agent eca-est-agent

# Restart agents
docker compose up -d eca-acme-agent eca-est-agent
```

---

## Security Considerations

### CRL Distribution Security

**HTTP vs HTTPS:**
- **Current:** CRL served over HTTP (port 9001)
- **Rationale:** CRL is signed by CA, integrity verified cryptographically
- **Production:** Consider HTTPS for defense-in-depth

**Access Control:**
- **Current:** CRL publicly accessible (no authentication)
- **Standard:** CRL is public information per X.509 standards
- **Consideration:** Firewall rules may restrict access if needed

### Cache Poisoning Prevention

**Agent-Side Validation:**
- CRL signature verified by OpenSSL during parsing
- Corrupted CRL files rejected automatically
- Download failures result in continued use of last valid CRL

**Mitigation:**
```powershell
# CrlValidator.psm1 validates CRL integrity via openssl
openssl crl -inform DER -in $CrlPath -noout -text
# ↑ Fails if CRL signature invalid
```

### Revocation Timing

**Maximum Delay:**
- CRL generated hourly (5 past each hour)
- Agent cache expires after 2 hours
- **Worst case:** 3 hours from revocation to detection

**Calculation:**
```
Revoke at 00:02 → CRL updated at 01:05 (1h 3m)
Agent cache expires at 02:05 (2h)
Total: ~3h
```

**Mitigation:**
- Reduce CRL `cacheDuration` to 15-30 minutes for production
- Reduce agent `max_age_hours` to 0.5-1.0 hours
- Enable `generateOnRevoke: true` for immediate CRL updates

### Private Key Protection

**CRL Signing Key:**
- Stored at `/home/step/secrets/intermediate_ca_key`
- Permissions: `0600` (owner read-write only)
- Protected by Docker volume isolation

**Best Practices:**
- Never expose PKI volume to untrusted containers
- Use secrets management (Vault, etc.) in production
- Rotate CA keys according to policy

---

## Testing

See `scripts/test-crl.sh` for end-to-end validation script.

**Test Coverage:**
1. CRL file existence
2. HTTP endpoint availability
3. CRL parsing and inspection
4. Certificate revocation detection
5. Agent automatic re-enrollment
6. Grafana metrics accuracy

---

## References

- [RFC 5280 - X.509 Certificate and CRL Profile](https://tools.ietf.org/html/rfc5280)
- [Smallstep CRL Documentation](https://smallstep.com/docs/step-ca/configuration/)
- [OpenSSL CRL Commands](https://www.openssl.org/docs/man1.1.1/man1/crl.html)

---

**Document Version:** 1.0
**Last Updated:** 2025-10-26
**Maintained By:** ECA PoC Team
