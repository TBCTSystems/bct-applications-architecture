# Quick Start Guide - Edge Certificate Agent

## Overview

This guide shows you how to get SSL/TLS certificates from Step CA using **DNS-01 challenge with Cloudflare**. The entire process takes about 10 minutes.

## Prerequisites

- ✅ .NET 8 SDK installed
- ✅ Docker Desktop running
- ✅ Cloudflare account with a domain (see [CLOUDFLARE_SETUP.md](CLOUDFLARE_SETUP.md))
- ✅ Step CA running in Docker

## Step 1: Start Step CA (Docker)

```powershell
# Start Step CA container
docker-compose up -d

# Verify it's running
docker-compose ps

# Check logs for admin password (shown on first run)
docker-compose logs step-ca
```

**Step CA Details:**
- **ACME Endpoint**: https://localca.example.com:9443/acme/acme/directory
- **Ports**: 9443 (API), 8080 (HTTP), 8443 (HTTPS)
- **Admin Password**: Found in logs on first run

## Step 2: Configure Cloudflare (One-Time Setup)

### Get Your Credentials

1. **Zone ID**: 
   - Go to https://dash.cloudflare.com
   - Click on your domain
   - Zone ID is on the right side of Overview page

2. **API Token**:
   - Go to https://dash.cloudflare.com/profile/api-tokens
   - Click "Create Token"
   - Use "Edit zone DNS" template
   - Select your domain
   - Copy the token immediately

### Update Default Settings

Edit `EdgeCertAgent/CertificateAgent.cs` and update the defaults (lines 130-131):

```csharp
public string? CloudflareApiToken { get; set; } = "YOUR_CLOUDFLARE_TOKEN";
public string? CloudflareZoneId { get; set; } = "YOUR_ZONE_ID";
```

Or use command-line arguments (see below).

## Step 3: Trust the Step CA Root Certificate

Run PowerShell as **Administrator**:

```powershell
# Export root certificate from container
docker cp step-ca:/home/step/certs/root_ca.crt ./stepca-root.crt

# Install to user's trusted root store
certutil -addstore -user -f "ROOT" ./stepca-root.crt
```

This allows the agent to connect to Step CA without `--insecure` flag.

## Step 4: Add Hosts Entry

Run PowerShell as **Administrator**:

```powershell
# Add hosts file entry so localca.example.com resolves to localhost
Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "`n127.0.0.1 localca.example.com"
```

## Step 5: Run the Certificate Agent

### Option A: Zero Configuration (Recommended)

If you've updated the default settings in `CertificateAgent.cs`:

```powershell
cd EdgeCertAgent
dotnet run
```

That's it! The agent will:
1. Connect to Step CA at `https://localca.example.com:9443`
2. Request certificate for your configured domain (e.g., `acme.dhygw.org`)
3. Create DNS TXT record in Cloudflare
4. Wait for DNS propagation
5. Step CA validates via DNS
6. Download certificate
7. Clean up DNS record

### Option B: With Command-Line Arguments

```powershell
cd EdgeCertAgent

dotnet run -- `
  --url=https://localca.example.com:9443/acme/acme/directory `
  --email=your@email.com `
  --subject=test.yourdomain.com `
  --cf-token=YOUR_CLOUDFLARE_TOKEN `
  --cf-zone=YOUR_ZONE_ID
```

### Expected Output

```
Edge Certificate Agent - Step CA ACME Client
==============================================

ACME URL: https://localca.example.com:9443/acme/acme/directory
Subject: acme.dhygw.org
Output: ./certs
Renewal threshold: 75%
DNS Provider: Cloudflare

Initialising ACME client...
Account key saved to ./certs\account.pem
Ensuring ACME account exists...
ACME account ready.
Creating certificate order...
Processing authorization for acme.dhygw.org
Creating DNS TXT record: _acme-challenge.acme.dhygw.org = lDynxty3nGz...
[Cloudflare] TXT record created successfully. ID: 9242ce1d05852...
DNS TXT record created successfully.
Waiting for DNS propagation (30 seconds)...
Triggering challenge validation...
Challenge status: Valid
Challenge validated by CA. ✓
[Cloudflare] TXT record deleted successfully.
DNS TXT record deleted.
Finalising order and downloading certificate...
Certificate saved: ./certs\cert.pem
Private key saved: ./certs\key.pem
CA certificate chain saved: ./certs\ca.pem

✓ Certificate agent completed successfully.
```

