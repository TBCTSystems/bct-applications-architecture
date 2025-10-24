# Certificate Renewal Service - PowerShell Edition

A PowerShell-based implementation of the certificate renewal service for Step CA, providing automated certificate lifecycle management with CRL (Certificate Revocation List) support.

## Requirements

### Software Requirements
- **PowerShell 5.1 or later** (Windows PowerShell or PowerShell Core)
- **Step CLI** (`step`) - Must be available in PATH
- **Step CA** - Running instance (Docker or native)
- **powershell-yaml module** - Required for YAML configuration parsing
  ```powershell
  Install-Module -Name powershell-yaml -Scope CurrentUser -Force
  ```

## Architecture

### PowerShell Modules

The service is organized into modular PowerShell scripts:

```
ps-scripts/
├── CertRenewalService.ps1   # Main service orchestration
├── CertRenewalConfig.ps1    # Configuration management  
├── CertRenewalLogger.ps1    # Logging functionality
├── CertMonitor.ps1          # Certificate monitoring and expiry checking
├── StepCAClient.ps1         # Step CA communication
└── CRLManager.ps1           # CRL downloading and revocation checking
```

### Key Components

#### 1. CertRenewalService
Main service class that:
- Initializes all components
- Orchestrates certificate checking cycles
- Manages continuous monitoring mode

#### 2. CertMonitor
Monitors certificates and determines renewal requirements:
- Checks certificate expiry using percentage thresholds
- Validates certificate files
- Integrates with CRL checking
- Provides detailed status reporting

#### 3. StepCAClient
Handles Step CA operations:
- Bootstraps Step CA configuration
- Renews existing certificates
- Requests new certificates when renewal fails
- Verifies certificates against root CA

#### 4. CRLManager
Manages Certificate Revocation Lists:
- Downloads CRLs from configured URLs
- Caches CRLs locally with smart refresh logic
- Checks certificate revocation status
- 60-second in-memory cache to avoid redundant downloads

#### 5. CertRenewalConfig
Configuration management:
- Loads YAML configuration files
- Provides defaults for missing values
- Supports both powershell-yaml module and fallback parsing

#### 6. CertRenewalLogger
Structured logging:
- Multiple log levels (DEBUG, INFO, WARNING, ERROR, CRITICAL)
- Console and file output
- Timestamped messages

## Configuration

Uses the same YAML configuration format as the Python version. Example:

```yaml
# Service Settings
check_interval_minutes: 30
log_level: INFO
log_file: logs/cert_renewal.log
cert_storage_path: certs

# Renewal Threshold (percentage-based)
renewal_threshold_percent: 33.0  # Renew when 33% or less lifetime remains

# Step CA Configuration
step_ca:
  protocol: "JWK"
  ca_url: "https://localhost:9000"
  ca_fingerprint: "your-ca-fingerprint-here"
  provisioner_name: "admin"
  provisioner_password: "yourpassword"
  root_cert_path: "certs/root_ca.crt"
  
  # CRL Settings
  crl_enabled: true
  crl_urls:
    - "https://localhost:9000/crl"
  crl_cache_dir: "certs/crl"
  crl_refresh_hours: 24
  crl_timeout_seconds: 30

# Certificates to Monitor
certificates:
  - name: "web-server"
    cert_path: "certs/web-server.crt"
    key_path: "certs/web-server.key"
    renewal_threshold_percent: 33.0  # Optional override
    subject: "web.example.com"
    sans:
      - "www.example.com"
      - "api.example.com"
```

## Installation

### Quick Start
From the project root directory, run the automated installation script:

```powershell
.\ps-scripts\Install-CertRenewalService.ps1
```

This script will:
- Verify PowerShell version (5.1+ required)
- Install the `powershell-yaml` module
- Check for Step CLI availability
- Verify Step CA is running
- Create required directories
- Validate configuration loading

### Manual Installation
1. Install the powershell-yaml module:
   ```powershell
   Install-Module -Name powershell-yaml -Scope CurrentUser -Force
   ```

