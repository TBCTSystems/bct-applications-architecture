# Certificate Management PoC - Automated mTLS with step-ca

A comprehensive proof-of-concept demonstrating automated certificate management using step-ca, ACME protocol, and mTLS-secured MQTT communication in a containerized environment.

## Project Overview

This PoC validates an end-to-end automated certificate management solution featuring:

- **step-ca Certificate Authority** with ACME protocol support
- **Automated certificate provisioning** via certbot integration
- **mTLS-secured MQTT communication** between IoT devices and applications
- **Real-time telemetry dashboard** with React frontend and .NET Core backend
- **Complete observability stack** with Prometheus, Grafana, and Loki
- **Cross-platform deployment** supporting Linux, macOS, and Windows

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   step-ca       │    │   Mosquitto      │    │   React         │
│   (ACME CA)     │    │   (MQTT Broker)  │    │   Frontend      │
│   Port: 9000    │    │   Port: 8883     │    │   Port: 3000    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         │ Certificate           │ mTLS                  │ HTTP/SignalR
         │ Issuance              │ Communication         │
         │                       │                       │
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Certbot       │    │   Device         │    │   Web API       │
│   Containers    │    │   Simulator      │    │   Backend       │
│   (Auto-renew)  │    │   (.NET Core)    │    │   (.NET Core)   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Quick Start

### Prerequisites

- Docker and Docker Compose
- 8GB+ RAM recommended
- Ports 3000, 5000, 8883, 9000 available

### 1. Clone and Setup

```bash
git clone <repository-url>
cd step-ca-poc
```

### 2. Update Hosts File

Add these entries to your hosts file:
- **Linux/macOS**: `/etc/hosts`
- **Windows**: `C:\Windows\System32\drivers\etc\hosts`

```
127.0.0.1 ca.localtest.me
127.0.0.1 device.localtest.me
127.0.0.1 app.localtest.me
127.0.0.1 mqtt.localtest.me
```

### 3. Fix Docker Permissions (Required)

**Linux/macOS:**
```bash
./scripts/fix-permissions.sh
```

**Windows (PowerShell as Administrator):**
```powershell
.\scripts\fix-permissions.ps1
```

### 4. Start the Stack

```bash
docker compose up -d
```

### 5. Verify Deployment

```bash
# Check all services are healthy
docker compose ps

# Monitor certificate automation
docker compose logs -f cert-automation

# Access the dashboard
open http://localhost:3000
```

## Service Endpoints

| Service | URL | Purpose |
|---------|-----|---------|
| **React Dashboard** | http://localhost:3000 | Real-time telemetry visualization |
| **Web API** | http://localhost:5000 | REST API and SignalR hub |
| **step-ca** | https://ca.localtest.me:9000 | Certificate Authority |
| **Grafana** | http://localhost:3000 | Observability dashboards |
| **Device Metrics** | http://localhost:8080/metrics | Prometheus metrics |

## Key Components

### Certificate Management
- **step-ca**: ACME-enabled Certificate Authority
- **certbot containers**: Automated certificate provisioning for each service
- **10-minute certificate lifecycle** (configurable for demo purposes)
- **Automatic renewal and distribution**

### IoT Device Simulation
- **.NET Core Device Simulator**: Simulates blood separator centrifuge
- **mTLS MQTT connection**: Secure communication with broker
- **Real-time telemetry**: Temperature, RPM, vibration, pressure data
- **Automatic certificate reload**: No service restart required

### Backend Services
- **.NET Core Web API**: MQTT subscriber and REST API
- **SignalR Hub**: Real-time data broadcasting
- **Historical data storage**: In-memory for PoC
- **Comprehensive metrics**: Prometheus integration

### Frontend
- **React TypeScript SPA**: Modern responsive dashboard
- **Material-UI components**: Professional UI/UX
- **Real-time updates**: SignalR client integration
- **Device monitoring**: Status, alerts, and telemetry visualization

### Observability
- **Prometheus**: Metrics collection from all services
- **Grafana**: Visualization and alerting
- **Loki**: Centralized log aggregation
- **Structured logging**: JSON format with correlation IDs

## Security Features

- **mTLS Authentication**: Certificate-based client authentication
- **Automated Certificate Rotation**: 10-minute lifecycle with 5-minute renewal
- **Network Isolation**: Docker network segmentation
- **TLS 1.2/1.3**: Modern encryption standards
- **Certificate Chain Validation**: Complete trust chain verification