## Step 6: Verify Certificates

```powershell
# List generated files
Get-ChildItem ./certs

# View certificate details
certutil -dump ./certs/cert.pem

# Check certificate expiration
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2("./certs/cert.pem")
$cert | Format-List Subject, Issuer, NotBefore, NotAfter
```

## Output Files

Generated in `./certs/` directory:

| File | Size | Description |
|------|------|-------------|
| `account.pem` | ~232 bytes | ACME account key (ES256) - reused across requests |
| `cert.pem` | ~1031 bytes | Your SSL certificate in PEM format |
| `cert.pem.der` | ~714 bytes | Certificate in DER binary format |
| `key.pem` | ~1706 bytes | Private key (RSA-2048) in PEM format |
| `ca.pem` | ~623 bytes | Step CA root certificate chain |

## Command-Line Options

All parameters are optional (defaults configured in code):

```bash
--url=<url>              ACME directory URL
                         Default: https://localca.example.com:9443/acme/acme/directory

--subject=<domain>       Domain name for certificate
                         Default: acme.dhygw.org
                         Must be in your Cloudflare zone

--email=<email>          ACME account contact email
                         Default: test@dhygw.org

--threshold=<percent>    Renewal threshold percentage
                         Default: 75 (renew at 75% lifetime)

--out=<folder>           Certificate output directory
                         Default: ./certs

--cf-token=<token>       Cloudflare API token
                         Default: (configured in code)

--cf-zone=<zoneid>       Cloudflare Zone ID
                         Default: (configured in code)

--insecure               Skip TLS certificate validation
                         Not needed if root CA is trusted
```

### Examples

```powershell
# Use defaults (simplest)
dotnet run

# Override domain only
dotnet run -- --subject=api.yourdomain.com

# Full override
dotnet run -- --url=https://step-ca.company.com/acme/directory --subject=device.example.com --email=admin@example.com

# Force renewal (lower threshold)
dotnet run -- --threshold=1
```

## How It Works - DNS-01 Challenge Flow

```
1. Agent → Step CA: "I want a certificate for acme.dhygw.org"
2. Step CA → Agent: "Prove ownership: create DNS TXT record _acme-challenge.acme.dhygw.org with value abc123"
3. Agent → Cloudflare API: "Create TXT record _acme-challenge.acme.dhygw.org = abc123"
4. Agent: Wait 30 seconds for DNS propagation
5. Agent → Step CA: "Ready for validation"
6. Step CA → DNS: "Query _acme-challenge.acme.dhygw.org TXT record"
7. DNS → Step CA: "Value is abc123" ✓
8. Step CA → Agent: "Validation passed, here's your certificate"
9. Agent → Cloudflare API: "Delete the TXT record" (cleanup)
10. Agent: Save cert.pem and key.pem
```

### Why DNS-01?

- ✅ **No port 80 required** - Works behind firewalls and NAT
- ✅ **No public IP needed** - Only DNS must be reachable
- ✅ **Multiple services** - Many services can share same IP
- ✅ **Wildcard support** - Can issue *.domain.com certificates
- ✅ **Air-gapped friendly** - Only needs DNS access

## Renewal Testing

```powershell
# First run creates certificate
dotnet run

# Second run checks expiration (skips if within threshold)
dotnet run
# Output: "Existing certificate still within renewal threshold."

# Force renewal by lowering threshold to 1%
dotnet run -- --threshold=1
# Output: "Certificate renewal required." → issues new certificate
```

## Troubleshooting

### Error: "Cloudflare API error: 401"
**Problem**: Invalid API token  
**Solution**: 
- Generate new token at https://dash.cloudflare.com/profile/api-tokens
- Ensure permission is "Zone → DNS → Edit"
- Update token in code or use `--cf-token=` argument

### Error: "Cloudflare API error: 403"
**Problem**: Token doesn't have permission for this zone  
**Solution**: 
- Recreate token with correct zone selected
- Verify Zone ID matches your domain