2. Ensure Step CLI is available in PATH or in `.\step-cli\` directory

3. Start Step CA (if using Docker):
   ```powershell
   docker-compose up -d
   ```

## Usage

All commands should be run from the **project root directory** (not from within ps-scripts).

### Single Certificate Check
Run a one-time check and renewal of all configured certificates:

```powershell
.\ps-scripts\Start-CertRenewalService.ps1 -ConfigPath test\test-config\config.yaml -Mode check
```

### Continuous Monitoring Service
Run continuous monitoring with automatic periodic checks:

```powershell
.\ps-scripts\Start-CertRenewalService.ps1 -ConfigPath config\config.yaml -Mode service
```

Press `Ctrl+C` to gracefully stop the service.

### Testing with Docker Step CA

1. **Start the test Step CA container:**
   ```powershell
   .\start-step-ca-docker.ps1
   ```

2. **Run a test check:**
   ```powershell
   .\Start-CertRenewalService.ps1 -Mode check
   ```

## Features

### Percentage-Based Renewal Thresholds
Certificates are renewed based on the percentage of remaining lifetime:
- **33%** = Renew when certificate has used 67% of its lifetime
- **10%** = Emergency renewal threshold
- **0%** = Expired (immediate renewal required)

### CRL Support
- Automatic CRL downloading from configured URLs
- Local caching with configurable refresh intervals
- 60-second in-memory cache to avoid redundant downloads
- Detection of revoked certificates triggers immediate renewal
- Fallback to cached CRLs if download fails

### Smart Renewal Logic
1. Check certificate expiry and CRL status
2. Attempt to renew using existing certificate
3. If renewal fails (e.g., revoked), request new certificate
4. Verify renewed certificate against root CA
5. Keep backup of original certificate

### Logging
- Structured logging with timestamps
- Configurable log levels
- Both console and file output
- Color-coded console messages

## Differences from Python Version

### Similarities
✅ Same configuration format (YAML)  
✅ Same core functionality and logic  
✅ Same percentage-based renewal thresholds  
✅ Same CRL management approach  
✅ Compatible with same test infrastructure  

### Key Differences
- **No Python dependencies** - Pure PowerShell implementation
- **Native Windows integration** - Better Windows process management
- **Step CLI required** - Uses step CLI for certificate operations (Python version had EST protocol option)
- **Simplified CRL parsing** - Uses step CLI for CRL inspection when available
- **PowerShell classes** - Object-oriented design using PowerShell classes

## Testing

The PowerShell version works with the same test infrastructure:

1. **Test Step CA Container:** Use existing `start-step-ca-docker.ps1`
2. **Test Certificates:** Compatible with existing dummy certificates
3. **Test Configuration:** Use existing `test/test-config/config.yaml`
4. **CRL Testing:** Works with Step CA's built-in CRL functionality

## Troubleshooting

### Step CLI Not Found
Ensure `step` CLI is in your PATH:
```powershell
Get-Command step
```

### SSL Certificate Validation
For self-signed certificates (testing), the service automatically skips certificate validation for localhost URLs. For production, ensure proper CA certificates are configured.

### CRL Download Failures
The service falls back to cached CRLs if downloads fail. Check:
- CRL URLs are accessible
- Network connectivity
- SSL/TLS configuration
- CRL cache directory exists and is writable

### PowerShell Version
Check your PowerShell version:
```powershell
$PSVersionTable.PSVersion
```
Requires 5.1 or later.

## Migrating from Python Version

1. **Keep your configuration files** - They work as-is
2. **Keep your test infrastructure** - Step CA container setup unchanged
3. **Update startup script** - Use `Start-CertRenewalService.ps1` instead of Python scripts
4. **No Python dependencies needed** - Uninstall Python packages if desired
5. **Ensure step CLI installed** - Both versions need it

## Production Deployment

### Windows Service
To run as a Windows Service, consider using:
- **NSSM** (Non-Sucking Service Manager)
- **Windows Task Scheduler** with "run at startup" trigger
- **PowerShell Scheduled Job**

### Monitoring
- Check log files regularly (`log_file` in config)
- Monitor certificate expiry dates
- Set up alerts for renewal failures
- Track CRL download success rates

### Security
- Protect provisioner passwords (use environment variables or secure storage)
- Limit file permissions on private keys
- Secure log files (may contain sensitive info)
- Use proper SSL/TLS validation in production

## License

Same license as the original Python version.

## Support

For issues specific to the PowerShell implementation, check:
1. PowerShell version compatibility
2. Step CLI availability and version
3. Configuration file syntax
4. Log files for detailed error messages
