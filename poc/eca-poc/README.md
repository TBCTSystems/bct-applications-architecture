# Certificate Auto-Renewal Service for Step CA

Automated certificate lifecycle management service for [Step CA](https://smallstep.com/docs/step-ca/) with percentage-based renewal thresholds and CRL support.

**Available in two implementations:**
- **Python** - Production-ready service with full feature set
- **PowerShell** - Windows-native alternative

---

## Quick Start

### Prerequisites

**Common:**
- Step CA running (Docker or native)
- Step CLI installed ([download](https://smallstep.com/docs/step-cli/installation/))

**Python Version:**
- Python 3.8+
- pip

**PowerShell Version:**
- PowerShell 5.1+ or PowerShell 7+
- `powershell-yaml` module

---

## Python Version

### Installation

```bash
# Install dependencies
pip install -r requirements.txt

# Or use the setup script
./setup.ps1  # Windows
./setup.sh   # Linux/Mac
```

### Configuration

Edit `config/config.yaml`:

```yaml
# Renewal threshold (percentage of certificate lifetime remaining)
renewal_threshold_percent: 33.0  # Renew when 33% or less of lifetime remains

# Step CA settings
step_ca:
  protocol: "JWK"  # or "EST"
  ca_url: "https://localhost:9000"
  ca_fingerprint: "your-ca-fingerprint"
  provisioner_name: "admin"
  provisioner_password: "password"
  root_cert_path: "certs/root_ca.crt"
  
  # CRL settings
  crl_enabled: true
  crl_urls:
    - "https://localhost:9000/crl"

# Certificates to monitor
certificates:
  - name: "web-server"
    cert_path: "certs/web-server.crt"
    key_path: "certs/web-server.key"
    subject: "web.example.com"
```

### Running

```bash
# Single check
python main.py --config config/config.yaml --mode check

# Continuous monitoring
python main.py --config config/config.yaml --mode service

# Using the convenience script
./start-renewal-service.ps1  # Windows
```

---

## PowerShell Version

### Installation

```powershell
# Install powershell-yaml module
Install-Module -Name powershell-yaml -Scope CurrentUser -Force

# Or use the installation script
.\ps-scripts\Install-CertRenewalService.ps1
```

### Configuration

Edit `test/test-config/config.yaml` (same format as Python version):

```yaml
renewal_threshold_percent: 33.0

step_ca:
  protocol: "JWK"
  ca_url: "https://localhost:9000"
  ca_fingerprint: "your-ca-fingerprint"
  provisioner_name: "admin"
  provisioner_password: "password"
  root_cert_path: "test/step-ca/certs/root_ca.crt"
  
  crl_enabled: true
  crl_urls:
    - "https://localhost:9000/crl"

certificates:
  - name: "web-server"
    cert_path: "certs/web-server.crt"
    key_path: "certs/web-server.key"
    subject: "web.example.com"
```

### Running

```powershell
# Single check
.\ps-scripts\Start-CertRenewalService.ps1 -ConfigPath test\test-config\config.yaml -Mode check

# Continuous monitoring
.\ps-scripts\Start-CertRenewalService.ps1 -ConfigPath config\config.yaml -Mode service

# Using the convenience launcher
.\Start-PowerShellService.ps1 -ConfigPath test\test-config\config.yaml -Mode check
```

---

## Key Features

- **Percentage-Based Renewal** - Renew when X% of certificate lifetime remains (calculated in seconds for precision)
- **CRL Support** - Automatic certificate revocation checking with smart caching
- **Multiple Protocols** - JWK (Step CA native) or EST (RFC 7030 standard)
- **Flexible Configuration** - YAML-based with per-certificate threshold overrides
- **Comprehensive Logging** - Structured logging with file and console output

---

## Configuration Options

### Renewal Threshold

```yaml
# Global threshold (applies to all certificates unless overridden)
renewal_threshold_percent: 33.0  # Renew at 33% remaining lifetime

# Per-certificate override
certificates:
  - name: "critical-cert"
    cert_path: "certs/critical.crt"
    key_path: "certs/critical.key"
    renewal_threshold_percent: 50.0  # Renew earlier for critical certs
```

**Example:** For a 90-day certificate with 33% threshold:
- Total lifetime: 90 days
- Renewal triggers at: 30 days remaining (33% of 90 days)

### Protocol Selection

**JWK (Step CA Native):**
```yaml
step_ca:
  protocol: "JWK"
  ca_url: "https://localhost:9000"
  provisioner_name: "admin"
  provisioner_password: "password"
```

**EST (RFC 7030 Standard):**
```yaml
step_ca:
  protocol: "EST"
  ca_url: "https://localhost:9000/.well-known/est"
  est_username: "est-client"
  est_password: "est-secret"
```

### CRL Configuration

```yaml
step_ca:
  crl_enabled: true
  crl_urls:
    - "https://localhost:9000/crl"  # Manual CRL URL
  crl_cache_dir: "certs/crl"        # Local cache directory
  crl_refresh_hours: 24              # Refresh interval
```

---

## Testing

### Python
```bash
# Run with test configuration
python main.py --config test/test-config/config.yaml --mode check
```

### PowerShell
```powershell
# Run with test configuration
.\ps-scripts\Start-CertRenewalService.ps1 -ConfigPath test\test-config\config.yaml -Mode check
```

### Docker
```bash
# Start Step CA test instance
docker-compose up -d

# Verify Step CA is running
docker ps | grep step-ca
```

---

## Documentation

- **Detailed Python Documentation**: See main sections below
- **PowerShell Documentation**: `ps-scripts/POWERSHELL-README.md`
- **Deployment Guide**: `DEPLOYMENT.md`
- **Startup Guide**: `STARTUP-GUIDE.md`

---

## Project Structure

```
.
├── src/                    # Python source code
│   ├── certificate_monitor.py
│   ├── crl_manager.py
│   ├── renewal_service.py
│   └── step_ca_client.py
├── ps-scripts/             # PowerShell implementation
│   ├── CertMonitor.ps1
│   ├── CRLManager.ps1
│   ├── CertRenewalService.ps1
│   └── Start-CertRenewalService.ps1
├── config/                 # Configuration files
├── test/                   # Test configurations and data
├── main.py                 # Python entry point
└── README.md               # This file
```

---

## Support

For detailed information on each implementation:
- Python: See sections below and `DEPLOYMENT.md`
- PowerShell: See `ps-scripts/POWERSHELL-README.md`