### Error: "Challenge status: Invalid"
**Problem**: Step CA couldn't find the DNS TXT record  
**Solution**: 
1. Verify domain is in Cloudflare (check dashboard)
2. Check nameservers point to Cloudflare: `nslookup -type=NS yourdomain.com`
3. Manually verify DNS propagation: `nslookup -type=TXT _acme-challenge.yourdomain.com`
4. Increase propagation delay in code (change 30s to 60s)

### Error: "Connection refused" to Step CA
**Problem**: Step CA container not running  
**Solution**:
```powershell
docker-compose ps
docker-compose up -d
docker-compose logs step-ca
```

### Error: "Subject name not in Cloudflare zone"
**Problem**: Trying to get certificate for domain not managed by Cloudflare  
**Solution**: Use `--subject=subdomain.yourdomain.com` where `yourdomain.com` is in Cloudflare

### Warning: "TLS certificate validation"
**Problem**: Step CA root certificate not trusted  
**Solution**: Run Step 3 above (trust root certificate)  
**Alternative**: Use `--insecure` flag (not recommended for production)

## Clean Up Certificates

To remove all certificates and start fresh:

```powershell
# Delete all certificate files
Remove-Item .\certs\* -Force

# Or delete and recreate folder
Remove-Item .\certs -Recurse -Force
New-Item -ItemType Directory -Path .\certs
```

## Production Deployment

### Scheduled Automatic Renewal

Create a Windows Task Scheduler task:

```powershell
# Create scheduled task (run daily at 2 AM)
$action = New-ScheduledTaskAction -Execute "dotnet.exe" -Argument "run" -WorkingDirectory "C:\Projects\eca-server-poc\EdgeCertAgent"
$trigger = New-ScheduledTaskTrigger -Daily -At 2am
Register-ScheduledTask -TaskName "EdgeCertAgent-Renewal" -Action $action -Trigger $trigger -Description "Daily certificate renewal check"
```

### Windows Service

Convert to a Windows Service using .NET Worker Service template or use NSSM (Non-Sucking Service Manager):

```powershell
# Download NSSM from nssm.cc
nssm install EdgeCertAgent "C:\Program Files\dotnet\dotnet.exe" "run"
nssm set EdgeCertAgent AppDirectory "C:\Projects\eca-server-poc\EdgeCertAgent"
nssm start EdgeCertAgent
```

### Multiple Domains

Run multiple times with different subjects:

```powershell
dotnet run -- --subject=api.example.com --out=./certs/api
dotnet run -- --subject=web.example.com --out=./certs/web
dotnet run -- --subject=admin.example.com --out=./certs/admin
```

### Monitoring & Alerts

Add monitoring to check certificate expiration:

```powershell
# Check certificate expiration
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2("./certs/cert.pem")
$daysRemaining = ($cert.NotAfter - (Get-Date)).Days

if ($daysRemaining -lt 7) {
    Write-Warning "Certificate expires in $daysRemaining days!"
    # Send alert (email, webhook, etc.)
}
```

## Next Steps

1. **Review Certificates**: Check `./certs/` folder for all generated files
2. **Deploy Certificates**: Copy to your application's SSL/TLS configuration
3. **Configure Renewal**: Set up scheduled task or Windows Service
4. **Add Monitoring**: Alert on certificate expiration or renewal failures
5. **Scale Up**: Request certificates for additional domains/services

## Additional Resources

- **Cloudflare Setup**: See [CLOUDFLARE_SETUP.md](CLOUDFLARE_SETUP.md) for detailed DNS provider configuration
- **Project Summary**: See [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md) for architecture and technical details
- **Step CA Docs**: https://smallstep.com/docs/step-ca/

## Summary

✅ **Zero-touch operation** - Just run `dotnet run`  
✅ **DNS-01 validation** - No port 80 required  
✅ **Cloudflare integration** - Free DNS API  
✅ **Automatic renewal** - Threshold-based  
✅ **Production-ready** - Tested with real domains  

**Cost**: $0/month (only ~$10/year for domain registration)

---

**Need Help?**  
- Check [Troubleshooting](#troubleshooting) section above
- Review [CLOUDFLARE_SETUP.md](CLOUDFLARE_SETUP.md) for DNS provider setup
- Check Step CA logs: `docker-compose logs step-ca`


