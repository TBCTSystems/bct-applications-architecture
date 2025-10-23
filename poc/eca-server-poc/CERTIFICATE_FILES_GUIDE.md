# Certificate Files Usage Guide

The Edge Certificate Agent generates several files in the `./certs/` directory. Here's how to use each file:

## Generated Files

### 1. `cert.pem` - Your Certificate
**Purpose**: The issued X.509 certificate for your domain

**Usage**:
```powershell
# View certificate details
certutil -dump cert.pem

# Use in web servers (IIS, Apache, nginx)
# Use in applications requiring TLS/SSL
```

**Contents**: Single certificate in PEM format
```
-----BEGIN CERTIFICATE-----
[Base64 encoded certificate]
-----END CERTIFICATE-----
```

### 2. `key.pem` - Private Key
**Purpose**: The private key corresponding to your certificate

**⚠️ SECURITY**: Keep this file secure! Never share or expose it.

**Usage**:
```powershell
# Use with cert.pem for TLS configuration
# Required for SSL/TLS handshake
```

**Contents**: RSA-2048 private key in PEM format
```
-----BEGIN RSA PRIVATE KEY-----
[Base64 encoded private key]
-----END RSA PRIVATE KEY-----
```

### 3. `ca.pem` - CA Certificate Chain
**Purpose**: Root CA certificate from Step CA for validation

**Usage**:
```powershell
# Trust the CA (one-time setup)
certutil -addstore -user "ROOT" ca.pem

# Use for certificate chain verification
# Configure in applications that need to verify your certificate
```

**Contents**: Root CA certificate
```
-----BEGIN CERTIFICATE-----
[Base64 encoded CA certificate]
-----END CERTIFICATE-----
```

**Why you need it**: 
- Client applications need this to verify your certificate
- Required for establishing trusted TLS connections
- Install on all systems that will connect to your service

### 4. `account.pem` - ACME Account Key
**Purpose**: Your ACME account credentials with Step CA

**⚠️ SECURITY**: Keep this secure! Reused for all certificate requests.

**Usage**: Automatically used by the agent for authentication with Step CA

**Do NOT**: Modify or delete this file between runs

### 5. `cert.pem.der` - Certificate (DER format)
**Purpose**: Binary DER format of your certificate

**Usage**: Some applications require DER format instead of PEM
```powershell
# Convert back to PEM if needed
certutil -encode cert.pem.der cert-converted.pem
```

## Common Usage Scenarios

### Scenario 1: Configure IIS with Certificate

```powershell
# Import certificate to Windows Certificate Store
$cert = Import-Certificate -FilePath ".\certs\cert.pem" -CertStoreLocation "Cert:\LocalMachine\My"
$key = Get-Content ".\certs\key.pem" -Raw

# Note: IIS typically uses .pfx format. Convert if needed:
# openssl pkcs12 -export -out certificate.pfx -inkey key.pem -in cert.pem -certfile ca.pem
```

### Scenario 2: Configure Application to Trust Your Certificates

On client machines that will connect to your service:

```powershell
# Install the CA certificate as trusted root
certutil -addstore -user "ROOT" ca.pem
```

Now clients can verify certificates issued by your Step CA.

### Scenario 3: Use in .NET Application

```csharp
// Load certificate and private key
var cert = X509Certificate2.CreateFromPemFile("cert.pem", "key.pem");

// Use in HttpClient or Kestrel
var handler = new HttpClientHandler();
handler.ClientCertificates.Add(cert);
var client = new HttpClient(handler);
```

### Scenario 4: Use with Docker Containers

```dockerfile
# Copy certificates to container
COPY certs/cert.pem /app/certs/
COPY certs/key.pem /app/certs/
COPY certs/ca.pem /app/certs/

# Trust the CA in the container
RUN cp /app/certs/ca.pem /usr/local/share/ca-certificates/step-ca.crt && \
    update-ca-certificates
```

### Scenario 5: Bundle for Distribution

Create a full certificate bundle:

```bash
# Create full chain: cert + CA
cat cert.pem ca.pem > fullchain.pem

# Create PFX bundle (password protected)
openssl pkcs12 -export -out certificate.pfx \
  -inkey key.pem \
  -in cert.pem \
  -certfile ca.pem \
  -password pass:YourSecurePassword
```

## File Permissions

**Recommended permissions**:
```powershell
# cert.pem, ca.pem, cert.pem.der - Read-only (644)
icacls .\certs\cert.pem /inheritance:r /grant:r "$env:USERNAME:(R)"

# key.pem, account.pem - Restricted (600)
icacls .\certs\key.pem /inheritance:r /grant:r "$env:USERNAME:(R,W)"
icacls .\certs\account.pem /inheritance:r /grant:r "$env:USERNAME:(R,W)"
```

## Certificate Lifecycle

```
1. Request Certificate
   ├─ Agent creates account.pem (first time)
   └─ Agent generates cert.pem + key.pem + ca.pem

2. Use Certificate
   ├─ Deploy cert.pem + key.pem to your service
   └─ Distribute ca.pem to clients

3. Renew Certificate
   ├─ Agent checks cert.pem expiry
   └─ If threshold reached, requests new cert.pem + key.pem
       (ca.pem and account.pem remain the same)

4. Deploy Updated Certificate
   └─ Replace old cert.pem + key.pem with new ones
```

## Troubleshooting

### Certificate Not Trusted
**Problem**: Browsers/clients show "Certificate not trusted"

**Solution**: Install `ca.pem` as a trusted root certificate on the client system

### Certificate/Key Mismatch
**Problem**: "Private key does not match certificate"

**Solution**: Ensure you're using the `cert.pem` and `key.pem` generated together (same run)

### Certificate Expired
**Problem**: Certificate is expired

**Solution**: 
1. Delete old certificates: `Remove-Item .\certs\cert.* -Force`
2. Run agent again to request new certificate
3. Or force renewal: `dotnet run -- --threshold=0`

## Best Practices

1. **Backup Files**: Keep secure backups of `account.pem` and `key.pem`
2. **Separate Environments**: Use different account keys for dev/staging/production
3. **Rotate Regularly**: Even with auto-renewal, periodically review and rotate certificates
4. **Monitor Expiry**: Set up monitoring alerts for certificate expiration
5. **Test Renewal**: Regularly test renewal process before certificates expire
6. **Access Control**: Restrict file access to only necessary users/services
7. **Distribution**: Automate distribution of renewed certificates to services

## Summary

| File | Purpose | Share? | Backup? |
|------|---------|--------|---------|
| `cert.pem` | Your public certificate | ✅ Yes | ⚠️ Optional |
| `key.pem` | Your private key | ❌ Never | ✅ Yes |
| `ca.pem` | CA root certificate | ✅ Yes | ⚠️ Optional |
| `account.pem` | ACME account credentials | ❌ Never | ✅ Yes |
| `cert.pem.der` | Binary cert format | ✅ Yes | ❌ No |

**Remember**: Only `cert.pem` and `ca.pem` should be distributed to clients. Keep `key.pem` and `account.pem` secure and private!
