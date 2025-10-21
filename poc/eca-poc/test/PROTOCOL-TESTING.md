# Protocol Testing Guide - JWK and EST

## Quick Start

### 1. Start Step CA (with both protocols)

```powershell
# Using Docker script
.\start-step-ca-docker.ps1 start

# Or using docker-compose
cd test
docker-compose -f docker-compose.test.yml up -d step-ca-test
```

The Step CA will automatically be configured with:
- **JWK Provisioner**: `admin` (Step CA native)
- **EST Provisioner**: `est-provisioner` (RFC 7030)

### 2. Verify Both Protocols Work

```powershell
# Test JWK endpoint
docker exec step-ca-test step ca health

# Test EST endpoint
curl -k https://localhost:9000/.well-known/est/cacerts

# Or on port 8443
curl -k https://localhost:8443/.well-known/est/cacerts
```

### 3. Test with JWK Protocol (Default)

```powershell
# Start renewal service with JWK
docker-compose -f docker-compose.test.yml up -d cert-renewal-test

# Check status
docker exec cert-renewal-test python main.py status

# View logs
docker logs cert-renewal-test -f
```

### 4. Test with EST Protocol

```powershell
# Start renewal service with EST
docker-compose -f docker-compose.test.yml --profile est-client up -d cert-renewal-est

# Check status
docker exec cert-renewal-est python main.py status

# View logs
docker logs cert-renewal-est -f
```

## Switching Between Protocols

You don't need different Step CA instances! Just change your client configuration:

### Option A: Configuration File

Edit `test/test-config/config.yaml`:

**For JWK:**
```yaml
step_ca:
  protocol: "JWK"
  ca_url: "https://localhost:9000"
  provisioner_name: "admin"
  provisioner_password: "testpassword"
```

**For EST:**
```yaml
step_ca:
  protocol: "EST"
  ca_url: "https://localhost:9000/.well-known/est"
  est_username: "est-client"
  est_password: "est-secret"
```

### Option B: Environment Variables

```powershell
# For JWK
$env:CERT_RENEWAL_STEP_CA__PROTOCOL = "JWK"
$env:CERT_RENEWAL_STEP_CA__CA_URL = "https://localhost:9000"
$env:CERT_RENEWAL_STEP_CA__PROVISIONER_NAME = "admin"
$env:CERT_RENEWAL_STEP_CA__PROVISIONER_PASSWORD = "testpassword"

# For EST
$env:CERT_RENEWAL_STEP_CA__PROTOCOL = "EST"
$env:CERT_RENEWAL_STEP_CA__CA_URL = "https://localhost:9000/.well-known/est"
$env:CERT_RENEWAL_STEP_CA__EST_USERNAME = "est-client"
$env:CERT_RENEWAL_STEP_CA__EST_PASSWORD = "est-secret"
```

## Architecture

```
┌────────────────────────────────────┐
│   Step CA (Single Instance)        │
│   Port: 9000, 8443 (alias)         │
├────────────────────────────────────┤
│  Provisioners:                     │
│    • admin (JWK)                   │
│    • est-provisioner (EST)         │
├────────────────────────────────────┤
│  Endpoints:                        │
│    • /           (JWK)             │
│    • /.well-known/est/ (EST)       │
└──────┬─────────────────────┬───────┘
       │                     │
       ▼                     ▼
┌──────────────┐    ┌──────────────┐
│ JWK Client   │    │ EST Client   │
│ (Step CLI)   │    │ (Pure Python)│
└──────────────┘    └──────────────┘
```

## Configuration Summary

| Aspect | JWK | EST |
|--------|-----|-----|
| **Protocol** | `"JWK"` | `"EST"` |
| **URL** | `https://localhost:9000` | `https://localhost:9000/.well-known/est` |
| **Port Alias** | 9000 | 8443 (maps to 9000) |
| **Provisioner** | `admin` | `est-provisioner` |
| **Auth Settings** | `provisioner_name`, `provisioner_password` | `est_username`, `est_password` |
| **Requires Step CLI** | Yes | No (pure Python) |
| **Standard** | Step CA native | RFC 7030 |

