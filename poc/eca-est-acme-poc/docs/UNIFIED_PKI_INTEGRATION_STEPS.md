# Unified PKI Integration - Required Steps

## Overview
This document outlines the steps required to integrate OpenXPKI EST server with step-ca to achieve a unified PKI hierarchy where both ACME and EST certificates chain to the same root CA.

## Status
- ✅ **ACME Protocol**: Fully functional with unified PKI
- ⚠️ **EST Protocol**: Endpoint operational, enrollment authorization pending OpenXPKI configuration research

## Manual Steps Required After init-openxpki-volume.sh

### 1. Import step-ca Certificates into OpenXPKI Database
```bash
# Import Root CA
docker compose exec -u pkiadm openxpki-server \
  oxi certificate add --cert /etc/openxpki/local/ca/root_ca.crt --force-nochain 1

# Import EST Intermediate CA as token (generation 2)
docker compose exec -u pkiadm openxpki-server \
  oxi token add --type certsign --generation 2 \
    --cert /etc/openxpki/local/ca/est-ca.pem \
    --key /etc/openxpki/local/ca/est-ca.key
```

### 2. Remove Dummy CA from Database
```bash
# Delete ca-signer-1 to make ca-signer-2 (step-ca EST CA) active
docker exec eca-openxpki-db mariadb -u openxpki -popenxpki openxpki -e \
  "DELETE FROM aliases WHERE pki_realm='democa' AND alias='ca-signer-1';"
```

### 3. Assign CAs to democa Realm
```bash
# Assign EST CA and Root CA to democa realm for trust chain validation
docker exec eca-openxpki-db mariadb -u openxpki -popenxpki openxpki -e \
  "UPDATE certificate SET pki_realm='democa' WHERE subject='CN=EST Intermediate CA' OR subject='CN=ECA-PoC-CA Root CA,O=ECA-PoC-CA';"
```

### 4. Update docker-compose.yml
Add config volume to openxpki-web service:
```yaml
openxpki-web:
  volumes:
    - openxpki-config-data:/etc/openxpki  # ADD THIS LINE
    - openxpki-client-socket:/run/openxpki-clientd
    - openxpki-download:/var/www/download:ro
```

### 5. Configure Apache SSL Trust Chain
```bash
# Copy step-ca certificates to Apache SSL trust directory
docker exec eca-openxpki-web cp /etc/openxpki/local/ca/est-ca.pem /etc/openxpki/tls/chain/est-ca.pem
docker exec eca-openxpki-web cp /etc/openxpki/local/ca/root_ca.crt /etc/openxpki/tls/chain/root-ca.pem
docker exec eca-openxpki-web c_rehash /etc/openxpki/tls/chain/
```

### 6. Enable Apache Site Configuration
```bash
# Link and enable OpenXPKI Apache configuration
docker exec eca-openxpki-web ln -sf /etc/openxpki/contrib/apache2-openxpki-site.conf /etc/openxpki/contrib/apache2-openxpki-site.conf /etc/apache2/sites-enabled/openxpki.conf
docker exec eca-openxpki-web apachectl graceful
```

### 7. Update EST Endpoint Configuration
Create `/etc/openxpki/config.d/realm.tpl/est/default.yaml`:
```yaml
label: EST Default Endpoint (step-ca)

# Allow bootstrap certificates not in database (external signer validation)
allow_external_signer: 1
# Allow untrusted signers (bootstrap certs) - skip chain validation
allow_untrusted_signer: 1

# Trust bootstrap certificates from step-ca EST Intermediate CA
authorized_signer:
    bootstrap:
        # Accept bootstrap-client certificates issued by EST CA
        subject: CN=bootstrap-client
        issuer: CN=EST Intermediate CA

renewal_period: "000060"

policy:
    # Require client certificate (no anonymous enrollment)
    allow_anon_enroll: 0
    # Auto-approve requests with valid bootstrap cert
    allow_man_approv: 0
    approval_points: 0
    # Allow multiple active certs for testing
    max_active_certs: 10
    auto_revoke_existing_certs: 0

profile:
    # Issue TLS client certificates
    cert_profile: tls_client
    cert_subject_style: enroll

eligible:
    initial:
        value: 1
    renewal:
        value: 1
    onbehalf:
       value: 1
```

## Verification

### Check Active CA
```bash
docker compose exec -u pkiadm openxpki-server oxi token list --realm democa
# Should show: active: ca-signer-2
```

### Verify EST Endpoint Returns Correct Chain
```bash
curl -sk https://localhost:8443/.well-known/est/cacerts | \
  base64 -d | openssl pkcs7 -inform der -print_certs -text | \
  grep -E "(Subject:|Issuer:)"

# Expected output:
#   Subject: CN=EST Intermediate CA
#   Issuer: O=ECA-PoC-CA, CN=ECA-PoC-CA Root CA
#   Subject: O=ECA-PoC-CA, CN=ECA-PoC-CA Root CA
```

### Verify ACME Works
```bash
docker compose logs eca-acme-agent --tail 10
# Should show successful certificate renewal
```

### Check Certificate Issuer
```bash
docker run --rm -v server-certs:/certs alpine:latest sh -c \
  'cat /certs/cert.pem' | openssl x509 -noout -issuer

# Expected: issuer=O=ECA-PoC-CA, CN=ECA-PoC-CA Intermediate CA
```

## Known Issues

### EST Enrollment Authorization
**Status**: Under investigation
**Symptom**: `I18N_OPENXPKI_UI_ENROLLMENT_ERROR_SIGNER_NOT_AUTHORIZED`
**Root Cause**: OpenXPKI's `EvaluateSignerTrust` workflow activity cannot validate bootstrap certificate trust chain

**Attempted Fixes**:
- ✅ Added `allow_external_signer: 1` to EST config
- ✅ Added `allow_untrusted_signer: 1` to EST config
- ✅ Assigned EST CA and Root CA to democa realm
- ✅ Added trust certificates to Apache SSL directory
- ❌ Bootstrap certificate trust chain validation still fails

**Next Steps**:
1. Research OpenXPKI's `validate_certificate` API and trust anchor configuration
2. Consider importing bootstrap certificate directly into database
3. Investigate if additional trust anchor configuration is needed in system/crypto.yaml
4. Review OpenXPKI community forums/documentation for external CA integration examples

## Production Considerations

1. **Security**: Replace `allow_untrusted_signer` with proper trust anchor configuration
2. **Bootstrap Certificates**: Implement secure distribution mechanism (not filesystem)
3. **Certificate Revocation**: Configure CRL/OCSP for both ACME and EST
4. **Monitoring**: Add alerts for certificate expiration and enrollment failures
5. **High Availability**: Load balance OpenXPKI web servers, replicate database

## References

- OpenXPKI Configuration: https://openxpki.readthedocs.io/
- EST RFC 7030: https://datatracker.ietf.org/doc/html/rfc7030
- step-ca Documentation: https://smallstep.com/docs/step-ca

---

**Generated with [Claude Code](https://claude.ai/code) via [Happy](https://happy.engineering)**

**Co-Authored-By: Claude <noreply@anthropic.com>**
**Co-Authored-By: Happy <yesreply@happy.engineering>**
