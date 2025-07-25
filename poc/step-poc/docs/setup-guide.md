# Setup Guide: Certificate Management PoC

## Prerequisites

Before starting the setup, ensure you have the following installed and configured:

### Required Software

1. **Docker Engine** (version 20.10 or later)
   - **Linux**: Follow [Docker Engine installation guide](https://docs.docker.com/engine/install/)
   - **macOS**: Install [Docker Desktop for Mac](https://docs.docker.com/desktop/mac/install/)
   - **Windows**: Install [Docker Desktop for Windows](https://docs.docker.com/desktop/windows/install/)

2. **Docker Compose** (version 2.0 or later)
   - Usually included with Docker Desktop
   - Linux users may need to install separately: [Docker Compose installation](https://docs.docker.com/compose/install/)

3. **Git** (for cloning the repository)
   - Download from [git-scm.com](https://git-scm.com/downloads)

### System Requirements

- **RAM**: Minimum 4GB, recommended 8GB
- **Disk Space**: At least 2GB free space
- **Network**: Internet connection for downloading Docker images
- **Permissions**: Administrative/root access for hosts file modification

### Verification Commands

Run these commands to verify your environment:

```bash
# Check Docker version
docker --version
# Expected output: Docker version 20.10.x or later

# Check Docker Compose version
docker-compose --version
# Expected output: Docker Compose version 2.x.x or later

# Verify Docker is running
docker ps
# Should return without errors (may show empty list)

# Check available disk space
df -h .
# Ensure at least 2GB free space
```

## Host File Configuration

### Why Host File Modification is Required

The PoC uses local domain names (`ca.localtest.me`, `mqtt.localtest.me`, `app.localtest.me`) for several critical reasons:

1. **Certificate Validation**: SSL/TLS certificates are issued for specific domain names. Using domain names instead of IP addresses ensures proper certificate validation.

2. **Real-world Simulation**: Production environments use domain names, not IP addresses. This setup mimics real deployment scenarios.

3. **Service Discovery**: While Docker provides internal DNS resolution, external access (from your browser or external tools) requires host file entries.

4. **Security Testing**: Domain-based certificates test the complete PKI chain, including Subject Alternative Names (SAN) validation.

### Host File Locations by Operating System

| Operating System | Host File Location |
|------------------|-------------------|
| **Linux** | `/etc/hosts` |
| **macOS** | `/etc/hosts` |
| **Windows** | `C:\Windows\System32\drivers\etc\hosts` |

### Required Host File Entries

Add the following lines to your hosts file:

```
# Certificate Management PoC - ACME Domain Resolution
127.0.0.1 ca.localtest.me
127.0.0.1 device.localtest.metest.me
127.0.0.1 app.localtest.metest.me
127.0.0.1 mqtt.localtest.metest.me
```

### Host File Modification Instructions

#### Linux and macOS

1. **Open Terminal**

2. **Edit the hosts file** (requires sudo privileges):
   ```bash
   sudo nano /etc/hosts
   ```
   
   Or using vim:
   ```bash
   sudo vim /etc/hosts
   ```

3. **Add the required entries** at the end of the file:
   ```
   # Certificate Management PoC - Local Domain Resolution
   127.0.0.1 ca.localtest.me
   127.0.0.1 mqtt.localtest.me
   127.0.0.1 app.localtest.me
   127.0.0.1 device.localtest.me
   127.0.0.1 localhost:3000
   ```

4. **Save and exit**:
   - nano: Press `Ctrl+X`, then `Y`, then `Enter`
   - vim: Press `Esc`, type `:wq`, press `Enter`

5. **Verify the changes**:
   ```bash
   ping ca.localtest.me
   # Should resolve to 127.0.0.1
   ```

#### Windows

1. **Open Command Prompt or PowerShell as Administrator**:
   - Right-click on "Command Prompt" or "PowerShell"
   - Select "Run as administrator"

2. **Navigate to the hosts file directory**:
   ```cmd
   cd C:\Windows\System32\drivers\etc
   ```

3. **Create a backup** (recommended):
   ```cmd
   copy hosts hosts.backup
   ```

4. **Edit the hosts file**:
   ```cmd
   notepad hosts
   ```

5. **Add the required entries** at the end of the file:
   ```
   # Certificate Management PoC - Local Domain Resolution
   127.0.0.1 ca.localtest.me
   127.0.0.1 mqtt.localtest.me
   127.0.0.1 app.localtest.me
   127.0.0.1 device.localtest.me
   127.0.0.1 localhost:3000
   ```

6. **Save the file** (Ctrl+S in Notepad)

7. **Verify the changes**:
   ```cmd
   ping ca.localtest.me
   ```

### Verification

After modifying the hosts file, verify the configuration:

```bash
# Test domain resolution
nslookup ca.localtest.me
# Should return 127.0.0.1

# Test all domains
ping -c 1 ca.localtest.me
ping -c 1 mqtt.localtest.metest.me
ping -c 1 app.localtest.metest.me
```

**Expected Output**:
```
PING ca.localtest.me (127.0.0.1): 56 data bytes
64 bytes from 127.0.0.1: icmp_seq=0 ttl=64 time=0.045 ms
```

## Project Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd certificate-management-poc
```

### 2. Verify Project Structure

Ensure the following directory structure exists:

```
certificate-management-poc/
├── docker-compose.yml
├── docker-compose.override.yml
├── config/
│   ├── step-ca/
│   ├── mosquitto/
│   ├── loki/
│   └── grafana/
├── docker/
│   └── certbot/
├── scripts/
├── docs/
└── README.md
```

### 3. Create Required Directories

Some directories may need to be created manually:

```bash
# Create log directories for development
mkdir -p logs/{step-ca,mosquitto,loki,grafana,certbot-device,certbot-app,certbot-mqtt}

# Create additional config directories if needed
mkdir -p config/grafana/dev
```

## Service Startup

### 1. Initial Infrastructure Startup

Start the core infrastructure services:

```bash
# Start all services in detached mode
docker-compose up -d

# Monitor startup progress
docker-compose logs -f
```

### 2. Verify Service Health

Check that all services are running and healthy:

```bash
# Check service status
docker-compose ps

# Expected output should show all services as "Up" and "healthy"
```

**Example healthy output**:
```
NAME                COMMAND                  SERVICE             STATUS              PORTS
certbot-app         "/usr/local/bin/cert…"   certbot-app         Up 2 minutes        
certbot-device      "/usr/local/bin/cert…"   certbot-device      Up 2 minutes        
certbot-mqtt        "/usr/local/bin/cert…"   certbot-mqtt        Up 2 minutes        
grafana             "/run.sh"                grafana             Up 2 minutes (healthy)   0.0.0.0:3000->3000/tcp
loki                "/usr/bin/loki -conf…"   loki                Up 2 minutes (healthy)   0.0.0.0:3100->3100/tcp
mosquitto           "/docker-entrypoint.…"   mosquitto           Up 2 minutes (healthy)   0.0.0.0:1883->1883/tcp, 0.0.0.0:8883->8883/tcp, 0.0.0.0:9001->9001/tcp
step-ca             "/usr/local/bin/step…"   step-ca             Up 2 minutes (healthy)   0.0.0.0:9000->9000/tcp
```

### 3. Service-Specific Verification

#### step-ca (Certificate Authority)

```bash
# Test CA health endpoint
curl -k https://ca.localtest.me:9000/health

# Expected response: {"status":"ok"}

# Download root CA certificate
curl -k https://ca.localtest.me:9000/root -o ca-cert.pem

# Verify certificate
openssl x509 -in ca-cert.pem -text -noout
```

#### Mosquitto (MQTT Broker)

```bash
# Test non-TLS connection (for initial verification)
docker exec mosquitto mosquitto_pub -h localhost -t test -m "hello world"

# Check MQTT logs
docker-compose logs mosquitto
```

#### Loki (Log Aggregation)

```bash
# Test Loki readiness
curl http://localhost:3100/ready

# Expected response: ready

# Check Loki metrics
curl http://localhost:3100/metrics
```

#### Grafana (Dashboard)

```bash
# Test Grafana health
curl http://localhost:3000/api/health

# Expected response: {"commit":"...","database":"ok","version":"..."}
```

### 4. Access Web Interfaces

Once all services are healthy, access the web interfaces:

- **Grafana Dashboard**: http://localhost:3000
  - Username: `admin`
  - Password: `admin` (or `devpassword` in development mode)

- **step-ca Health Check**: https://ca.localtest.me:9000/health
  - Note: You may see a security warning due to self-signed certificates

- **Loki API**: http://localhost:3100

## Certificate Verification

### 1. Wait for Initial Certificate Generation

The certbot containers will automatically request certificates from step-ca. This process may take 1-2 minutes after startup.

### 2. Check Certificate Status

```bash
# Check device certificate status
docker exec certbot-device /usr/local/bin/certificate-monitor.sh status

# Check application certificate status
docker exec certbot-app /usr/local/bin/certificate-monitor.sh status

# Check MQTT certificate status
docker exec certbot-mqtt /usr/local/bin/certificate-monitor.sh status
```

**Expected output** (example for device):
```json
{
  "status": "valid",
  "subject": "CN=device.localtest.me",
  "issuer": "CN=Certificate Management PoC CA",
  "not_before": "Jan  1 12:00:00 2024 GMT",
  "not_after": "Jan  1 12:10:00 2024 GMT",
  "serial": "123456789",
  "time_until_expiry_seconds": 480,
  "service_name": "device"
}
```

### 3. Monitor Certificate Renewal

Certificates are configured to renew every 5 minutes. Monitor the renewal process:

```bash
# Watch certbot logs for renewal activity
docker-compose logs -f certbot-device

# Expected log entries every 5 minutes showing renewal attempts
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Services Fail to Start

**Symptoms**: Services show "Exited" status or fail health checks

**Diagnosis**:
```bash
# Check service logs
docker-compose logs <service-name>

# Check Docker system resources
docker system df
docker system prune  # If low on space
```

**Solutions**:
- Ensure sufficient disk space (minimum 2GB)
- Verify Docker daemon is running
- Check for port conflicts: `netstat -tulpn | grep -E ':(3000|3100|9000|1883|8883|9001)'`

#### 2. Domain Names Don't Resolve

**Symptoms**: `ping ca.localtest.me` fails or returns wrong IP

**Diagnosis**:
```bash
# Check hosts file content
cat /etc/hosts | grep local  # Linux/macOS
type C:\Windows\System32\drivers\etc\hosts | findstr local  # Windows
```

**Solutions**:
- Verify hosts file entries are correct
- Restart network services (may be required on some systems)
- Check for DNS caching: `sudo dscacheutil -flushcache` (macOS)

#### 3. Certificate Generation Fails

**Symptoms**: Certbot containers show errors in logs

**Diagnosis**:
```bash
# Check step-ca logs
docker-compose logs step-ca

# Check certbot logs
docker-compose logs certbot-device
```

**Solutions**:
- Ensure step-ca is healthy before certbot starts
- Verify ACME endpoint accessibility: `curl -k https://ca.localtest.me:9000/acme/acme/directory`
- Check network connectivity between containers

#### 4. Grafana Shows No Data

**Symptoms**: Grafana dashboards are empty or show "No data"

**Diagnosis**:
```bash
# Check Loki connectivity from Grafana
docker exec grafana curl http://loki:3100/ready

# Verify log ingestion
curl http://localhost:3100/loki/api/v1/labels
```

**Solutions**:
- Verify Loki datasource configuration in Grafana
- Check that services are generating logs
- Restart Grafana: `docker-compose restart grafana`

#### 5. Permission Issues (Linux/macOS)

**Symptoms**: "Permission denied" errors when modifying hosts file

**Solutions**:
```bash
# Use sudo for hosts file modification
sudo nano /etc/hosts

# Check file permissions
ls -la /etc/hosts

# Ensure Docker has proper permissions
sudo usermod -aG docker $USER
# Log out and back in after this command
```

### Diagnostic Commands

```bash
# Complete system status check
docker-compose ps
docker system df
docker network ls

# Service-specific health checks
curl -k https://ca.localtest.me:9000/health
curl http://localhost:3100/ready
curl http://localhost:3000/api/health

# Certificate status checks
docker exec certbot-device /usr/local/bin/certificate-monitor.sh health
docker exec certbot-app /usr/local/bin/certificate-monitor.sh health
docker exec certbot-mqtt /usr/local/bin/certificate-monitor.sh health

# Certificate file verification
docker exec certbot-device ls -la /certs/
docker exec certbot-app ls -la /certs/
docker exec certbot-mqtt ls -la /certs/

# ACME directory endpoint verification
docker exec step-ca curl -k https://localhost:9000/acme/acme/directory

# Network connectivity tests
docker exec step-ca ping -c 1 loki
docker exec grafana ping -c 1 loki
docker exec mosquitto ping -c 1 step-ca
```

## Cleanup and Reset

### Stopping Services

```bash
# Stop all services
docker-compose down

# Stop and remove volumes (complete reset)
docker-compose down -v

# Remove all containers and networks
docker-compose down --remove-orphans
```

### Removing Host File Entries

To clean up after testing, remove the added entries from your hosts file:

1. Edit the hosts file using the same method as installation
2. Remove or comment out the lines:
   ```
   # 127.0.0.1 ca.localtest.me
   # 127.0.0.1 mqtt.localtest.metest.me
   # 127.0.0.1 app.localtest.metest.me
   # 127.0.0.1 device.localtest.metest.me
   # 127.0.0.1 localhost:3000
   ```

### Complete Environment Reset

```bash
# Stop and remove everything
docker-compose down -v --remove-orphans

# Remove downloaded images (optional)
docker image prune -a

# Remove all unused Docker resources
docker system prune -a --volumes
```

## Next Steps

After successful setup and verification:

1. **Explore Grafana**: Access http://localhost:3000 and explore the Loki datasource
2. **Monitor Logs**: Watch real-time certificate renewal in Grafana
3. **Test Certificate Lifecycle**: Observe the 10-minute certificate expiration and 5-minute renewal cycle
4. **Prepare for Phase 2**: The infrastructure is now ready for the .NET device simulator and application development

## Support and Documentation

- **Project Documentation**: See `docs/` directory for detailed technical documentation
- **Configuration Reference**: See `docs/phase1-infrastructure-documentation.md`
- **Docker Compose Reference**: [Official Documentation](https://docs.docker.com/compose/)
- **step-ca Documentation**: [Smallstep Documentation](https://smallstep.com/docs/)
- **Mosquitto Documentation**: [Eclipse Mosquitto](https://mosquitto.org/documentation/)
- **Grafana Documentation**: [Grafana Labs](https://grafana.com/docs/)