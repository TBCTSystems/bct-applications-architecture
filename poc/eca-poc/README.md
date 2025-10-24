# Certificate Auto-Renewal Service for Step CA

A robust, production-ready service that automatically monitors and renews certificates using [Step CA](https://smallstep.com/docs/step-ca/). This proof of concept demonstrates automated certificate lifecycle management with configurable renewal thresholds, comprehensive logging, and Docker deployment.

**Available in Two Implementations:**
- **Python Version** - Production-ready service (main implementation)
- **PowerShell Version** - Windows-native alternative (see `ps-scripts/POWERSHELL-README.md`)

## Features

- 🔄 **Automatic Certificate Renewal** - Monitors certificate expiration and renews before expiry
- 📊 **Certificate Status Monitoring** - Real-time status reporting for all managed certificates
- ⚙️ **Flexible Configuration** - YAML configuration with environment variable overrides
- 📝 **Comprehensive Logging** - Structured logging with rotation and multiple output formats
- 🐳 **Docker Ready** - Complete Docker setup for easy deployment
- 🔒 **Secure by Default** - Uses Step CA's secure certificate management
- 📈 **Health Monitoring** - Built-in health checks and status reporting
- 🎯 **CLI Interface** - Command-line tools for manual operations and monitoring
- 🔌 **Multiple Protocols** - Supports both JWK (Step CA native) and EST protocols
- 🚫 **CRL Support** - Automatic certificate revocation checking using CRLs
- 🔄 **Smart CRL Caching** - Efficient CRL download and caching with refresh logic

## Supported Protocols

### JWK (JSON Web Key) - Step CA Native
- **Best for**: Step CA deployments, modern PKI environments
- **Authentication**: JWT tokens with JWK provisioners
- **Features**: Full Step CA integration, advanced provisioner types
- **Requirements**: Step CLI installed

### EST (Enrollment over Secure Transport)
- **Best for**: Legacy PKI environments, SCEP migration, enterprise CAs
- **Authentication**: HTTP Basic Auth or client certificates
- **Features**: Standards-based RFC 7030 compliance
- **Requirements**: EST-compatible CA server

Choose the protocol that best fits your PKI infrastructure and security requirements.

## Certificate Revocation List (CRL) Support

The service includes comprehensive CRL support to check certificate revocation status:

### **Features:**
- **Automatic CRL Discovery** - Extracts CRL URLs from certificate distribution points
- **Manual CRL Configuration** - Support for explicit CRL URLs in configuration
- **Smart Caching** - Downloads and caches CRLs locally with configurable refresh intervals
- **Multiple CRL Sources** - Can check against multiple CRLs simultaneously
- **Revocation Reasons** - Reports revocation date, reason, and source CRL
- **Forced Renewal** - Automatically triggers renewal for revoked certificates

### **How it Works:**
1. **Certificate Analysis** - Extracts CRL distribution points from each certificate
2. **CRL Download** - Downloads CRLs from configured URLs and certificate distribution points
3. **Local Caching** - Caches CRLs locally to reduce network calls
4. **Revocation Check** - Validates certificate serial numbers against CRL entries
5. **Smart Refresh** - Refreshes CRLs based on nextUpdate time or configured interval
6. **Automatic Action** - Forces certificate renewal if revocation is detected

### **Configuration:**
```yaml
step_ca:
  crl_enabled: true
  crl_urls:
    - "http://ca.example.com/crl/ca.crl"
  crl_cache_dir: "certs/crl"
  crl_refresh_hours: 24
```

### **Usage:**
```bash
# Check CRL status
python main.py crl

# Force refresh all CRLs
python main.py crl --refresh

# Status with revocation info
python main.py status
```

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Certificate    │    │   Renewal        │    │    Step CA      │
│  Monitor        │───▶│   Service        │───▶│    Server       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Certificate   │    │     Logging      │    │   Certificate   │
│   Storage       │    │     System       │    │   Validation    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Quick Start

### Prerequisites

- Python 3.8+ (3.11+ recommended for best timezone support)
- Step CLI installed
- Access to a Step CA instance
- Docker (optional, for containerized deployment)

### Installation

1. **Clone or download this project**
   ```bash
   git clone <repository-url>
   cd cert-renewal-service
   ```

2. **Install Python dependencies**
   ```bash
   pip install -r requirements.txt
   ```

3. **Install Step CLI** (if not already installed)
   ```bash
   # macOS
   brew install step
   
   # Ubuntu/Debian
   wget -O step.deb https://github.com/smallstep/cli/releases/latest/download/step-cli_amd64.deb
   sudo dpkg -i step.deb
   
   # Windows
   # Download from https://github.com/smallstep/cli/releases
   ```

### Configuration

1. **Copy and customize the configuration**
   ```bash
   cp config/.env.example .env
   # Edit .env with your Step CA details
   ```

2. **Update config/config.yaml** with your certificate requirements:

   **For JWK (Step CA Native):**
   ```yaml
   step_ca:
     protocol: "JWK"
     ca_url: "https://your-step-ca:9000"
     ca_fingerprint: "your-ca-fingerprint"
     provisioner_name: "your-provisioner"
     provisioner_password: "your-password"  # or use env var
   
   certificates:
     - name: "web-server"
       cert_path: "certs/web-server.crt"
       key_path: "certs/web-server.key"
       subject: "web.example.com"
       renewal_threshold_days: 30
   ```

   **For EST Protocol:**
   ```yaml
   step_ca:
     protocol: "EST"
     ca_url: "https://your-ca:8443/.well-known/est"
     ca_fingerprint: "your-ca-fingerprint"
     est_username: "est-client"
     est_password: "est-password"  # or use client cert auth
   
   certificates:
     - name: "web-server"
       cert_path: "certs/web-server.crt"
       key_path: "certs/web-server.key"
       subject: "web.example.com"
       renewal_threshold_days: 30
   ```

### Usage

#### Initialize the service
```bash
python main.py init
```

#### Check certificate status
```bash
python main.py status
```

#### Check CRL status and refresh
```bash
python main.py crl
python main.py crl --refresh  # Force refresh all CRLs
```

## Renewal Threshold Configuration

The service supports flexible renewal threshold configuration at multiple levels:

### **Three-Tier Threshold System:**

1. **🟢 Normal Threshold** (`default_renewal_threshold_days: 30`)
   - Standard renewal point for certificates
   - Can be overridden per certificate

2. **🟡 Warning Threshold** (`warning_threshold_days: 14`)  
   - Logs warnings but doesn't force renewal yet
   - Helps with early notification

3. **🔴 Emergency Threshold** (`emergency_renewal_threshold_days: 7`)
   - Forces immediate renewal regardless of other factors
   - Critical deadline for certificate replacement

### **Configuration Hierarchy:**
```yaml
# Global defaults (apply to all certificates)
default_renewal_threshold_days: 30
emergency_renewal_threshold_days: 7
warning_threshold_days: 14

certificates:
  - name: "web-server"
    # Uses global default (30 days)
    
  - name: "api-server" 
    renewal_threshold_days: 15  # Custom threshold
    
  - name: "critical-service"
    renewal_threshold_days: 45  # More conservative
```

### **Renewal Logic:**
- **45+ days**: Certificate is valid
- **15-44 days**: Approaching renewal (warning logs)
- **8-14 days**: Normal renewal triggered
- **≤7 days**: Emergency renewal (immediate action)

### **Status Indicators:**
```
✓   🚨 critical-service    # Emergency renewal needed
✓ ⚠     api-server         # Normal renewal needed  
✓       web-server         # Valid, no action needed
```

### Usage Examples
```

#### Run a single renewal check
```bash
python main.py check
```

#### Run as a daemon (continuous monitoring)
```bash
python main.py daemon
```

#### Manually renew a specific certificate
```bash
python main.py renew web-server
```

## Docker Deployment

### Production Deployment

1. **Build and run with Docker Compose**
   ```bash
   # Copy and configure environment
   cp config/.env.example .env
   # Edit .env with your settings
   
   # Start the service
   docker-compose up -d
   ```

2. **Check service status**
   ```bash
   docker-compose logs -f cert-renewal-service
   docker exec cert-renewal-service python main.py status
   ```

### Development with Step CA

For development and testing, you can run a complete environment including Step CA:

```bash
cd docker
docker-compose -f docker-compose.dev.yml up -d step-ca

# Wait for Step CA to initialize, then get the fingerprint
docker exec step-ca-dev step ca root --fingerprint

# Update your .env file with the fingerprint
# Start the renewal service
docker-compose -f docker-compose.dev.yml up cert-renewal-service
```

## Configuration Reference

### Service Configuration

| Setting | Environment Variable | Default | Description |
|---------|---------------------|---------|-------------|
| `check_interval_minutes` | `CERT_RENEWAL_CHECK_INTERVAL_MINUTES` | 30 | Minutes between certificate checks |
| `log_level` | `CERT_RENEWAL_LOG_LEVEL` | INFO | Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL) |
| `log_file` | `CERT_RENEWAL_LOG_FILE` | logs/cert_renewal.log | Path to log file |
| `cert_storage_path` | `CERT_RENEWAL_CERT_STORAGE_PATH` | certs | Directory for certificate storage |

#### Renewal Threshold Settings
| Setting | Environment Variable | Default | Description |
|---------|---------------------|---------|-------------|
| `default_renewal_threshold_days` | `CERT_RENEWAL_DEFAULT_RENEWAL_THRESHOLD_DAYS` | 30 | Default days before expiry to trigger renewal |
| `emergency_renewal_threshold_days` | `CERT_RENEWAL_EMERGENCY_RENEWAL_THRESHOLD_DAYS` | 7 | Emergency threshold - force renewal regardless |
| `warning_threshold_days` | `CERT_RENEWAL_WARNING_THRESHOLD_DAYS` | 14 | Warning threshold - log warnings but don't force renewal |

### Step CA Configuration

| Setting | Environment Variable | Description |
|---------|---------------------|-------------|
| `protocol` | `CERT_RENEWAL_STEP_CA__PROTOCOL` | Authentication protocol: JWK or EST |
| `ca_url` | `CERT_RENEWAL_STEP_CA__CA_URL` | Step CA server URL (JWK) or EST endpoint URL |
| `ca_fingerprint` | `CERT_RENEWAL_STEP_CA__CA_FINGERPRINT` | CA root certificate fingerprint |

#### JWK Provisioner Settings (when protocol = "JWK")
| Setting | Environment Variable | Description |
|---------|---------------------|-------------|
| `provisioner_name` | `CERT_RENEWAL_STEP_CA__PROVISIONER_NAME` | Provisioner name for authentication |
| `provisioner_password` | `CERT_RENEWAL_STEP_CA__PROVISIONER_PASSWORD` | Provisioner password (optional) |
| `provisioner_key_path` | `CERT_RENEWAL_STEP_CA__PROVISIONER_KEY_PATH` | Path to provisioner private key (optional) |

#### EST Settings (when protocol = "EST")
| Setting | Environment Variable | Description |
|---------|---------------------|-------------|
| `est_username` | `CERT_RENEWAL_STEP_CA__EST_USERNAME` | EST HTTP Basic auth username |
| `est_password` | `CERT_RENEWAL_STEP_CA__EST_PASSWORD` | EST HTTP Basic auth password |
| `est_client_cert` | `CERT_RENEWAL_STEP_CA__EST_CLIENT_CERT` | EST client certificate path (alternative auth) |
| `est_client_key` | `CERT_RENEWAL_STEP_CA__EST_CLIENT_KEY` | EST client private key path |
| `est_ca_bundle` | `CERT_RENEWAL_STEP_CA__EST_CA_BUNDLE` | EST CA bundle path (optional) |

#### CRL Settings
| Setting | Environment Variable | Description |
|---------|---------------------|-------------|
| `crl_enabled` | `CERT_RENEWAL_STEP_CA__CRL_ENABLED` | Enable/disable CRL checking (default: true) |
| `crl_urls` | `CERT_RENEWAL_STEP_CA__CRL_URLS` | List of CRL URLs to check (optional) |
| `crl_cache_dir` | `CERT_RENEWAL_STEP_CA__CRL_CACHE_DIR` | Directory for CRL caching (default: certs/crl) |
| `crl_refresh_hours` | `CERT_RENEWAL_STEP_CA__CRL_REFRESH_HOURS` | Hours between CRL refresh (default: 24) |
| `crl_timeout_seconds` | `CERT_RENEWAL_STEP_CA__CRL_TIMEOUT_SECONDS` | CRL download timeout (default: 30) |

### Certificate Configuration

Each certificate in the `certificates` list supports:

- `name`: Unique identifier for the certificate
- `cert_path`: Path where the certificate will be stored
- `key_path`: Path where the private key will be stored  
- `subject`: Certificate subject (Common Name)
- `sans`: List of Subject Alternative Names (optional)
- `renewal_threshold_days`: Days before expiry to trigger renewal (optional - uses service default if not specified)

## CLI Commands

### Global Options

- `--config, -c`: Path to configuration file (default: config/config.yaml)

### Commands

- `daemon`: Run as a continuous monitoring service
- `check`: Perform a single certificate check and renewal cycle
- `status`: Show status of all configured certificates
  - `--format`: Output format (json, table)
- `crl`: Show CRL status and manage revocation lists
  - `--refresh`: Force refresh of all CRLs
- `renew <certificate-name>`: Manually renew a specific certificate
- `init`: Initialize Step CA configuration and test connectivity

## Logging

The service provides structured logging with:

- **Console output**: Real-time status and error information
- **File logging**: Persistent logs with rotation (10MB files, 5 backups)
- **Log levels**: DEBUG, INFO, WARNING, ERROR, CRITICAL
- **Contextual information**: Certificate names, operation details, timestamps

### Log File Locations

- Default: `logs/cert_renewal.log`
- Docker: `/app/logs/cert_renewal.log` (mounted to host `./logs/`)
- Configurable via `log_file` setting

## Monitoring and Health Checks

### Health Check Endpoint

The Docker container includes a built-in health check that verifies:
- Service can start and load configuration
- Step CA connectivity
- Certificate status can be retrieved

### Status Monitoring

Use the status command to get detailed certificate information:

```bash
# Table format (human-readable)
python main.py status

# JSON format (machine-readable)
python main.py status --format json
```

### Metrics

The service logs key metrics:
- Total certificates managed
- Certificates requiring renewal
- Successful/failed renewals
- Certificate validation status

## Security Considerations

1. **Provisioner Credentials**: Store provisioner passwords in environment variables or secure secret management
2. **File Permissions**: Ensure certificate and key files have appropriate permissions (600/644)
3. **Network Security**: Use TLS for Step CA communication and secure network policies
4. **Container Security**: Run containers as non-root user (included in Dockerfile)
5. **Log Security**: Sensitive information is not logged (passwords, private keys)

## Troubleshooting

### Common Issues

1. **Step CLI not found**
   ```
   Error: Step CLI not found. Please install step-cli and ensure it's in PATH.
   ```
   Solution: Install Step CLI or ensure it's in your system PATH

2. **CA Connection Failed**
   ```
   Error: Cannot connect to Step CA
   ```
   Solution: Verify `ca_url`, network connectivity, and CA server status

3. **Certificate Renewal Failed**
   ```
   Error: Failed to renew certificate
   ```
   Solution: Check provisioner credentials, certificate permissions, and CA logs

4. **Permission Denied**
   ```
   Error: Permission denied accessing certificate files
   ```
   Solution: Ensure proper file permissions and user access

### Debug Mode

Enable debug logging for detailed troubleshooting:

```bash
# Via environment variable
CERT_RENEWAL_LOG_LEVEL=DEBUG python main.py daemon

# Via configuration file
log_level: DEBUG
```

### Log Analysis

Key log patterns to monitor:
- `Certificate.*needs renewal`: Certificates approaching expiry
- `Successfully renewed certificate`: Successful renewal operations
- `Failed to.*certificate`: Error conditions requiring attention
- `Step command.*failed`: Step CA communication issues

## Development

### Project Structure

```
cert-renewal-service/
├── src/                          # Source code
│   ├── config.py                # Configuration management
│   ├── logger.py                # Logging system
│   ├── certificate_monitor.py   # Certificate monitoring
│   ├── step_ca_client.py       # Step CA integration
│   └── renewal_service.py       # Main service logic
├── config/                      # Configuration files
│   ├── config.yaml             # Main configuration
│   └── .env.example           # Environment variables template
├── docker/                     # Docker configurations
├── certs/                      # Certificate storage (created at runtime)
├── logs/                       # Log files (created at runtime)
├── main.py                     # CLI entry point
├── requirements.txt            # Python dependencies
├── Dockerfile                  # Container definition
└── docker-compose.yml         # Container orchestration
```

### Adding Features

1. **New Certificate Sources**: Extend `CertificateMonitor` class
2. **Additional Renewal Methods**: Add methods to `StepCAClient` class  
3. **Custom Notifications**: Hook into renewal events in `CertificateRenewalService`
4. **Metrics Export**: Add monitoring integrations to the main service loop

### Code Standards

- **Timezone-aware Dates**: All datetime objects use `datetime.now(datetime.timezone.utc)` instead of deprecated `datetime.utcnow()`
- **Type Hints**: Full type annotations for better code clarity and IDE support
- **Error Handling**: Comprehensive exception handling with detailed logging
- **Configuration**: Pydantic models for robust configuration validation

### Testing

Create a test environment:

```bash
# Start development environment with Step CA
cd docker
docker-compose -f docker-compose.dev.yml up -d

# Initialize and test
python main.py init
python main.py status
```

## License

This project is provided as-is for demonstration purposes. Please review and adapt security configurations for production use.

## Support

For issues and questions:
1. Check the troubleshooting section above
2. Review the Step CA documentation: https://smallstep.com/docs/
3. Enable debug logging for detailed error information