## Testing Scenarios

### Scenario 1: Side-by-Side Testing

Run both clients simultaneously:

```powershell
# Start both
docker-compose -f docker-compose.test.yml up -d step-ca-test cert-renewal-test
docker-compose -f docker-compose.test.yml --profile est-client up -d cert-renewal-est

# Monitor JWK client
docker logs cert-renewal-test -f

# In another terminal, monitor EST client  
docker logs cert-renewal-est -f
```

### Scenario 2: Switch Protocols

Change config and restart:

```powershell
# Edit test/test-config/config.yaml
# Change protocol: "EST"
# Update ca_url, est_username, est_password

# Restart service
docker restart cert-renewal-test
```

### Scenario 3: Manual Operations

```powershell
# JWK: Get token
docker exec step-ca-test step ca token test.local --provisioner admin

# EST: Get CA certs
curl -k https://localhost:9000/.well-known/est/cacerts | base64 -d | openssl pkcs7 -print_certs -text

# Both: Check provisioners
docker exec step-ca-test step ca provisioner list
```

## Troubleshooting

### EST Provisioner Not Found

If EST isn't working, manually add the provisioner:

```powershell
docker exec -it step-ca-test sh -c "
python3 << 'EOF'
import json
with open('/home/step/config/ca.json', 'r') as f:
    config = json.load(f)
config['authority']['provisioners'].append({'type': 'EST', 'name': 'est-provisioner'})
with open('/home/step/config/ca.json', 'w') as f:
    json.dump(config, f, indent=2)
EOF
"

# Restart Step CA
docker restart step-ca-test
```

### Verify Provisioners

```powershell
# Check ca.json
docker exec step-ca-test cat /home/step/config/ca.json | jq '.authority.provisioners'

# Should show both:
# [
#   {"type": "JWK", "name": "admin", ...},
#   {"type": "EST", "name": "est-provisioner"}
# ]
```

### Test EST Endpoint

```powershell
# Should return base64-encoded certificates
curl -k https://localhost:9000/.well-known/est/cacerts

# Decode and view
curl -k https://localhost:9000/.well-known/est/cacerts | python -c "import sys, base64; print(base64.b64decode(sys.stdin.read()).decode('latin1'))"
```

## Docker Compose Profiles

The `docker-compose.test.yml` now supports:

- **Default**: `step-ca-test` + `cert-renewal-test` (JWK)
- **`--profile est-client`**: Adds `cert-renewal-est` (EST)

```powershell
# Start default (JWK only)
docker-compose -f docker-compose.test.yml up -d

# Start with EST client too
docker-compose -f docker-compose.test.yml --profile est-client up -d

# Stop all
docker-compose -f docker-compose.test.yml --profile est-client down
```

## Key Files Modified

| File | Change |
|------|--------|
| `docker-compose.test.yml` | Added EST client profile, port 8443 |
| `init-step-ca.sh` | Auto-adds EST provisioner |
| `start-step-ca-docker.ps1` | Adds EST provisioner automatically |
| `test-config/config.yaml` | Documented both protocols |

## Quick Commands

```powershell
# Start everything
.\start-step-ca-docker.ps1 start

# List provisioners
docker exec step-ca-test step ca provisioner list

# Test JWK
docker exec cert-renewal-test python main.py check

# Test EST
docker exec cert-renewal-est python main.py check

# View Step CA logs
docker logs step-ca-test -f

# Clean reset
docker-compose -f docker-compose.test.yml down -v
.\start-step-ca-docker.ps1 reset
```

## References

- **EST RFC**: https://datatracker.ietf.org/doc/html/rfc7030
- **Step CA Docs**: https://smallstep.com/docs/step-ca/provisioners
- **EST Client Code**: `../src/est_client.py`
- **Protocol Router**: `../src/step_ca_client.py`
