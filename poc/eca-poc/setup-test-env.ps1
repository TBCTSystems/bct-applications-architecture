# Test Environment Setup Script for Certificate Renewal Service
# This script sets up a complete testing environment with Step CA and dummy certificates

param(
    [Parameter(Mandatory=$false)]
    [string]$TestDir = "test",
    
    [Parameter(Mandatory=$false)]
    [switch]$StartStepCA = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$GenerateDummyCerts = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$SetupAll = $false
)

$ErrorActionPreference = "Stop"

Write-Host "Certificate Renewal Service - Test Environment Setup" -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Green

# Get the script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TestPath = Join-Path $ScriptDir $TestDir

# Function to check if command exists
function Test-Command {
    param($Command)
    try {
        Get-Command $Command -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

# Function to wait for service to be ready
function Wait-ForService {
    param($Url, $MaxWaitSeconds = 60)
    
    Write-Host "Waiting for service at $Url to be ready..." -ForegroundColor Yellow
    $timeout = (Get-Date).AddSeconds($MaxWaitSeconds)
    
    do {
        try {
            $response = Invoke-RestMethod -Uri "$Url/health" -Method GET -TimeoutSec 5
            if ($response) {
                Write-Host "Service is ready!" -ForegroundColor Green
                return $true
            }
        } catch {
            Start-Sleep -Seconds 2
        }
    } while ((Get-Date) -lt $timeout)
    
    Write-Host "Service failed to start within $MaxWaitSeconds seconds" -ForegroundColor Red
    return $false
}

# Check prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Yellow

if (-not (Test-Command "step")) {
    Write-Error "Step CLI not found. Please install step-cli first."
}

if (-not (Test-Command "docker")) {
    Write-Error "Docker not found. Please install Docker first."
}

Write-Host "Prerequisites check passed!" -ForegroundColor Green

# Setup directories
Write-Host "Setting up test directories..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path "$TestPath\step-ca" -Force | Out-Null
New-Item -ItemType Directory -Path "$TestPath\dummy-certs" -Force | Out-Null
New-Item -ItemType Directory -Path "$TestPath\client-certs" -Force | Out-Null
New-Item -ItemType Directory -Path "$TestPath\logs" -Force | Out-Null

# Generate Step CA configuration if it doesn't exist
$StepCAPath = Join-Path $TestPath "step-ca"
$CAConfigPath = Join-Path $StepCAPath "config"

if ($SetupAll -or -not (Test-Path "$CAConfigPath\ca.json")) {
    Write-Host "Initializing Step CA..." -ForegroundColor Yellow
    
    # Initialize Step CA
    $env:STEPPATH = $StepCAPath
    
    # Remove existing CA if present
    if (Test-Path $CAConfigPath) {
        Remove-Item $CAConfigPath -Recurse -Force
    }
    
    # Initialize new CA
    step ca init --name="Test-CA" --dns="localhost,step-ca,127.0.0.1" --address=":9000" --provisioner="admin" --password-file=<(echo "testpassword") --provisioner-password-file=<(echo "adminpassword")
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Step CA initialized successfully!" -ForegroundColor Green
        
        # Get CA fingerprint for later use
        $fingerprint = step certificate fingerprint "$CAConfigPath\certs\root_ca.crt"
        Write-Host "CA Fingerprint: $fingerprint" -ForegroundColor Cyan
        
        # Save fingerprint to file for easy access
        $fingerprint | Out-File -FilePath "$TestPath\ca-fingerprint.txt" -Encoding UTF8
    } else {
        Write-Error "Failed to initialize Step CA"
    }
}

# Create docker-compose for test environment
Write-Host "Creating test docker-compose configuration..." -ForegroundColor Yellow

$dockerCompose = @"
version: '3.8'

services:
  step-ca-test:
    image: smallstep/step-ca:latest
    container_name: step-ca-test
    ports:
      - "9000:9000"
    volumes:
      - ./step-ca:/home/step
    environment:
      - DOCKER_STEPCA_INIT_NAME=Test-CA
      - DOCKER_STEPCA_INIT_DNS_NAMES=localhost,step-ca-test,127.0.0.1
      - DOCKER_STEPCA_INIT_REMOTE_MANAGEMENT=true
      - DOCKER_STEPCA_INIT_PASSWORD=testpassword
      - DOCKER_STEPCA_INIT_PROVISIONER_PASSWORD=adminpassword
    networks:
      - test-network
    healthcheck:
      test: ["CMD", "step", "ca", "health", "--ca-url", "https://localhost:9000", "--root", "/home/step/certs/root_ca.crt"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s

  cert-renewal-test:
    build:
      context: ..
      dockerfile: Dockerfile
    container_name: cert-renewal-test
    depends_on:
      step-ca-test:
        condition: service_healthy
    volumes:
      - ./test-config:/app/config
      - ./client-certs:/app/certs
      - ./logs:/app/logs
    environment:
      - CERT_RENEWAL_STEP_CA__CA_URL=https://step-ca-test:9000
      - CERT_RENEWAL_STEP_CA__PROVISIONER_NAME=admin
      - CERT_RENEWAL_STEP_CA__PROVISIONER_PASSWORD=adminpassword
      - CERT_RENEWAL_LOG_LEVEL=DEBUG
      - CERT_RENEWAL_CHECK_INTERVAL_MINUTES=2
    networks:
      - test-network
    command: ["tail", "-f", "/dev/null"]  # Keep container running for testing

networks:
  test-network:
    driver: bridge
"@

$dockerCompose | Out-File -FilePath "$TestPath\docker-compose.test.yml" -Encoding UTF8

# Create test configuration
Write-Host "Creating test configuration..." -ForegroundColor Yellow

$testConfig = @"
# Test Configuration for Certificate Renewal Service

# Service Settings
check_interval_minutes: 2  # Fast checking for testing
log_level: DEBUG
log_file: logs/cert_renewal_test.log
cert_storage_path: certs

# Renewal Threshold Settings (shorter for testing)
default_renewal_threshold_days: 5     # Short for testing
emergency_renewal_threshold_days: 1   # Very short for testing
warning_threshold_days: 3             # Short for testing

# Step CA Configuration
step_ca:
  protocol: "JWK"
  ca_url: "https://localhost:9000"
  ca_fingerprint: "REPLACE_WITH_ACTUAL_FINGERPRINT"
  provisioner_name: "admin"
  provisioner_password: "adminpassword"
  root_cert_path: "test/step-ca/certs/root_ca.crt"
  
  # CRL settings
  crl_enabled: true
  crl_cache_dir: "certs/crl"
  crl_refresh_hours: 1

# Test Certificates to Monitor
certificates:
  - name: "test-web-server"
    cert_path: "certs/test-web-server.crt"
    key_path: "certs/test-web-server.key"
    renewal_threshold_days: 3
    subject: "test-web.local"
    sans:
      - "www.test-web.local"
      - "api.test-web.local"
  
  - name: "test-api-server"
    cert_path: "certs/test-api-server.crt"
    key_path: "certs/test-api-server.key"
    renewal_threshold_days: 5
    subject: "test-api.local"
    sans:
      - "api-v2.test-web.local"
      
  - name: "test-expiring-soon"
    cert_path: "certs/test-expiring-soon.crt"
    key_path: "certs/test-expiring-soon.key"
    renewal_threshold_days: 2
    subject: "expiring.test.local"

# Example configuration with EST protocol (commented out)
# step_ca:
#   protocol: "EST"
#   ca_url: "https://localhost:8443/.well-known/est"
#   est_username: "testuser"
#   est_password: "testpass"
"@

New-Item -ItemType Directory -Path "$TestPath\test-config" -Force | Out-Null
$testConfig | Out-File -FilePath "$TestPath\test-config\config.yaml" -Encoding UTF8

# Create dummy certificate generation script
Write-Host "Creating dummy certificate generation script..." -ForegroundColor Yellow

$dummyCertScript = @"
#!/usr/bin/env python3
"""
Generate dummy certificates for testing the certificate renewal service.
"""
import os
import sys
from datetime import datetime, timedelta
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

def generate_ca_certificate():
    """Generate a dummy CA certificate and private key."""
    print("Generating dummy CA certificate...")
    
    # Generate private key
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048
    )
    
    # Certificate details
    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
        x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, "Test State"),
        x509.NameAttribute(NameOID.LOCALITY_NAME, "Test City"),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Test CA Organization"),
        x509.NameAttribute(NameOID.COMMON_NAME, "Test CA"),
    ])
    
    # Create certificate
    cert = x509.CertificateBuilder().subject_name(
        subject
    ).issuer_name(
        issuer
    ).public_key(
        private_key.public_key()
    ).serial_number(
        x509.random_serial_number()
    ).not_valid_before(
        datetime.utcnow()
    ).not_valid_after(
        datetime.utcnow() + timedelta(days=365 * 5)  # 5 years
    ).add_extension(
        x509.BasicConstraints(ca=True, path_length=None),
        critical=True,
    ).add_extension(
        x509.KeyUsage(
            key_cert_sign=True,
            crl_sign=True,
            digital_signature=False,
            key_encipherment=False,
            key_agreement=False,
            data_encipherment=False,
            content_commitment=False,
            encipher_only=False,
            decipher_only=False
        ),
        critical=True,
    ).sign(private_key, hashes.SHA256())
    
    return cert, private_key

