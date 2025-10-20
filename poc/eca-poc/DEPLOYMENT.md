# Certificate Auto-Renewal Service

## Overview

This service automatically monitors and renews certificates using Step CA. It's designed for production environments where certificate lifecycle management needs to be automated and reliable.

## Key Components

### 1. Certificate Monitor (`certificate_monitor.py`)
- Monitors certificate expiration dates
- Validates certificate integrity
- Tracks renewal status and history
- Supports both PEM and DER certificate formats

### 2. Step CA Client (`step_ca_client.py`)
- Interfaces with Step CA for certificate operations
- Handles authentication and provisioning
- Manages certificate renewal and validation
- Provides error handling and retry logic

### 3. Renewal Service (`renewal_service.py`)
- Main orchestration service
- Coordinates monitoring and renewal activities
- Manages service lifecycle and scheduling
- Provides status reporting and health checks

### 4. Configuration System (`config.py`)
- Flexible YAML-based configuration
- Environment variable overrides
- Validation and schema enforcement
- Support for multiple certificate profiles

### 5. Logging System (`logger.py`)
- Structured logging with multiple outputs
- Log rotation and retention policies
- Configurable log levels and formats
- Integration with monitoring systems

## Deployment Options

### Standalone Python Application
```bash
pip install -r requirements.txt
python main.py daemon
```

### Docker Container
```bash
docker-compose up -d
```

### Kubernetes (Example)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cert-renewal-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cert-renewal-service
  template:
    metadata:
      labels:
        app: cert-renewal-service
    spec:
      containers:
      - name: cert-renewal
        image: cert-renewal-service:latest
        env:
        - name: CERT_RENEWAL_STEP_CA__CA_URL
          value: "https://step-ca:9000"
        volumeMounts:
        - name: certs
          mountPath: /app/certs
        - name: config
          mountPath: /app/config
      volumes:
      - name: certs
        persistentVolumeClaim:
          claimName: cert-storage
      - name: config
        configMap:
          name: cert-renewal-config
```

## Production Considerations

### Security
- Run with minimal privileges
- Secure storage of provisioner credentials
- Network segmentation for CA access
- Regular security updates

### Monitoring
- Health check endpoints
- Metrics export (Prometheus compatible)
- Alert integration for renewal failures
- Log aggregation and analysis

### High Availability
- Multiple service instances
- Shared certificate storage
- Coordination mechanisms
- Failover procedures

### Backup and Recovery
- Certificate backup procedures
- Configuration backup
- Disaster recovery planning
- Testing and validation

## Integration Examples

### With Nginx
```nginx
server {
    listen 443 ssl;
    ssl_certificate /app/certs/web-server.crt;
    ssl_certificate_key /app/certs/web-server.key;
    
    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
}
```

### With systemd
```ini
[Unit]
Description=Certificate Renewal Service
After=network.target

[Service]
Type=simple
User=certrenew
WorkingDirectory=/opt/cert-renewal
ExecStart=/usr/bin/python3 main.py daemon
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### With cron (backup option)
```bash
# Check certificates daily at 2 AM
0 2 * * * /opt/cert-renewal/main.py check >> /var/log/cert-renewal-cron.log 2>&1
```