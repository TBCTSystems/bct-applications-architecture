# Edge Certificate Agent - DNS-01 ACME Client

Automated certificate issuance and renewal using **Step CA** (private Certificate Authority) and **Cloudflare DNS** for ACME DNS-01 challenge validation.

## 🎯 What This Does

- 🔐 **Automatically requests SSL/TLS certificates** from your private Step CA
- ☁️ **Uses Cloudflare DNS API** for DNS-01 challenge (no port 80 required!)
- 🔄 **Auto-renewal** based on certificate lifetime threshold
- 🎛️ **Zero-config deployment** with sensible defaults
- 💰 **$0/month cost** (free Cloudflare DNS API)

## ⚡ Quick Start

### Prerequisites

- ✅ .NET 8 SDK
- ✅ Docker Desktop
- ✅ Cloudflare account with domain
- ✅ 10 minutes

### 1. Start Step CA

```powershell
docker-compose up -d
```

### 2. Trust Step CA Root Certificate

```powershell
# Export from container
docker cp step-ca:/home/step/certs/root_ca.crt ./stepca-root.crt

# Install (run as Administrator)
certutil -addstore -user -f "ROOT" ./stepca-root.crt
```

### 3. Add Hosts Entry

```powershell
# Run as Administrator
Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "`n127.0.0.1 localca.example.com"
```

### 4. Configure Cloudflare Credentials

Edit `EdgeCertAgent/CertificateAgent.cs` (lines 130-131):

```csharp
public string? CloudflareApiToken { get; set; } = "YOUR_CLOUDFLARE_TOKEN";
public string? CloudflareZoneId { get; set; } = "YOUR_ZONE_ID";
```

**Get Cloudflare Credentials:**
- **Zone ID**: Dashboard → Select domain → Overview (right side)
- **API Token**: Profile → API Tokens → Create Token → "Edit zone DNS" template

### 5. Run the Agent

```powershell
cd EdgeCertAgent
dotnet run
```

**That's it!** Certificates saved to `./certs/`

## 📦 What You Get

Generated in `./certs/` directory:

| File | Description |
|------|-------------|
| `cert.pem` | Your SSL/TLS certificate |
| `key.pem` | Private key (RSA-2048) |
| `ca.pem` | Step CA root certificate chain |
| `account.pem` | ACME account key (reused) |
| `cert.pem.der` | Certificate in DER format |

## 🛠️ Configuration

All parameters are **optional** (defaults pre-configured):

```powershell
dotnet run -- \
  --url=https://localca.example.com:9443/acme/acme/directory \
  --subject=acme.dhygw.org \
  --email=test@dhygw.org \
  --cf-token=YOUR_TOKEN \
  --cf-zone=YOUR_ZONE_ID \
  --threshold=75 \
  --out=./certs
```

### Options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--url` | `https://localca.example.com:9443/acme/acme/directory` | Step CA ACME endpoint |
| `--subject` | `acme.dhygw.org` | Domain for certificate |
| `--email` | `test@dhygw.org` | ACME account email |
| `--cf-token` | *(set in code)* | Cloudflare API token |
| `--cf-zone` | *(set in code)* | Cloudflare Zone ID |
| `--threshold` | `75` | Renewal threshold % |
| `--out` | `./certs` | Output directory |

## 🔄 How It Works

```
┌─────────────┐
│ EdgeCert    │ 1. Request certificate
│ Agent       │───────────────────────────┐
└─────────────┘                           │
                                          ▼
┌─────────────┐                    ┌─────────────┐
│ Cloudflare  │ 3. Create TXT      │  Step CA    │
│ DNS API     │◄───────────────────│  (Docker)   │
└─────────────┘    _acme-challenge └─────────────┘
      │                                   │
      │ 4. DNS Propagation (30s)          │
      │                                   │
      │ 5. Validate via DNS query         │
      │◄──────────────────────────────────┤
      │                                   │
      │ 6. TXT record confirmed           │
      ├──────────────────────────────────►│
      │                                   │
      │                            7. Issue cert
      │                                   │
      │ 8. Cleanup TXT record             │
      │◄──────────────────────────────────┤
      │                                   ▼
      │                         9. Save cert.pem
```

### DNS-01 Challenge Process

1. **Agent → Step CA**: "I want a certificate for `acme.dhygw.org`"
2. **Step CA → Agent**: "Create DNS TXT record: `_acme-challenge.acme.dhygw.org = abc123xyz`"
3. **Agent → Cloudflare**: Create TXT record via REST API
4. **Agent**: Wait 30 seconds for DNS propagation
5. **Agent → Step CA**: "Ready for validation"
6. **Step CA → DNS**: Query `_acme-challenge.acme.dhygw.org`
7. **DNS → Step CA**: "Value is `abc123xyz`" ✓
8. **Step CA → Agent**: "Here's your certificate"
9. **Agent → Cloudflare**: Delete TXT record (cleanup)

## 🎨 Architecture

