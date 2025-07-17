# Certificate Directory

This directory contains all certificates used by the Enterprise Certificate Management PoC.

## Certificate Files

### Root CA Certificate
- `root_ca.crt` - Root certificate from step-ca (downloaded automatically)

### Service Certificates
- `mosquitto.crt` - MQTT broker server certificate
- `mosquitto.key` - MQTT broker private key
- `lumia-app.crt` - Lumia application client certificate
- `lumia-app.key` - Lumia application private key

### Device Certificates
- `REVEOS-SIM-001.crt` - Device simulator certificate
- `REVEOS-SIM-001.key` - Device simulator private key

## Certificate Lifecycle

1. **Initial Setup**: Certificates are generated during system initialization
2. **Validation**: All certificates are validated against the root CA
3. **Renewal**: Certificates are automatically renewed before expiry
4. **Revocation**: Certificates can be revoked through step-ca

## Security Notes

- Private keys (*.key) have restricted permissions (600)
- Certificates are valid for 30 days in demo mode
- All certificates use RSA 2048-bit keys minimum
- Certificates include appropriate Subject Alternative Names (SANs)

## File Permissions

```
certificates/
├── root_ca.crt          (644)
├── mosquitto.crt        (644)
├── mosquitto.key        (600)
├── lumia-app.crt        (644)
├── lumia-app.key        (600)
├── REVEOS-SIM-001.crt   (644)
└── REVEOS-SIM-001.key   (600)
```