# ECA PoC - Quick Start Guide

**Edge Certificate Agent - Proof of Concept**

This guide will get the complete ECA PoC running on your laptop in under 5 minutes.

---

## Prerequisites

- **Docker Desktop** (or Docker Engine 20.10+)
- **Docker Compose v2**
- **openssl** CLI tool
- **git**
- **Minimum 4GB RAM** available for Docker

### Quick Check

```bash
docker --version          # Should be 20.10+
docker compose version    # Should be v2.x
openssl version
git --version
```

---

## One-Command Setup

### Step 1: Initialize every volume (run once per laptop)

```bash
./init-volumes.sh
```

```powershell
.\init-volumes.ps1
```

**What this does:**
- Runs `step ca init` with the right defaults and saves everything into the `pki-data` Docker volume
- Copies the EST chain (root + issuing certs) into OpenXPKI’s config volume
- Seeds the OpenXPKI database schema and realm configuration
- Leaves both ACME and EST endpoints ready for `docker compose up`

**Tips**
- Linux/macOS/WSL: `ECA_CA_PASSWORD=your-secret ./init-volumes.sh` avoids interactive prompts
- Windows: `$env:ECA_CA_PASSWORD="your-secret"; .\init-volumes.ps1 -Force`
- Re-run only if you intentionally delete the `pki-data` or `openxpki-config-data` volumes

---

### Step 2: Start All Services

```bash
docker compose up -d
```

**What this does:**
- Starts step-ca, OpenXPKI, ACME/EST agents, target server/client, and optional observability components
- Agents immediately begin certificate enrollment/renewal loops

Need to demo observability right away? Run `./scripts/observability.sh demo` (or `.ps1`) after the stack is up to start Fluentd + Loki + Grafana, run the health checks, and print the Grafana URL/credentials.

---

## Verification

### Check Container Status

```bash
docker compose ps
```

**Expected:** All containers showing `healthy` or `Up` status.

---

### Verify EST Endpoint

```bash
curl -k https://localhost:8443/.well-known/est/cacerts | \
  base64 -d | openssl pkcs7 -inform der -print_certs
```

**Expected:** Certificate chain (Root CA + Issuing CA)

---

### View ACME Agent Logs

```bash
docker compose logs -f eca-acme-agent
```

**Expected:** Certificate monitoring and renewal activity

---

### View EST Agent Logs

```bash
docker compose logs -f eca-est-agent
```

**Expected:** Bootstrap certificate authentication and enrollment attempts

---

## Access Points

| Service | URL | Purpose |
|---------|-----|---------|
| **step-ca API** | https://localhost:9000 | PKI/CA administration |
| **OpenXPKI Web UI** | https://localhost:8443 | PKI management interface |
| **EST Endpoint** | https://localhost:8443/.well-known/est/ | EST protocol (RFC 7030) |
| **Target Server** | https://localhost:443 | NGINX with ACME-managed cert |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         Docker Network                       │
│                        eca-poc-network                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐                                           │
│  │   step-ca    │ Root CA + EST Intermediate CA            │
│  │   (PKI)      │                                           │
│  └──────┬───────┘                                           │
│         │                                                    │
│         ├──────────────┬─────────────────┐                 │
│         │              │                 │                  │
│  ┌──────▼─────┐  ┌────▼─────────┐  ┌────▼──────────┐      │
│  │ OpenXPKI   │  │  ACME Agent  │  │   EST Agent   │      │
│  │ EST Server │  │              │  │               │       │
│  └──────┬─────┘  └──────┬───────┘  └───────┬───────┘      │
│         │               │                   │               │
│         │        ┌──────▼───────┐    ┌──────▼──────┐       │
│         │        │ Target Server│    │Target Client│       │
│         │        │   (NGINX)    │    │  (Alpine)   │       │
│         │        └──────────────┘    └─────────────┘       │
│         │                                                    │
│  ┌──────▼────────────────────────────┐                     │
│  │  MariaDB (OpenXPKI Database)      │                     │
│  └────────────────────────────────────┘                     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Features Demonstrated

### 1. **ACME Protocol (Server Certificates)**
- ACME agent monitors server certificate lifecycle
- Automatic renewal at 75% of certificate lifetime
- HTTP-01 challenge validation
- Zero-downtime certificate rotation

