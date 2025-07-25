# Certificate Troubleshooting Guide

## Issue: ACME HTTP-01 Challenge Failures

### Problem Description
If you see errors like:
```
"error":{"type":"urn:ietf:params:acme:error:connection","detail":"The server could not connect to validation target"}
```

This means step-ca cannot reach the certbot containers for ACME HTTP-01 validation.

### Root Cause
The step-ca container resolves `.localtest.me` domains to `127.0.0.1` (your host machine) instead of the Docker container IPs where the certbot HTTP servers are running.

### Solution Options

#### Option 1: Automatic Setup (Recommended)

**Linux/macOS:**
```bash
./scripts/setup-extra-hosts.sh
docker compose -f docker-compose.yml -f docker-compose.extra-hosts.yml up -d step-ca
```

**Windows:**
```powershell
.\scripts\setup-extra-hosts.ps1
docker compose -f docker-compose.yml -f docker-compose.extra-hosts.yml up -d step-ca
```

#### Option 2: Manual Configuration

1. **Find Container IPs:**
```bash
docker inspect certbot-device --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
docker inspect certbot-app --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
docker inspect certbot-mqtt --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
```

2. **Add to docker-compose.yml under step-ca service:**
```yaml
step-ca:
  # ... existing configuration ...
  extra_hosts:
    - "device.localtest.me:172.20.0.50"    # Use your actual IP
    - "app.localtest.me:172.20.0.60"       # Use your actual IP  
    - "mqtt.localtest.me:172.20.0.70"      # Use your actual IP
```

3. **Restart step-ca:**
```bash
docker compose up -d step-ca
```

#### Option 3: Use Static IPs (Default)

The docker-compose.yml already defines static IPs:
- certbot-device: 172.20.0.50
- certbot-app: 172.20.0.60  
- certbot-mqtt: 172.20.0.70

These should work in most environments unless you have IP conflicts.

### Verification

1. **Check step-ca can resolve domains:**
```bash
docker exec step-ca nslookup mqtt.localtest.me
# Should return the container IP, not 127.0.0.1
```

2. **Test HTTP connectivity:**
```bash
docker exec step-ca curl -v http://mqtt.localtest.me/.well-known/acme-challenge/test
# Should connect to the container IP
```

3. **Monitor certificate generation:**
```bash
docker exec certbot-mqtt /usr/local/bin/certificate-monitor.sh status
# Should show valid certificate after a few minutes
```

### Common Issues

#### Issue: "Could not resolve host"
- **Cause**: Domain not in step-ca's /etc/hosts
- **Fix**: Ensure extra_hosts is properly configured

#### Issue: "Connection refused"
- **Cause**: Certbot HTTP server not running
- **Fix**: Check certbot container logs and ensure port 80 is exposed

#### Issue: "Invalid IP address in add-host"
- **Cause**: Malformed extra_hosts syntax
- **Fix**: Ensure proper YAML formatting and valid IP addresses

### Environment-Specific Notes

#### Docker Desktop (Windows/macOS)
- Container IPs may change between restarts
- Use the automatic setup scripts for dynamic IP detection

#### Linux Docker Engine
- Static IPs are more stable
- Manual configuration usually works reliably

#### CI/CD Environments
- Use the automatic setup scripts in your pipeline
- Consider using Docker networks with custom DNS

### Advanced: Alternative Solutions

#### Option A: Custom Docker Network with DNS
```yaml
networks:
  cert-mgmt-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
    driver_opts:
      com.docker.network.bridge.name: cert-mgmt-br0
```

#### Option B: External DNS Resolution
- Set up local DNS server
- Configure step-ca to use custom DNS resolver

#### Option C: Use Container Names
- Modify certbot to use container hostnames instead of .localtest.me domains
- Requires changes to certificate domain configuration

### Testing Your Fix

After applying any solution:

1. **Restart affected services:**
```bash
docker compose restart step-ca certbot-mqtt certbot-device certbot-app
```

2. **Wait for certificate generation (1-2 minutes):**
```bash
watch docker exec certbot-mqtt /usr/local/bin/certificate-monitor.sh status
```

3. **Check all certificates:**
```bash
docker exec certbot-device /usr/local/bin/certificate-monitor.sh status
docker exec certbot-app /usr/local/bin/certificate-monitor.sh status
docker exec certbot-mqtt /usr/local/bin/certificate-monitor.sh status
```

4. **Test MQTT with certificates:**
```bash
docker compose restart mosquitto
docker compose up -d device-simulator
```

### Getting Help

If you're still having issues:

1. **Collect diagnostic information:**
```bash
docker compose ps
docker compose logs step-ca --tail=20
docker compose logs certbot-mqtt --tail=20
docker exec step-ca cat /etc/hosts
```

2. **Check network configuration:**
```bash
docker network inspect step-ca-poc_cert-mgmt-network
```

3. **Verify certificate files:**
```bash
docker exec certbot-mqtt ls -la /certs/
```

Include this information when reporting issues.