def generate_certificate(subject_name, ca_cert, ca_key, sans=None, days_valid=30):
    """Generate a certificate signed by the CA."""
    print(f"Generating certificate for {subject_name} (valid for {days_valid} days)...")
    
    # Generate private key
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048
    )
    
    # Certificate subject
    subject = x509.Name([
        x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
        x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, "Test State"),
        x509.NameAttribute(NameOID.LOCALITY_NAME, "Test City"),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Test Organization"),
        x509.NameAttribute(NameOID.COMMON_NAME, subject_name),
    ])
    
    # Create certificate builder
    builder = x509.CertificateBuilder().subject_name(
        subject
    ).issuer_name(
        ca_cert.subject
    ).public_key(
        private_key.public_key()
    ).serial_number(
        x509.random_serial_number()
    ).not_valid_before(
        datetime.utcnow()
    ).not_valid_after(
        datetime.utcnow() + timedelta(days=days_valid)
    ).add_extension(
        x509.BasicConstraints(ca=False, path_length=None),
        critical=True,
    ).add_extension(
        x509.KeyUsage(
            digital_signature=True,
            key_encipherment=True,
            key_agreement=False,
            key_cert_sign=False,
            crl_sign=False,
            data_encipherment=False,
            content_commitment=False,
            encipher_only=False,
            decipher_only=False
        ),
        critical=True,
    )
    
    # Add SANs if provided
    if sans:
        san_list = [x509.DNSName(san) for san in sans]
        builder = builder.add_extension(
            x509.SubjectAlternativeName(san_list),
            critical=False,
        )
    
    # Sign certificate
    cert = builder.sign(ca_key, hashes.SHA256())
    
    return cert, private_key

