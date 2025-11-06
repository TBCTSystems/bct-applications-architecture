# ECA PoC - Frequently Asked Questions

**Last Updated**: 2025-11-06
**Version**: 2.0

## Table of Contents

- [Quick Troubleshooting](#quick-troubleshooting)
- [Installation & Setup](#installation--setup)
- [Agent Issues](#agent-issues)
- [Certificate Issues](#certificate-issues)
- [Network & Connectivity](#network--connectivity)
- [Docker & Container Issues](#docker--container-issues)
- [Testing & Validation](#testing--validation)
- [Performance & Resource Usage](#performance--resource-usage)
- [Security & Secrets](#security--secrets)
- [Platform-Specific Issues](#platform-specific-issues)
- [Getting Help](#getting-help)

---

## Quick Troubleshooting

### The 5-Minute Debug Checklist

When something goes wrong, run through this checklist:

1. ✅ **Are all services running?**
   ```bash
   docker compose ps
   # All services should show "Up" or "running"
   ```

2. ✅ **Are core services healthy?**
   ```bash
   docker inspect --format='{{.State.Health.Status}}' eca-pki
   docker inspect --format='{{.State.Health.Status}}' eca-openxpki-db
   # Both should show "healthy"
   ```

3. ✅ **Do endpoints respond?**
   ```bash
   curl -k https://localhost:4210/health
   # Should return: {"status":"ok"}
   ```

4. ✅ **Are there obvious errors in logs?**
   ```bash
   docker compose logs --tail=50 acme-agent est-agent pki
   # Look for ERROR or FATAL level messages
   ```

5. ✅ **Are volumes initialized?**
   ```bash
   docker volume ls | grep -E "pki-data|server-certs|client-certs"
   # All three should exist
   ```

If all checks pass but issue persists, see detailed troubleshooting below.

---

## Installation & Setup

### Q: I get "Docker daemon is not running" error

**Symptoms**:
```
Cannot connect to the Docker daemon at unix:///var/run/docker.sock.
Is the docker daemon running?
```

**Solutions**:

**Linux**:
```bash
sudo systemctl start docker
sudo systemctl enable docker  # Auto-start on boot
```

**macOS**:
- Open Docker Desktop application
- Wait for "Docker Desktop is running" status

**Windows**:
- Open Docker Desktop
- Enable WSL 2 backend if using WSL

**Verify Docker is running**:
```bash
docker ps
# Should return empty list or running containers, not an error
```

---

### Q: init-volumes.sh fails with "step: command not found"

**Symptoms**:
```bash
./init-volumes.sh
init-volumes.sh: line 42: step: command not found
```

**Cause**: step CLI not installed.

**Solutions**:

**macOS**:
```bash
brew install step
```

**Linux (Ubuntu/Debian)**:
```bash
wget https://dl.smallstep.com/cli/docs-ca-install/latest/step-cli_amd64.deb
sudo dpkg -i step-cli_amd64.deb
```

**Linux (RHEL/CentOS)**:
```bash
wget https://dl.smallstep.com/cli/docs-ca-install/latest/step-cli_amd64.rpm
sudo rpm -i step-cli_amd64.rpm
```

**Verify installation**:
```bash
step version
# Should print version number
```

---

### Q: integration-test.sh fails with "Pester module not found"

**Symptoms**:
```
PowerShell module 'Pester' not found
```

**Cause**: Pester testing framework not installed.

**Solution**:
```bash
# Install Pester 5.x
pwsh -Command "Install-Module -Name Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force"

# Verify installation
pwsh -Command "Get-Module -ListAvailable Pester"
```

---

### Q: Volume initialization fails with "permission denied"

**Symptoms**:
```
Error: failed to copy PKI data to volume: permission denied
```

**Causes**:
1. Docker running as non-root without proper permissions
2. SELinux blocking volume access (Linux)
3. Volume owned by different user

**Solutions**:

**Add user to docker group** (Linux):
```bash
sudo usermod -aG docker $USER
newgrp docker  # Activate group without logout
```

**Disable SELinux temporarily** (RHEL/CentOS):
```bash
sudo setenforce 0  # Temporary
# OR edit /etc/selinux/config for permanent change
```

**Fix volume permissions**:
```bash
# Remove volume and recreate
docker volume rm pki-data
./init-volumes.sh
```

---

### Q: "Volume is in use" error when reinitializing

**Symptoms**:
```
Error response from daemon: remove pki-data: volume is in use
```

**Cause**: Containers are still running and using the volume.

**Solutions**:

**Option 1: Use integration-test.sh (recommended)**:
```bash
./integration-test.sh --clean
# Script will prompt to stop containers automatically
```

**Option 2: Stop containers manually**:
```bash
docker compose down -v
./init-volumes.sh
```

**Option 3: Force remove** (⚠️ DESTRUCTIVE):
```bash
docker compose down
docker volume rm pki-data --force
```

---

## Agent Issues

### Q: ACME agent keeps failing renewal

**Symptoms**:
```
[ERROR] ACME renewal failed: HTTP-01 challenge validation failed
[ERROR] Retry attempt 1/3 failed
```

**Common Causes & Solutions**:

#### 1. Target server not accessible from PKI service

**Diagnosis**:
```bash
# Check if PKI can reach target-server
docker exec eca-pki curl -v http://target-server:4212/.well-known/acme-challenge/test
```

**Solution**: Verify network connectivity:
```bash
# Both should be on same network
docker network inspect eca-poc-network
```

#### 2. NGINX not serving challenge directory

**Diagnosis**:
```bash
# Check NGINX configuration
docker exec eca-target-server nginx -T | grep acme-challenge
```

**Solution**: Verify NGINX config includes:
```nginx
location /.well-known/acme-challenge/ {
    root /var/www/challenges;
}
```

#### 3. Challenge files not being written

**Diagnosis**:
```bash
# Check if volume is mounted
docker inspect eca-acme-agent | grep -A 10 Mounts
```

**Solution**: Verify `challenge` volume is mounted in both ACME agent and target-server.

#### 4. Certificate already exists and is valid

**Not an error**: Agent skips renewal if certificate is still valid (>33% lifetime remaining).

**Force renewal for testing**:
```yaml
environment:
  FORCE_RENEWAL: true  # Forces renewal on next check
```

---

### Q: EST agent fails initial enrollment

**Symptoms**:
```
[ERROR] EST enrollment failed: unable to authenticate with bootstrap token
[ERROR] Server returned 401 Unauthorized
```

**Common Causes & Solutions**:

#### 1. Invalid bootstrap certificate

**Diagnosis**:
```bash
# Check if bootstrap certificate exists and is valid
docker exec eca-est-agent ls -la /home/step/bootstrap-certs/
docker exec eca-est-agent openssl x509 -in /home/step/bootstrap-certs/bootstrap-client.pem -noout -dates
```

**Solution**: Regenerate bootstrap certificates:
```bash
./init-volumes.sh  # Recreates bootstrap certs
```

#### 2. OpenXPKI server not ready

**Diagnosis**:
```bash
# Check OpenXPKI server health
docker compose logs openxpki-server | grep -i error
curl -k https://localhost:4222/.well-known/est/cacerts
```

**Solution**: Wait for OpenXPKI to fully initialize (can take 30-60 seconds):
```bash
docker compose logs -f openxpki-server
# Wait for "OpenXPKI server ready" message
```

#### 3. EST provisioner not configured

**Diagnosis**:
```bash
# Check if EST provisioner exists
docker exec eca-pki step ca provisioner list
```

**Solution**: Recreate PKI volume with EST provisioner:
```bash
./integration-test.sh --clean
```

---

### Q: Agent check loop not running

**Symptoms**:
- No log output from agent
- Certificate expires without renewal attempt
- Agent container shows "Up" but no activity

**Diagnosis**:
```bash
# Check agent logs for startup errors
docker compose logs acme-agent | head -50

# Check if agent process is running
docker exec eca-acme-agent ps aux | grep pwsh
```

**Common Causes**:

#### 1. Startup error causing immediate exit

**Solution**: Check logs for initialization errors:
```bash
docker compose logs acme-agent | grep -i "error\|fatal"
```

#### 2. Infinite sleep due to misconfiguration

**Solution**: Verify `CHECK_INTERVAL_SECONDS` is set:
```bash
docker exec eca-acme-agent printenv | grep CHECK_INTERVAL
```

#### 3. Agent waiting for manual trigger

**Solution**: Check if `FORCE_RENEWAL` is set to trigger immediate renewal:
```bash
docker compose restart acme-agent
docker compose logs -f acme-agent
# Should see "Starting check loop" within 10 seconds
```

---

## Certificate Issues

### Q: Certificate has wrong domain name

**Symptoms**:
```
SSL certificate problem: certificate subject name 'target-server' does not match 'localhost'
```

**Cause**: Certificate CN/SAN doesn't match requested hostname.

**Solution**: Update `DOMAIN_NAME` environment variable:

```yaml
acme-agent:
  environment:
    DOMAIN_NAME: localhost,target-server  # Multiple SANs
```

Then force renewal:
```bash
docker compose restart acme-agent
```

---

### Q: Certificate is expired

**Symptoms**:
```
curl: (60) SSL certificate problem: certificate has expired
```

**Diagnosis**:
```bash
# Check certificate expiry
docker run --rm -v server-certs:/certs alpine \
  openssl x509 -in /certs/server.crt -noout -dates

# Check current time
date -u
```

**Solutions**:

#### Short-term: Force immediate renewal
```bash
# Set FORCE_RENEWAL and restart agent
docker compose stop acme-agent
docker compose run --rm -e FORCE_RENEWAL=true acme-agent
```

#### Long-term: Adjust renewal threshold
```yaml
environment:
  RENEWAL_THRESHOLD_PERCENT: 50  # Renew earlier (at 50% lifetime)
```

---

### Q: CRL validation failing

**Symptoms**:
```
[WARN] CRL download failed: connection refused
[WARN] Proceeding with renewal (fail-open mode)
```

**Diagnosis**:
```bash
# Check if CRL endpoint is accessible
curl -v http://localhost:4211/crl/ca.crl

# Check CRL service logs
docker compose logs crl-server
```

**Solutions**:

#### CRL service not running
```bash
docker compose up -d crl-server
```

#### CRL URL misconfigured
```yaml
environment:
  CRL_URL: http://pki:4211/crl/ca.crl  # Use internal Docker network
```

#### Disable CRL validation (not recommended for production)
```yaml
environment:
  CRL_ENABLED: false
```

---

### Q: Certificate chain validation fails

**Symptoms**:
```
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

**Cause**: Client doesn't trust the CA root certificate.

**Solutions**:

#### Trust CA certificate in browser
1. Download root CA cert:
   ```bash
   docker run --rm -v pki-data:/pki alpine cat /pki/certs/root_ca.crt > root_ca.crt
   ```
2. Import `root_ca.crt` into browser/system trust store

#### Use curl with CA cert
```bash
curl --cacert root_ca.crt https://localhost:4213/
```

#### Skip verification (testing only)
```bash
curl -k https://localhost:4213/  # -k skips certificate verification
```

---

## Network & Connectivity

### Q: "Connection refused" errors

**Symptoms**:
```
curl: (7) Failed to connect to localhost port 4210: Connection refused
```

**Diagnosis**:
```bash
# Check if port is exposed
docker compose ps | grep 4210

# Check if service is listening
docker exec eca-pki netstat -ln | grep 4210

# Check firewall rules (Linux)
sudo iptables -L -n | grep 4210
```

**Solutions**:

#### Service not started
```bash
docker compose up -d pki
```

#### Port not exposed in docker-compose.yml
```yaml
services:
  pki:
    ports:
      - "4210:9000"  # Expose internal port 9000 as 4210
```

#### Firewall blocking port
```bash
# Ubuntu/Debian
sudo ufw allow 4210/tcp

# RHEL/CentOS
sudo firewall-cmd --add-port=4210/tcp --permanent
sudo firewall-cmd --reload
```

---

### Q: DNS resolution failing inside containers

**Symptoms**:
```
[ERROR] Could not resolve host: pki
```

**Diagnosis**:
```bash
# Test DNS resolution inside container
docker exec eca-acme-agent nslookup pki
docker exec eca-acme-agent getent hosts pki
```

**Solutions**:

#### Not on same Docker network
```bash
# Check networks
docker network inspect eca-poc-network

# Both services should appear in "Containers" section
```

#### Use Docker Compose network name
```yaml
services:
  acme-agent:
    networks:
      - eca-poc-network
  pki:
    networks:
      - eca-poc-network
```

#### Use IP address instead of hostname (workaround)
```bash
# Find IP address
docker inspect eca-pki | grep IPAddress

# Update agent config
PKI_URL: https://172.18.0.5:9000  # Use IP instead of 'pki'
```

---

### Q: Port conflicts with other services

**Symptoms**:
```
Error starting userland proxy: listen tcp4 0.0.0.0:4210: bind: address already in use
```

**Diagnosis**:
```bash
# Find what's using the port (Linux/macOS)
sudo lsof -i :4210

# Windows
netstat -ano | findstr :4210
```

**Solutions**:

#### Stop conflicting service
```bash
sudo systemctl stop <service-name>
```

#### Change ECA port mapping
```yaml
services:
  pki:
    ports:
      - "9000:9000"  # Use different external port
```

Then update agent configuration to use new port.

---

## Docker & Container Issues

### Q: Container keeps restarting

**Symptoms**:
```bash
docker compose ps
# Shows container status as "Restarting (1) 5 seconds ago"
```

**Diagnosis**:
```bash
# Check container logs
docker compose logs <service-name> | tail -100

# Check exit code
docker inspect <container-id> | grep ExitCode
```

**Common Exit Codes**:
- `0` - Clean exit (not an error)
- `1` - General error (check logs)
- `126` - Command cannot execute (permissions)
- `127` - Command not found
- `137` - Killed by OOM (out of memory)
- `139` - Segmentation fault

**Solutions**:

#### Out of memory (exit code 137)
Increase memory limit:
```yaml
deploy:
  resources:
    limits:
      memory: 1G  # Increase from 512M
```

#### Missing dependency (exit code 127)
Rebuild image:
```bash
docker compose build --no-cache <service-name>
```

#### Configuration error (exit code 1)
Check logs for specific error:
```bash
docker compose logs <service-name> | grep -i error
```

---

### Q: Cannot exec into container

**Symptoms**:
```bash
docker exec -it eca-acme-agent bash
# Error: executable file not found in $PATH
```

**Cause**: Alpine Linux uses `sh` not `bash`.

**Solution**:
```bash
# Use sh instead of bash
docker exec -it eca-acme-agent sh

# Or use PowerShell
docker exec -it eca-acme-agent pwsh
```

---

### Q: Volume data persists after docker compose down

**Expected behavior**: Named volumes persist by default.

**To remove volumes**:
```bash
# Remove volumes when stopping
docker compose down -v

# Or use integration test script
./integration-test.sh --clean
```

---

### Q: Image pull fails

**Symptoms**:
```
Error response from daemon: Get https://registry-1.docker.io/v2/: unauthorized
```

**Solutions**:

#### Docker Hub rate limit exceeded
Wait 6 hours or login to Docker Hub:
```bash
docker login
```

#### Network issue
Check internet connectivity:
```bash
ping registry-1.docker.io
```

#### Use mirror registry
```yaml
# Configure in ~/.docker/daemon.json
{
  "registry-mirrors": ["https://mirror.gcr.io"]
}
```

---

## Testing & Validation

### Q: Integration tests fail with timeout

**Symptoms**:
```
[ERROR] Timeout waiting for service 'pki' to become healthy
Test timed out after 300 seconds
```

**Solutions**:

#### Increase timeout
Edit `integration-test.sh`:
```bash
SERVICE_READY_TIMEOUT=300  # Increase from 60 to 300 seconds
```

#### Check service logs for startup errors
```bash
docker compose logs pki | grep -i error
```

#### Reduce services being tested
```bash
# Test only specific services
./integration-test.sh --validate-only  # Skip full integration tests
```

---

### Q: Pester tests fail with module errors

**Symptoms**:
```
Import-Module: Could not load module 'ConfigManager.psm1'
```

**Cause**: PowerShell module path not configured correctly.

**Solution**:
```bash
# Run tests from correct directory
cd poc/eca-est-acme-poc
./scripts/run-tests.sh

# Or set module path explicitly
export PSModulePath="$PWD/agents/common:$PSModulePath"
pwsh -Command "Invoke-Pester -Path ./tests"
```

---

### Q: CRL revocation tests fail

**Symptoms**:
```
[FAIL] CRL validation should detect revoked certificate
Expected: true, Actual: false
```

**Diagnosis**:
```bash
# Check if certificate is actually revoked
docker exec eca-pki step ca revoke --cert-pem=/path/to/cert.pem

# Check if CRL is updated
curl http://localhost:4211/crl/ca.crl | openssl crl -inform DER -text
```

**Solution**:
Wait for CRL regeneration (hourly by default) or force regeneration:
```bash
docker exec eca-pki step ca crl
```

---

## Performance & Resource Usage

### Q: High CPU usage from agents

**Diagnosis**:
```bash
# Check CPU usage
docker stats

# Check agent poll interval
docker exec eca-acme-agent printenv | grep CHECK_INTERVAL
```

**Solutions**:

#### Increase poll interval (reduce frequency)
```yaml
environment:
  CHECK_INTERVAL_SECONDS: 43200  # 12 hours instead of 6
```

#### Limit CPU usage
```yaml
deploy:
  resources:
    limits:
      cpus: '0.25'  # Max 25% of one core
```

---

### Q: High memory usage from Loki

**Diagnosis**:
```bash
docker stats eca-loki
# Check memory column
```

**Solutions**:

#### Reduce log retention
Edit `loki-config.yml`:
```yaml
table_manager:
  retention_period: 24h  # Reduce from 168h (7 days)
```

#### Limit memory
```yaml
deploy:
  resources:
    limits:
      memory: 256M  # Reduce from 512M
```

#### Disable Loki if not needed
```bash
docker compose stop loki grafana fluentd
```

---

### Q: Slow integration test execution

**Expected duration**: 3-4 minutes for first run, 2-3 minutes for subsequent runs.

**If slower**:

#### Use quick mode (skip init)
```bash
./integration-test.sh --quick
```

#### Run only specific test phases
```bash
./integration-test.sh --validate-only  # Skip tests, only validate endpoints
./integration-test.sh --test-only      # Skip startup, only run tests
```

#### Reduce test verbosity
Edit `integration-test.sh`:
```bash
LOG_LEVEL=ERROR  # Only show errors, not INFO/DEBUG
```

---

## Security & Secrets

### Q: How do I change default passwords?

**Default passwords in PoC**:
- Grafana: `admin` / `eca-admin`
- OpenXPKI DB root: `topsecret`
- OpenXPKI DB user: `openxpki` / `openxpki`

**Solution**: Edit `docker-compose.yml` before first startup:

```yaml
environment:
  # Grafana
  GF_SECURITY_ADMIN_PASSWORD: <your-secure-password>

  # OpenXPKI
  MYSQL_ROOT_PASSWORD: <your-secure-password>
  MYSQL_PASSWORD: <your-secure-password>
```

**If already started**, recreate containers:
```bash
docker compose down
# Edit docker-compose.yml
docker compose up -d
```

---

### Q: How do I secure bootstrap tokens?

**Current approach** (PoC): Bootstrap certificate files in volume.

**Production alternatives**:

#### Docker Secrets (Swarm)
```yaml
secrets:
  bootstrap_cert:
    file: ./secrets/bootstrap-client.pem

services:
  est-agent:
    secrets:
      - bootstrap_cert
    environment:
      EST_BOOTSTRAP_CERT_PATH: /run/secrets/bootstrap_cert
```

#### HashiCorp Vault
```bash
# Store in Vault
vault kv put secret/est-bootstrap cert=@bootstrap-client.pem

# Retrieve in agent startup script
vault kv get -field=cert secret/est-bootstrap > /tmp/bootstrap.pem
```

#### Environment variable with encryption
```bash
# Encrypt bootstrap cert
export BOOTSTRAP_CERT=$(cat bootstrap-client.pem | base64 | openssl enc -aes-256-cbc -a)

# Decrypt in agent
echo $BOOTSTRAP_CERT | openssl enc -aes-256-cbc -d -a | base64 -d > /tmp/bootstrap.pem
```

---

### Q: Are private keys encrypted?

**Current state** (PoC): Private keys stored **unencrypted** on Docker volumes.

**Why**: Simplicity for demonstration purposes.

**Production recommendations**:

#### Volume encryption (Linux)
```bash
# Use LUKS to encrypt volume backing store
cryptsetup luksFormat /dev/sdb1
cryptsetup open /dev/sdb1 encrypted-pki
mkfs.ext4 /dev/mapper/encrypted-pki
# Mount and use for Docker volumes
```

#### Cloud KMS integration
- AWS: Use KMS for key encryption
- Azure: Use Key Vault
- GCP: Use Cloud KMS

#### Hardware Security Modules (HSM)
- PKCS#11 integration with step-ca
- Store CA keys on HSM
- Agent keys can remain on encrypted volumes

---

## Platform-Specific Issues

### macOS

#### Q: Port 4230 not accessible on macOS

**Cause**: macOS firewall blocking incoming connections.

**Solution**:
```bash
# Allow Docker in firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /Applications/Docker.app
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /Applications/Docker.app
```

#### Q: File sharing permission errors

**Cause**: Docker Desktop file sharing restrictions.

**Solution**:
1. Open Docker Desktop
2. Preferences → Resources → File Sharing
3. Add project directory: `/Users/<username>/personal-scratchpad`
4. Apply & Restart

---

### Windows

#### Q: Line ending issues with shell scripts

**Symptoms**:
```
bash: ./integration-test.sh: /bin/bash^M: bad interpreter
```

**Cause**: CRLF line endings instead of LF.

**Solution**:
```bash
# Convert line endings (Git Bash / WSL)
dos2unix integration-test.sh init-volumes.sh

# Or configure Git to auto-convert
git config --global core.autocrlf input
```

#### Q: PowerShell execution policy blocks scripts

**Symptoms**:
```
cannot be loaded because running scripts is disabled on this system
```

**Solution**:
```powershell
# Allow current user to run scripts
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Or run script with bypass
powershell -ExecutionPolicy Bypass -File integration-test.ps1
```

---

### Linux

#### Q: SELinux blocking volume mounts

**Symptoms**:
```
Error: failed to mount volume: permission denied (SELinux)
```

**Solution**:
```bash
# Temporarily disable SELinux
sudo setenforce 0

# OR add SELinux context to volumes
chcon -Rt svirt_sandbox_file_t /var/lib/docker/volumes/pki-data

# OR disable SELinux permanently (not recommended)
sudo vi /etc/selinux/config
# Set: SELINUX=disabled
```

---

## Getting Help

### Before Opening an Issue

1. ✅ **Check this FAQ** for common solutions
2. ✅ **Run the 5-minute debug checklist** (top of this document)
3. ✅ **Search existing issues**: https://github.com/your-repo/issues
4. ✅ **Collect debug information**:
   ```bash
   # Collect system info
   docker version
   docker compose version
   step version
   pwsh --version

   # Collect logs
   docker compose logs > debug-logs.txt

   # Collect configuration
   docker compose config > debug-config.yml
   ```

---

### Opening an Issue

**Good issue template**:

```markdown
## Environment
- OS: Ubuntu 22.04 / macOS 13.0 / Windows 11
- Docker: 24.0.5
- Docker Compose: 2.20.0
- step CLI: 0.24.4
- PowerShell: 7.4.0

## Problem Description
Clear description of what's not working.

## Expected Behavior
What you expected to happen.

## Actual Behavior
What actually happened.

## Steps to Reproduce
1. Run `./integration-test.sh`
2. See error in ACME agent logs
3. ...

## Logs
```
[Paste relevant logs here]
```

## Additional Context
Any other relevant information.
```

---

### Community Resources

- **Documentation**: See README.md, ARCHITECTURE.md, TESTING.md, CONFIGURATION.md
- **GitHub Issues**: https://github.com/your-repo/issues
- **Discussions**: https://github.com/your-repo/discussions
- **Smallstep Docs**: https://smallstep.com/docs/
- **ACME RFC**: https://datatracker.ietf.org/doc/html/rfc8555
- **EST RFC**: https://datatracker.ietf.org/doc/html/rfc7030

---

### Debug Mode

Enable verbose logging across all components:

```yaml
# Edit docker-compose.yml
services:
  acme-agent:
    environment:
      LOG_LEVEL: DEBUG  # Change from INFO

  est-agent:
    environment:
      LOG_LEVEL: DEBUG

  pki:
    command: ["--debug"]  # Enable step-ca debug logging
```

Restart services:
```bash
docker compose down
docker compose up -d
docker compose logs -f
```

---

## Still Stuck?

If you've tried everything in this FAQ and still can't resolve your issue:

1. **Enable debug logging** (see above)
2. **Collect full logs**: `docker compose logs > full-debug.txt`
3. **Open an issue** with all debug information
4. **Be patient**: Maintainers will respond as time permits

**Remember**: This is a Proof of Concept for learning and demonstration. For production support, consider commercial PKI solutions or professional services.

---

**Related Documentation**:
- [README.md](README.md) - Quick start and overview
- [ARCHITECTURE.md](ARCHITECTURE.md) - System design and components
- [TESTING.md](TESTING.md) - Testing procedures and validation
- [CONFIGURATION.md](CONFIGURATION.md) - All configuration options
- [CERTIFICATES_101.md](CERTIFICATES_101.md) - PKI fundamentals
