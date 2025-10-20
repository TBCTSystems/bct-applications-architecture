# Certificate Renewal Service - Test Environment

This directory contains a complete test environment for the certificate renewal service with dummy certificates, Step CA server, and automated testing tools.

## 🚀 Quick Start

### 1. Install Prerequisites

**Step CLI** (required for Step CA):
```powershell
# Using Chocolatey
choco install step

# Or download from: https://smallstep.com/docs/step-cli/installation/
```

**Docker Desktop** (for containerized testing):
- Download from: https://www.docker.com/products/docker-desktop/

**Python Dependencies**:
```powershell
pip install cryptography pydantic pyyaml requests python-dotenv
```

### 2. Run Full Setup (Recommended)

```powershell
# Navigate to project root
cd "c:\Users\jdavusb5\OneDrive - Terumo BCT\Documents\CertRenew\Client POC"

# Run complete setup
.\setup-test-env.ps1 -SetupAll
```

### 3. Manual Setup (Step by Step)

```powershell
# 1. Generate dummy certificates
python test\generate_dummy_certs.py

# 2. Initialize Step CA
.\test\init-step-ca.ps1

# 3. Start Step CA server
cd test
docker-compose -f docker-compose.test.yml up -d step-ca-test

# 4. Get CA fingerprint and update config
step certificate fingerprint step-ca\certs\root_ca.crt

# 5. Update the fingerprint in test-config\config.yaml
# Replace "REPLACE_WITH_ACTUAL_FINGERPRINT" with the actual fingerprint

# 6. Validate environment
python validate_test_env.py

# 7. Run tests
python test_runner.py
```

## 📁 Directory Structure

```
test/
├── README.md                    # This file
├── generate_dummy_certs.py      # Generates test certificates with various expiration dates
├── test_runner.py               # Automated test suite
├── validate_test_env.py         # Environment validation script
├── init-step-ca.ps1            # Step CA initialization (PowerShell)
├── init-step-ca.sh             # Step CA initialization (Bash)
├── docker-compose.test.yml      # Docker test environment
├── step-ca/                     # Step CA data directory
├── dummy-certs/                 # Generated test certificates
│   ├── ca.crt                  # Test CA certificate
│   ├── ca.key                  # Test CA private key
│   ├── test-web-server.crt     # Web server cert (expires in 10 days)
│   ├── test-api-server.crt     # API server cert (expires in 20 days)
│   ├── test-expiring-soon.crt  # Emergency cert (expires in 2 days)
│   ├── test-already-expired.crt # Already expired cert
│   └── certificate_summary.txt  # Summary of all generated certificates
├── client-certs/               # Directory for renewed certificates
├── test-config/                # Test configuration files
│   └── config.yaml            # Main test configuration
└── logs/                      # Test logs and reports
```

## 🧪 Test Scenarios

### Certificate Expiration Scenarios
- **`test-web-server`** - Expires in 10 days (should trigger renewal)
- **`test-api-server`** - Expires in 20 days (normal certificate)
- **`test-expiring-soon`** - Expires in 2 days (emergency renewal)
- **`test-valid-long`** - Expires in 60 days (should not renew)
- **`test-already-expired`** - Already expired (immediate renewal needed)
- **`test-client-auth`** - Expires in 7 days (client authentication)

### Protocol Testing
- ✅ **JWK Protocol** - Native Step CA integration
- ✅ **EST Protocol** - Enterprise CA compatibility (configurable)
- ✅ **CRL Checking** - Certificate revocation validation

### Service Operations
- ✅ Service initialization and configuration validation
- ✅ Certificate status monitoring and reporting
- ✅ Automatic renewal with threshold-based triggering
- ✅ Daemon mode for continuous operation
- ✅ Error handling and recovery

## 🔧 Configuration

### Test Configuration Features
- **Fast checking**: 2-minute intervals (vs 30 minutes in production)
- **Short renewal thresholds**: 1-5 days (vs 30+ days in production)
- **Debug logging**: Full visibility into operations
- **Test-friendly paths**: Relative paths for easy testing