def save_certificate(cert, key, cert_path, key_path):
    """Save certificate and key to files."""
    os.makedirs(os.path.dirname(cert_path), exist_ok=True)
    os.makedirs(os.path.dirname(key_path), exist_ok=True)
    
    # Save certificate
    with open(cert_path, 'wb') as f:
        f.write(cert.public_bytes(serialization.Encoding.PEM))
    
    # Save private key
    with open(key_path, 'wb') as f:
        f.write(key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        ))
    
    # Set appropriate permissions
    os.chmod(cert_path, 0o644)
    os.chmod(key_path, 0o600)
    
    print(f"Saved certificate: {cert_path}")
    print(f"Saved private key: {key_path}")

def main():
    """Generate dummy certificates for testing."""
    base_dir = "test/dummy-certs"
    
    # Generate CA certificate
    ca_cert, ca_key = generate_ca_certificate()
    save_certificate(ca_cert, ca_key, f"{base_dir}/ca.crt", f"{base_dir}/ca.key")
    
    # Generate test certificates with different expiration times
    certificates = [
        {
            "name": "test-web-server",
            "subject": "test-web.local",
            "sans": ["www.test-web.local", "api.test-web.local"],
            "days": 10  # Expires in 10 days - should trigger renewal
        },
        {
            "name": "test-api-server", 
            "subject": "test-api.local",
            "sans": ["api-v2.test-web.local"],
            "days": 20  # Expires in 20 days
        },
        {
            "name": "test-expiring-soon",
            "subject": "expiring.test.local",
            "sans": None,
            "days": 2   # Expires in 2 days - emergency renewal
        },
        {
            "name": "test-valid-long",
            "subject": "valid.test.local",
            "sans": ["valid-api.test.local"],
            "days": 60  # Expires in 60 days - should not renew
        },
        {
            "name": "test-already-expired",
            "subject": "expired.test.local", 
            "sans": None,
            "days": -1  # Already expired
        }
    ]
    
    for cert_info in certificates:
        cert, key = generate_certificate(
            cert_info["subject"],
            ca_cert,
            ca_key,
            cert_info["sans"],
            cert_info["days"]
        )
        
        cert_path = f"{base_dir}/{cert_info['name']}.crt"
        key_path = f"{base_dir}/{cert_info['name']}.key"
        
        save_certificate(cert, key, cert_path, key_path)
    
    print("\nDummy certificates generated successfully!")
    print("Use these for testing the certificate renewal service.")
    print(f"CA certificate: {base_dir}/ca.crt")

