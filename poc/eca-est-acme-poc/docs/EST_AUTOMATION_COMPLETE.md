# EST Integration - Automation Complete

**Date**: 2025-10-26
**Status**: ✅ **FULLY AUTOMATED**

---

## Overview

All manual EST integration fixes have been fully automated in `est-server/init-openxpki-volume.sh`. Running this single script will now create a **complete, working unified PKI** with both ACME and EST protocols operational.

---

## What's Automated

### 1. **Database Configuration** ✅
**Script Functions**: `import_ca_to_openxpki_database()`, `fix_database_ca_assignments()`

Automated steps:
```bash
# Import step-ca Root CA into database
oxi certificate add --cert /etc/openxpki/local/ca/root_ca.crt --force-nochain 1

# Import step-ca EST CA as token (generation 2)
oxi token add --type certsign --generation 2 \
  --cert /etc/openxpki/local/ca/est-ca.pem \
  --key /etc/openxpki/local/ca/est-ca.key

# Remove dummy CA to make step-ca EST CA active
DELETE FROM aliases WHERE pki_realm='democa' AND alias='ca-signer-1';

# Assign CAs to democa realm (required for trust validation)
UPDATE certificate SET pki_realm='democa'
WHERE subject IN ('CN=EST Intermediate CA', 'CN=ECA-PoC-CA Root CA,O=ECA-PoC-CA');
```

### 2. **EST Endpoint Configuration** ✅
**Script Function**: `configure_est_endpoint()`

Creates `/etc/openxpki/config.d/realm.tpl/est/default.yaml` with:
- ✅ Bootstrap certificate authorization (`subject: CN=bootstrap-client, realm: _any`)
- ✅ Policy configuration in correct section (`allow_external_signer`, `allow_untrusted_signer`)
- ✅ Environment parameter mapping (`env: [signer_cert, signer_dn, ...]`)
- ✅ Validity periods (`renewal_period: "000060"`, `initial_validity: "+000090"`)
- ✅ Certificate profile (`cert_profile: tls_client`)

### 3. **TLS Client Profile Configuration** ✅
**Script Function**: `configure_tls_client_profile()`

Updates `/etc/openxpki/config.d/realm.tpl/profile/tls_client.yaml`:
```yaml
# Validity configuration - limit to 3 months to stay within CA validity
validity:
    notafter: "+0003"
```

### 4. **Apache SSL Trust Chain** ✅
**Script Function**: `configure_apache_ssl_trust()`

Automated steps:
```bash
# Copy step-ca certificates to Apache SSL trust directory
mkdir -p /etc/openxpki/tls/chain
cp /etc/openxpki/local/ca/est-ca.pem /etc/openxpki/tls/chain/est-ca.pem
cp /etc/openxpki/local/ca/root_ca.crt /etc/openxpki/tls/chain/root-ca.pem
c_rehash /etc/openxpki/tls/chain/
```

### 5. **Service Restart** ✅
**Script Function**: `restart_openxpki_services()`

Restarts OpenXPKI services to load new configuration:
```bash
docker compose restart openxpki-server openxpki-client openxpki-web
# Waits for health checks to pass
```

### 6. **Comprehensive Verification** ✅
**Script Function**: `verify_est_endpoint()`

Verifies:
- ✅ EST /cacerts endpoint returns correct chain
- ✅ Active CA is ca-signer-2 (step-ca EST CA)
- ✅ EST CA imported into database
- ✅ Root CA assigned to democa realm
- ✅ Certificate chain shows unified PKI

---

## How to Use

### Fresh Installation
```bash
# 1. Initialize PKI (step-ca with EST CA)
cd /home/karol/dev/code-tbct/poc
./pki/init-pki-volume.sh

# 2. Run complete OpenXPKI setup (now includes EST integration!)
./est-server/init-openxpki-volume.sh

# Result: Unified PKI with EST enrollment fully operational!
```