### 2. **EST Protocol (Client Certificates)**
- EST agent uses bootstrap certificate for initial enrollment
- Mutual TLS (mTLS) authentication
- Automatic key rotation on renewal
- RFC 7030 compliant

### 3. **PKI Hierarchy**
- Root CA (step-ca)
- EST Intermediate CA (issues client certificates)
- Issuing CA (OpenXPKI demo CA)

---

## Testing Certificate Lifecycle

### Test ACME Renewal (Fast)

Edit `.env` file:
```bash
CERT_LIFETIME_MINUTES=2   # Certificate expires in 2 minutes
RENEWAL_THRESHOLD_PCT=75  # Renew at 75% (1.5 minutes)
CHECK_INTERVAL_SEC=30     # Check every 30 seconds
```

Restart ACME agent:
```bash
docker compose restart eca-acme-agent
docker compose logs -f eca-acme-agent
```

**Expected:** Certificate renewal within ~1.5 minutes

---

### Test EST Enrollment (Fast)

Same process as ACME - edit `.env`, restart EST agent:
```bash
docker compose restart eca-est-agent
docker compose logs -f eca-est-agent
```

**Expected:** Certificate enrollment and renewal automation

---

## Troubleshooting

### Containers Not Starting

```bash
# Check Docker resources
docker system df

# Check logs for specific container
docker compose logs eca-pki
docker compose logs eca-openxpki-db
```

---

### EST Endpoint Returns 404

```bash
# Verify OpenXPKI web server is healthy
docker compose ps eca-openxpki-web

# Check Apache configuration
docker exec eca-openxpki-web apache2ctl -t

# Restart web server
docker compose restart eca-openxpki-web
```

---

### ACME Agent Not Renewing

```bash
# Check PKI health
curl -k https://localhost:9000/health

# View agent logs with DEBUG level
docker compose logs -f eca-acme-agent | grep -E "(INFO|ERROR)"
```

---

### EST Agent Bootstrap Certificate Expired

Bootstrap certificates are valid for **24 hours** by default.

**Regenerate:**
```bash
docker exec eca-pki bash -c '
step certificate create "bootstrap-client" \
    /home/step/bootstrap-certs/bootstrap-client.pem \
    /home/step/bootstrap-certs/bootstrap-client.key \
    --profile leaf \
    --ca /home/step/est-certs/est-ca.pem \
    --ca-key /home/step/est-certs/est-ca.key \
    --not-after 24h \
    --insecure --no-password
'

docker compose restart eca-est-agent
```

---

## Cleanup

### Stop All Services

```bash
docker compose down
```

---

### Remove All Data (Fresh Start)

```bash
# Stop containers
docker compose down

# Remove volumes
docker volume rm pki-data server-certs client-certs challenge \
  openxpki-config-data openxpki-db openxpki-socket \
  openxpki-client-socket openxpki-db-socket openxpki-log \
  openxpki-log-ui openxpki-download

# Remove temp files
rm -rf /tmp/eca-pki-init /tmp/openxpki-config-init
```

Then re-run the setup from Step 1.

---

## What's Next?

### Production Considerations

1. **Replace demo CA** - OpenXPKI currently uses demo PKI
   - Import step-ca EST CA into OpenXPKI realm
   - Configure EST endpoint to use step-ca for signing

2. **Security hardening**
   - Enable TLS client certificate validation
   - Use proper secrets management (not .env files)
   - Implement certificate revocation (CRL/OCSP)

3. **High availability**
   - Load balanced OpenXPKI web servers
   - Database replication
   - Shared storage for certificates

4. **Monitoring & alerting**
   - Certificate expiration monitoring
   - Agent health checks
   - Enrollment success/failure metrics

---

## Resources

- **Documentation:** `docs/` directory
- **Architecture:** `docs/01_Plan_Overview_and_Setup.md`
- **EST Guide:** `docs/EST_IMPLEMENTATION_GUIDE.md`
- **OpenXPKI Status:** `docs/OPENXPKI_INTEGRATION_FINAL_REPORT.md`

---

## Support

For issues or questions:
1. Check `docs/` for detailed documentation
2. Review container logs: `docker compose logs [service-name]`
3. Verify prerequisites are met
4. Try a fresh cleanup and re-setup

---

**Generated with [Claude Code](https://claude.ai/code) via [Happy](https://happy.engineering)**

**Co-Authored-By: Claude <noreply@anthropic.com>**
**Co-Authored-By: Happy <yesreply@happy.engineering>**