### Key Configuration Settings
```yaml
# Fast testing intervals
check_interval_minutes: 2

# Short renewal thresholds
default_renewal_threshold_days: 5
emergency_renewal_threshold_days: 1

# Debug logging
log_level: DEBUG
log_file: test/logs/cert_renewal_test.log

# Step CA connection
step_ca:
  protocol: "JWK"
  ca_url: "https://localhost:9000"
  provisioner_name: "admin"
  provisioner_password: "adminpassword"
```

## 🐳 Docker Testing

### Start Test Environment
```powershell
cd test
docker-compose -f docker-compose.test.yml up -d
```

### View Service Logs
```powershell
# Step CA logs
docker logs step-ca-test

# Renewal service logs  
docker logs cert-renewal-test
```

### Execute Commands in Container
```powershell
# Run status check in container
docker exec -it cert-renewal-test python main.py status

# Run certificate check in container
docker exec -it cert-renewal-test python main.py check --dry-run
```

### Stop Test Environment
```powershell
cd test
docker-compose -f docker-compose.test.yml down
```

## 🧪 Running Tests

### Automated Test Suite
```powershell
# Run all tests
python test\test_runner.py

# Run with custom config
python test\test_runner.py path\to\custom\config.yaml
```

### Manual Testing Commands

**Initialize Service**:
```powershell
python main.py --config test\test-config\config.yaml init
```

**Check Certificate Status**:
```powershell
python main.py --config test\test-config\config.yaml status
```

**Run Certificate Check (Dry Run)**:
```powershell
python main.py --config test\test-config\config.yaml check --dry-run
```

**Start Daemon Mode**:
```powershell
python main.py --config test\test-config\config.yaml daemon
```

**Test CRL Functionality**:
```powershell
python main.py --config test\test-config\config.yaml crl
```

### Environment Validation
```powershell
# Comprehensive environment check
python test\validate_test_env.py
```

## 🔍 Troubleshooting

### Common Issues

**Step CA Not Starting**
```powershell
# Check if port 9000 is in use
netstat -an | findstr 9000

# Check Docker container status
docker ps -a

# View Step CA logs
docker logs step-ca-test
```

**Certificate Generation Fails**
```powershell
# Install cryptography package
pip install cryptography

# Check file permissions
icacls test\dummy-certs
```

**Service Connection Issues**
1. Verify CA fingerprint in config matches actual fingerprint:
   ```powershell
   step certificate fingerprint test\step-ca\certs\root_ca.crt
   ```

2. Update `test-config\config.yaml` with correct fingerprint

3. Check network connectivity:
   ```powershell
   # Test CA endpoint (ignore SSL errors for testing)
   curl -k https://localhost:9000/health
   ```

**Tests Failing**
```powershell
# Check prerequisites
python --version
step version
docker --version

# Validate environment
python test\validate_test_env.py

# Check configuration
python main.py --config test\test-config\config.yaml init
```

### Log Locations
- **Service logs**: `test/logs/cert_renewal_test.log`
- **Docker logs**: `docker logs <container-name>`
- **Test reports**: `test/logs/test_reports/`

## 🎯 Next Steps After Testing

Once testing is complete and successful:

1. **Production Configuration**: Copy and modify the test configuration for production use
2. **Certificate Deployment**: Replace dummy certificates with actual certificates
3. **Monitoring Setup**: Configure monitoring and alerting for production
4. **Backup Strategy**: Implement certificate and key backup procedures
5. **Automation**: Set up automated deployment and CI/CD integration

## 📚 Additional Resources

- [Step CA Documentation](https://smallstep.com/docs/step-ca/)
- [EST Protocol RFC 7030](https://tools.ietf.org/html/rfc7030)
- [Certificate Management Best Practices](https://smallstep.com/blog/certificate-management-best-practices/)
- [Main Project README](../README.md)
- [Deployment Guide](../DEPLOYMENT.md)