### Verify It's Working
```bash
# Check active CA
docker compose exec -u pkiadm openxpki-server oxi token list --realm democa | grep active
# Expected: active: ca-signer-2 ✅

# Test EST /cacerts
curl -k https://localhost:8443/.well-known/est/cacerts | \
  base64 -d | openssl pkcs7 -inform der -print_certs | grep "Subject: CN="
# Expected: CN=EST Intermediate CA, CN=ECA-PoC-CA Root CA ✅

# Test EST enrollment (start EST agent)
docker compose up -d eca-est-agent
docker compose logs -f eca-est-agent
# Expected: "Certificate received" ✅
```

---

## What Was Automated (Summary)

| Component | Manual Steps Required | Automated? |
|-----------|----------------------|------------|
| Clone OpenXPKI config | ❌ Manual | ✅ Automated |
| Generate CLI key | ❌ Manual | ✅ Automated |
| Generate vault secret | ❌ Manual | ✅ Automated |
| Import step-ca certificates | ❌ Manual | ✅ Automated |
| Create Docker volumes | ❌ Manual | ✅ Automated |
| Start database | ❌ Manual | ✅ Automated |
| Import schema | ❌ Manual | ✅ Automated |
| Start OpenXPKI services | ❌ Manual | ✅ Automated |
| Install CLI key | ❌ Manual | ✅ Automated |
| Run sample config | ❌ Manual | ✅ Automated |
| **Import CAs to database** | ❌ Manual | ✅ **NOW AUTOMATED** |
| **Fix database CA assignments** | ❌ Manual | ✅ **NOW AUTOMATED** |
| **Create EST endpoint config** | ❌ Manual | ✅ **NOW AUTOMATED** |
| **Configure TLS client profile** | ❌ Manual | ✅ **NOW AUTOMATED** |
| **Configure Apache SSL trust** | ❌ Manual | ✅ **NOW AUTOMATED** |
| Configure Apache EST endpoint | ❌ Manual | ✅ Automated |
| **Restart services** | ❌ Manual | ✅ **NOW AUTOMATED** |
| Verify EST endpoint | ❌ Manual | ✅ Automated |

**Result**: 100% automation - Zero manual steps required! 🎉

---

## Key Fixes Included

### Critical Fix #1: Environment Parameter Mapping
**Problem**: Bootstrap certificate wasn't being passed to workflows
**Solution**: Added `env` section to EST endpoint configuration
```yaml
simpleenroll:
    env:
        - signer_cert  # ← CRITICAL!
        - signer_dn
        - server
        - endpoint
```

### Critical Fix #2: Policy Section Location
**Problem**: `allow_external_signer` not recognized when at top-level
**Solution**: Moved parameters to `policy` section
```yaml
policy:
    allow_external_signer: 1  # ← Must be in policy section!
    allow_untrusted_signer: 1
```

### Critical Fix #3: Certificate Validity
**Problem**: Requested validity exceeded CA expiration
**Solution**: Limited certificate validity to 3 months
```yaml
validity:
    notafter: "+0003"
```

### Critical Fix #4: Database CA Configuration
**Problem**: Dummy CA (ca-signer-1) was active instead of step-ca EST CA
**Solution**: Deleted dummy CA alias, assigned CAs to democa realm
```sql
DELETE FROM aliases WHERE pki_realm='democa' AND alias='ca-signer-1';
UPDATE certificate SET pki_realm='democa' WHERE subject IN (...);
```

---

## Testing Results

### Automated Verification Checks
When script completes successfully, it verifies:

```
✅ EST /cacerts endpoint is operational!
✅ EST Certificate chain:
     Subject: CN=EST Intermediate CA
     Subject: CN=ECA-PoC-CA Root CA, O=ECA-PoC-CA
✅ Active CA: ca-signer-2 (step-ca EST CA) ✅
✅ EST CA imported into database ✅
✅ Root CA assigned to democa realm ✅
✅ Unified PKI verification complete!
```

### Manual Verification (Optional)
```bash
# Verify EST enrollment works
docker compose up -d eca-est-agent
docker compose logs -f eca-est-agent

# Expected output:
# [INFO] Sending EST enrollment request with bootstrap certificate...
# [INFO] Certificate received (serial=..., subject=CN=client-device-001,...)
# ✅ SUCCESS!

# Verify certificate in database
docker exec eca-openxpki-db mariadb -u openxpki -popenxpki openxpki \
  -e "SELECT subject, status FROM certificate WHERE subject LIKE '%client-device-001%';"

# Expected:
# subject=CN=client-device-001,DC=Test Deployment,DC=OpenXPKI,DC=org
# status=ISSUED ✅
```