```
┌────────────────────────────────────────┐
│         EdgeCertAgent (.NET 8)         │
│                                        │
│  ┌──────────────────────────────────┐  │
│  │    CertificateAgent              │  │
│  │  - ACME Client (Certes)          │  │
│  │  - Renewal Logic                 │  │
│  │  - Certificate Management        │  │
│  └────────────┬─────────────────────┘  │
│               │                        │
│  ┌────────────▼─────────────────────┐  │
│  │    IDnsProvider Interface        │  │
│  └────────────┬─────────────────────┘  │
│               │                        │
│  ┌────────────▼─────────────────────┐  │
│  │  CloudflareDnsProvider           │  │
│  │  - REST API Integration          │  │
│  │  - TXT Record Create/Delete      │  │
│  └────────────┬─────────────────────┘  │
└───────────────┼─────────────────────────┘
                │
                │ HTTPS REST API
                ▼
    ┌───────────────────────┐
    │   Cloudflare DNS API  │
    │   (api.cloudflare.com)│
    └───────────────────────┘
                │
                │ ACME DNS-01
                ▼
    ┌───────────────────────┐
    │      Step CA          │
    │  (Docker Container)   │
    │  Port: 9443           │
    └───────────────────────┘
```

## 🔐 Security Features

- ✅ **DNS-01 Challenge** - No public ports required (80/443)
- ✅ **TLS Certificate Validation** - Trusted root CA
- ✅ **ACME Account Key** - ES256 elliptic curve
- ✅ **Private Key** - RSA-2048 encryption
- ✅ **Automatic Cleanup** - DNS records removed after validation
- ✅ **Zero-touch Operation** - No manual intervention needed

## 🚀 Production Deployment

### Scheduled Renewal

```powershell
# Run daily at 2 AM
$action = New-ScheduledTaskAction -Execute "dotnet.exe" -Argument "run" -WorkingDirectory "C:\Projects\eca-server-poc\EdgeCertAgent"
$trigger = New-ScheduledTaskTrigger -Daily -At 2am
Register-ScheduledTask -TaskName "EdgeCertAgent-Renewal" -Action $action -Trigger $trigger
```

### Windows Service

```powershell
# Using NSSM (nssm.cc)
nssm install EdgeCertAgent "C:\Program Files\dotnet\dotnet.exe" "run"
nssm set EdgeCertAgent AppDirectory "C:\Projects\eca-server-poc\EdgeCertAgent"
nssm start EdgeCertAgent
```

### Multiple Domains

```powershell
dotnet run -- --subject=api.example.com --out=./certs/api
dotnet run -- --subject=web.example.com --out=./certs/web
dotnet run -- --subject=admin.example.com --out=./certs/admin
```

## 📊 DNS-01 vs HTTP-01

| Feature | DNS-01 (This Project) | HTTP-01 |
|---------|----------------------|---------|
| **Port 80 Required** | ❌ No | ✅ Yes |
| **Public IP Required** | ❌ No | ✅ Yes |
| **Admin Rights** | ❌ No | ✅ Yes (Windows) |
| **Firewall Friendly** | ✅ Yes | ❌ No |
| **Wildcard Certs** | ✅ Yes | ❌ No |
| **Multi-Service** | ✅ Yes | ⚠️ Limited |
| **DNS API Required** | ✅ Yes | ❌ No |
| **Air-gapped Networks** | ✅ Yes* | ❌ No |

*With DNS accessible

## 🛠️ Troubleshooting

### Cloudflare API Error 401
❌ **Invalid API token**  
✅ Generate new token at https://dash.cloudflare.com/profile/api-tokens

### Challenge Status: Invalid
❌ **DNS record not found**  
✅ Verify domain in Cloudflare dashboard  
✅ Check nameservers: `nslookup -type=NS yourdomain.com`

### Connection Refused
❌ **Step CA not running**  
✅ Run: `docker-compose up -d`  
✅ Check: `docker-compose logs step-ca`

### TLS Certificate Validation
❌ **Root CA not trusted**  
✅ Run Step 2 above (trust root certificate)  
✅ Alternative: Use `--insecure` flag (not recommended)

## 📚 Documentation

- **[QUICK_START.md](QUICK_START.md)** - Detailed step-by-step guide
- **[PROJECT_SUMMARY.md](PROJECT_SUMMARY.md)** - Technical architecture
- **[CERTIFICATE_FILES_GUIDE.md](CERTIFICATE_FILES_GUIDE.md)** - Certificate file formats

## 💰 Cost Analysis

| Component | Cost |
|-----------|------|
| **Step CA** | $0 (self-hosted Docker) |
| **Cloudflare DNS API** | $0 (free tier) |
| **.NET 8 Runtime** | $0 (open source) |
| **Certes Library** | $0 (MIT license) |
| **Domain Registration** | ~$10/year |
| **Total Monthly Cost** | **$0** |

## 🧪 Tested Configuration

- ✅ Windows 11 with PowerShell
- ✅ .NET 8.0
- ✅ Docker Desktop 4.x
- ✅ Step CA v0.25+
- ✅ Cloudflare Free Tier
- ✅ Real domain: `acme.dhygw.org`

## 🤝 Contributing

This is a proof-of-concept project. Contributions welcome!

## 📄 License

MIT License - See LICENSE file

## 🎓 Learn More

- **ACME Protocol**: [RFC 8555](https://datatracker.ietf.org/doc/html/rfc8555)
- **Step CA**: https://smallstep.com/docs/step-ca/
- **Certes Library**: https://github.com/fszlin/certes
- **Cloudflare API**: https://developers.cloudflare.com/api/

---

**Made with ❤️ using .NET 8 and Cloudflare DNS**