if __name__ == "__main__":
    main()
"@

$dummyCertScript | Out-File -FilePath "$TestPath\generate_dummy_certs.py" -Encoding UTF8

# Create test runner script
$testRunnerScript = @"
#!/usr/bin/env python3
"""
Test runner for certificate renewal service.
"""
import subprocess
import sys
import time
import json
import os

def run_command(cmd, cwd=None):
    """Run a command and return the result."""
    print(f"Running: {' '.join(cmd)}")
    try:
        result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
        return result
    except Exception as e:
        print(f"Error running command: {e}")
        return None

def test_service_initialization():
    """Test service initialization."""
    print("\n=== Testing Service Initialization ===")
    
    result = run_command(["python", "main.py", "--config", "test/test-config/config.yaml", "init"])
    
    if result and result.returncode == 0:
        print("✓ Service initialization successful")
        return True
    else:
        print("✗ Service initialization failed")
        if result:
            print(f"Error: {result.stderr}")
        return False

def test_certificate_status():
    """Test certificate status checking."""
    print("\n=== Testing Certificate Status ===")
    
    result = run_command(["python", "main.py", "--config", "test/test-config/config.yaml", "status", "--format", "json"])
    
    if result and result.returncode == 0:
        try:
            status_data = json.loads(result.stdout)
            print(f"✓ Found {status_data['total_certificates']} certificates")
            print(f"  - {status_data['summary']['valid_certificates']} valid")
            print(f"  - {status_data['summary']['certificates_needing_renewal']} need renewal")
            return True
        except json.JSONDecodeError:
            print("✗ Failed to parse status JSON")
            return False
    else:
        print("✗ Certificate status check failed")
        if result:
            print(f"Error: {result.stderr}")
        return False

def test_certificate_renewal():
    """Test certificate renewal."""
    print("\n=== Testing Certificate Renewal ===")
    
    result = run_command(["python", "main.py", "--config", "test/test-config/config.yaml", "check"])
    
    if result and result.returncode == 0:
        print("✓ Certificate renewal check successful")
        return True
    else:
        print("✗ Certificate renewal check failed")
        if result:
            print(f"Error: {result.stderr}")
        return False

def main():
    """Run all tests."""
    print("Certificate Renewal Service - Test Runner")
    print("=" * 50)
    
    tests = [
        test_service_initialization,
        test_certificate_status,
        test_certificate_renewal
    ]
    
    passed = 0
    failed = 0
    
    for test in tests:
        try:
            if test():
                passed += 1
            else:
                failed += 1
        except Exception as e:
            print(f"Test failed with exception: {e}")
            failed += 1
        
        time.sleep(1)  # Brief pause between tests
    
    print(f"\n=== Test Results ===")
    print(f"Passed: {passed}")
    print(f"Failed: {failed}")
    print(f"Total:  {len(tests)}")
    
    if failed == 0:
        print("🎉 All tests passed!")
        return 0
    else:
        print("❌ Some tests failed!")
        return 1

if __name__ == "__main__":
    sys.exit(main())
"@

$testRunnerScript | Out-File -FilePath "$TestPath\test_runner.py" -Encoding UTF8

# Create README for test environment
$testReadme = @"
# Test Environment for Certificate Renewal Service

This directory contains a complete test environment for the certificate renewal service.

## Quick Start

### 1. Setup Test Environment
```powershell
.\setup-test-env.ps1 -SetupAll
```

### 2. Generate Dummy Certificates
```powershell
python test\generate_dummy_certs.py
```

### 3. Start Step CA (Docker)
```powershell
cd test
docker-compose -f docker-compose.test.yml up -d step-ca-test
```

### 4. Update Configuration
Update the CA fingerprint in `test/test-config/config.yaml`:
```powershell
# Get fingerprint
step certificate fingerprint test/step-ca/certs/root_ca.crt

# Update config.yaml with the fingerprint
```

### 5. Run Tests
```powershell
python test\test_runner.py
```

## Test Components

### Step CA Server
- **URL**: https://localhost:9000
- **Provisioner**: admin
- **Password**: adminpassword
- **Docker container**: step-ca-test

### Dummy Certificates
Generated certificates with different expiration times:
- `test-web-server` - expires in 10 days
- `test-api-server` - expires in 20 days  
- `test-expiring-soon` - expires in 2 days (emergency)
- `test-valid-long` - expires in 60 days
- `test-already-expired` - already expired