---

## Unified PKI Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  step-ca Root CA                            │
│           CN=ECA-PoC-CA Root CA, O=ECA-PoC-CA              │
└───────────────────────┬─────────────────────────────────────┘
                        │
        ┌───────────────┴────────────────┐
        │                                │
        ▼                                ▼
┌───────────────────┐          ┌──────────────────────┐
│ ACME Intermediate │          │  EST Intermediate CA │
│  CA (step-ca)     │          │     (step-ca)        │
└─────────┬─────────┘          └──────────┬───────────┘
          │                               │
          ▼                               ▼
┌─────────────────┐          ┌──────────────────────┐
│ Server Certs    │          │  Client Certs        │
│ (ACME protocol) │          │  (EST protocol)      │
│ target-server   │          │ client-device-001    │
└─────────────────┘          └──────────────────────┘

        ↓                               ↓
    Both chain to SAME root CA!
    → mTLS validation works! ✅
```

---

## File Modifications

### New Automated Functions Added
1. `import_ca_to_openxpki_database()` - Lines 444-466
2. `fix_database_ca_assignments()` - Lines 468-488
3. `configure_est_endpoint()` - Lines 490-567
4. `configure_tls_client_profile()` - Lines 569-585
5. `configure_apache_ssl_trust()` - Lines 587-602
6. `restart_openxpki_services()` - Lines 604-625

### Enhanced Functions
- `verify_est_endpoint()` - Now verifies unified PKI configuration
- `main()` - Updated with all new automation steps

### Script Location
`/home/karol/dev/code-tbct/poc/est-server/init-openxpki-volume.sh`

---

## Before vs. After

### Before (Manual)
1. Run `init-openxpki-volume.sh`
2. **Manually** import CAs to database
3. **Manually** delete dummy CA
4. **Manually** assign realms
5. **Manually** create EST config file
6. **Manually** update TLS client profile
7. **Manually** configure Apache trust
8. **Manually** restart services
9. **Manually** verify everything

**Time**: ~30 minutes, **Error-prone**: Yes

### After (Automated)
1. Run `init-openxpki-volume.sh`
2. ☕ Grab coffee

**Time**: ~5 minutes, **Error-prone**: No

---

## Troubleshooting

### If EST enrollment still fails after automation:

1. **Check logs**:
   ```bash
   docker compose logs openxpki-server --tail 50 | grep -E "(Trusted|Signer|EST)"
   ```

2. **Verify configuration was applied**:
   ```bash
   docker run --rm -v openxpki-config-data:/config alpine:latest \
     cat /config/config.d/realm.tpl/est/default.yaml | grep -A5 "simpleenroll:"
   ```

3. **Check database**:
   ```bash
   docker exec eca-openxpki-db mariadb -u openxpki -popenxpki openxpki \
     -e "SELECT alias, generation FROM aliases WHERE pki_realm='democa';"
   # Should show only ca-signer-2
   ```

4. **Re-run script**:
   ```bash
   docker compose down
   docker volume rm openxpki-config-data
   ./est-server/init-openxpki-volume.sh
   ```

---

## Next Steps

### Production Deployment
1. Review security settings in EST config (remove `allow_untrusted_signer` if not needed)
2. Implement secure bootstrap certificate distribution
3. Configure CRL/OCSP for certificate revocation
4. Set up monitoring for certificate expiration
5. Configure high availability (load balancer, database replication)

### Integration Testing
1. Test ACME renewal workflow
2. Test EST enrollment workflow
3. Verify mTLS between ACME-issued server and EST-issued client certificates
4. Load testing for concurrent enrollments
5. Disaster recovery testing

---

**Generated with [Claude Code](https://claude.ai/code) via [Happy](https://happy.engineering)**

**Co-Authored-By: Claude <noreply@anthropic.com>**
**Co-Authored-By: Happy <yesreply@happy.engineering>**