## Monitoring & Metrics

### Device Simulator Metrics
- `device_mqtt_connection_status`
- `device_telemetry_messages_sent_total`
- `device_certificate_expiry_seconds`
- `device_temperature_celsius`
- `device_rpm_current`

### Web API Metrics
- `mqtt_messages_received_total`
- `signalr_connections_active`
- `api_requests_total`
- `certificate_reload_total`

## Development

### Project Structure
```
├── src/
│   ├── DeviceSimulator/     # .NET Core device simulator
│   ├── WebApi/              # .NET Core backend API
│   └── Frontend/            # React TypeScript SPA
├── docker/
│   └── certbot/             # Custom certbot container
├── config/
│   ├── mosquitto/           # MQTT broker configuration
│   ├── grafana/             # Dashboard and datasource configs
│   └── loki/                # Log aggregation configuration
├── scripts/                 # Automation and setup scripts
└── docs/                    # Phase completion reports
```

### Running Individual Services

```bash
# Start only infrastructure
docker compose up -d step-ca mosquitto loki grafana

# Start device simulator only
docker compose up -d device-simulator

# View logs for specific service
docker compose logs -f web-api
```

### Certificate Management

```bash
# Manually trigger certificate automation
./scripts/ensure-certificate-automation.sh

# Check certificate status
docker exec certbot-device /usr/local/bin/certificate-monitor.sh status

# View certificate details
docker exec mosquitto openssl x509 -in /mosquitto/certs/cert.pem -text -noout
```

## Testing

### Health Checks
```bash
# Check all service health
curl http://localhost:5000/health
curl http://localhost:8080/health
curl -k https://ca.localtest.me:9000/health
```

### MQTT Testing
```bash
# Test non-TLS connection (for debugging)
docker exec mosquitto mosquitto_pub -h localhost -t test -m "hello world"

# Monitor MQTT traffic
docker compose logs -f mosquitto
```

### Certificate Validation
```bash
# Verify certificate chain
openssl verify -CAfile ca_chain.crt cert.pem

# Check certificate expiration
openssl x509 -in cert.pem -noout -dates
```

## Troubleshooting

### Common Issues

**1. Permission Denied Errors**
```bash
# Run the permission fix script
./scripts/fix-permissions.sh  # Linux/macOS
.\scripts\fix-permissions.ps1  # Windows
```

**2. Certificate Generation Failures**
```bash
# Check certbot logs
docker compose logs certbot-app

# Verify step-ca is accessible
curl -k https://ca.localtest.me:9000/health
```

**3. MQTT Connection Issues**
```bash
# Check Mosquitto logs
docker compose logs mosquitto

# Verify certificate files exist
docker exec device-simulator ls -la /certs/
```

**4. Frontend Not Loading**
```bash
# Check if Web API is running
curl http://localhost:5000/health

# Verify SignalR connection
docker compose logs web-api | grep SignalR
```

### Reset Environment
```bash
# Complete reset
docker compose down -v
docker system prune -f

# Restart with fresh state
./scripts/fix-permissions.sh  # If needed
docker compose up -d
```

## Documentation

- [Phase 1: Infrastructure Setup](docs/phase1-acceptance-criteria.md)
- [Phase 2: Certificate Management](docs/phase2.1-completion-report.md)
- [Phase 3: Device Simulator](docs/phase3-completion-report.md)
- [Phase 4: Web Application](docs/phase4-final-integration-report.md)
- [Certificate Troubleshooting](docs/certificate-troubleshooting.md)
- [Setup Guide](docs/setup-guide.md)

## Production Considerations

### Security Hardening
- Increase certificate lifetime (24 hours → 90 days)
- Implement proper CA certificate management
- Add certificate revocation checking
- Enable audit logging

### Scalability
- Replace in-memory storage with persistent database
- Implement horizontal scaling for Web API
- Add load balancing for MQTT broker
- Configure certificate distribution for multiple nodes

### Monitoring
- Set up alerting rules in Grafana
- Implement certificate expiration monitoring
- Add performance benchmarking
- Configure log retention policies

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [Smallstep step-ca](https://github.com/smallstep/certificates) for the excellent ACME CA
- [Eclipse Mosquitto](https://mosquitto.org/) for the robust MQTT broker
- [Grafana Labs](https://grafana.com/) for the observability stack

---

**Status**: Production Ready  
**Last Updated**: January 27, 2025  
**Version**: 1.0.0