### Test Configuration
- **Check interval**: 2 minutes (fast for testing)
- **Log level**: DEBUG
- **Renewal thresholds**: Short for testing (1-5 days)

## Manual Testing

### Initialize Service
```powershell
python main.py --config test/test-config/config.yaml init
```

### Check Certificate Status
```powershell
python main.py --config test/test-config/config.yaml status
```

### Run Single Check
```powershell
python main.py --config test/test-config/config.yaml check
```

### Start Daemon Mode
```powershell
python main.py --config test/test-config/config.yaml daemon
```

### Test CRL Functionality
```powershell
python main.py --config test/test-config/config.yaml crl
```

## Docker Testing

### Start Complete Test Environment
```powershell
cd test
docker-compose -f docker-compose.test.yml up -d
```

### View Logs
```powershell
docker-compose -f docker-compose.test.yml logs -f cert-renewal-test
```

### Execute Commands in Container
```powershell
docker exec -it cert-renewal-test python main.py status
```

## Troubleshooting

### Step CA Not Starting
1. Check if port 9000 is available
2. Verify Docker is running
3. Check container logs: `docker logs step-ca-test`

### Certificate Generation Fails
1. Ensure Python cryptography library is installed
2. Check write permissions in test directory
3. Verify Step CLI is installed and accessible

### Service Connection Issues
1. Verify CA fingerprint in config matches actual fingerprint
2. Check network connectivity to Step CA
3. Ensure provisioner credentials are correct

## File Structure
```
test/
├── setup-test-env.ps1           # Environment setup script
├── generate_dummy_certs.py      # Dummy certificate generator
├── test_runner.py               # Automated test runner
├── docker-compose.test.yml      # Docker test environment
├── step-ca/                     # Step CA data directory
├── dummy-certs/                 # Generated dummy certificates
├── client-certs/                # Client certificates for testing
├── test-config/                 # Test configuration files
└── logs/                        # Test logs
```
"@

$testReadme | Out-File -FilePath "$TestPath\README.md" -Encoding UTF8

# Generate dummy certificates if requested
if ($GenerateDummyCerts -or $SetupAll) {
    Write-Host "Generating dummy certificates..." -ForegroundColor Yellow
    
    try {
        python "$TestPath\generate_dummy_certs.py"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Dummy certificates generated successfully!" -ForegroundColor Green
        } else {
            Write-Warning "Failed to generate dummy certificates. Run manually: python test\generate_dummy_certs.py"
        }
    } catch {
        Write-Warning "Failed to generate dummy certificates: $($_.Exception.Message)"
    }
}

# Start Step CA if requested
if ($StartStepCA -or $SetupAll) {
    Write-Host "Starting Step CA test server..." -ForegroundColor Yellow
    
    Set-Location $TestPath
    try {
        docker-compose -f docker-compose.test.yml up -d step-ca-test
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Step CA container started. Waiting for it to be ready..." -ForegroundColor Yellow
            
            if (Wait-ForService "https://localhost:9000" 120) {
                Write-Host "Step CA is ready for testing!" -ForegroundColor Green
                
                # Get and display CA fingerprint
                Start-Sleep -Seconds 5  # Give it a moment to fully initialize
                try {
                    $fingerprint = step certificate fingerprint "$TestPath\step-ca\certs\root_ca.crt"
                    Write-Host "CA Fingerprint: $fingerprint" -ForegroundColor Cyan
                    Write-Host "Update this fingerprint in test/test-config/config.yaml" -ForegroundColor Yellow
                } catch {
                    Write-Warning "Could not get CA fingerprint. Check Step CA initialization."
                }
            }
        } else {
            Write-Warning "Failed to start Step CA container"
        }
    } catch {
        Write-Warning "Failed to start Step CA: $($_.Exception.Message)"
    } finally {
        Set-Location $ScriptDir
    }
}

Write-Host "`nTest environment setup complete!" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Generate dummy certificates: python test\generate_dummy_certs.py" -ForegroundColor White
Write-Host "2. Start Step CA: cd test && docker-compose -f docker-compose.test.yml up -d" -ForegroundColor White
Write-Host "3. Update CA fingerprint in test/test-config/config.yaml" -ForegroundColor White
Write-Host "4. Run tests: python test\test_runner.py" -ForegroundColor White
Write-Host "`nFor detailed instructions, see test\README.md" -ForegroundColor Cyan