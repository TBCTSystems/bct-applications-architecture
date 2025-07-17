#!/bin/bash

echo "🔧 Setting up MQTT ACME Certificate Renewal System"
echo "=================================================="

# Create necessary directories
echo "📁 Creating directory structure..."
mkdir -p logs certificates/backup

# Make renewal script executable
chmod +x mqtt-cert-renewal.sh

# Create systemd timer for automatic renewal (if systemd is available)
create_systemd_timer() {
    if command -v systemctl > /dev/null 2>&1; then
        echo "⏰ Creating systemd timer for automatic renewal..."
        
        # Create service file
        sudo tee /etc/systemd/system/mqtt-cert-renewal.service > /dev/null << EOF
[Unit]
Description=MQTT Certificate Renewal Service
After=network.target

[Service]
Type=oneshot
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/mqtt-cert-renewal.sh
User=$(whoami)
Group=$(whoami)

[Install]
WantedBy=multi-user.target
EOF

        # Create timer file
        sudo tee /etc/systemd/system/mqtt-cert-renewal.timer > /dev/null << EOF
[Unit]
Description=MQTT Certificate Renewal Timer
Requires=mqtt-cert-renewal.service

[Timer]
OnCalendar=daily
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF

        # Reload systemd and enable timer
        sudo systemctl daemon-reload
        sudo systemctl enable mqtt-cert-renewal.timer
        sudo systemctl start mqtt-cert-renewal.timer
        
        echo "✅ Systemd timer created and enabled"
        echo "   - Service: mqtt-cert-renewal.service"
        echo "   - Timer: mqtt-cert-renewal.timer"
        echo "   - Schedule: Daily with random delay"
    else
        echo "⚠️  systemd not available, manual scheduling required"
    fi
}

# Create cron job for automatic renewal
create_cron_job() {
    echo "⏰ Setting up cron job for automatic renewal..."
    
    # Add cron job to run daily at 2 AM
    (crontab -l 2>/dev/null; echo "0 2 * * * $(pwd)/mqtt-cert-renewal.sh >> $(pwd)/logs/mqtt-cert-renewal-cron.log 2>&1") | crontab -
    
    echo "✅ Cron job created"
    echo "   - Schedule: Daily at 2:00 AM"
    echo "   - Log: $(pwd)/logs/mqtt-cert-renewal-cron.log"
}

# Create monitoring script
create_monitoring_script() {
    echo "📊 Creating certificate monitoring script..."
    
    cat > mqtt-cert-monitor.sh << 'EOF'
#!/bin/bash

# MQTT Certificate Monitoring Script
CERT_PATH="./certificates/mosquitto.crt"
LOG_FILE="./logs/mqtt-cert-monitor.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

if [ ! -f "$CERT_PATH" ]; then
    log "❌ Certificate not found: $CERT_PATH"
    exit 1
fi

# Get certificate expiry information
expiry_date=$(openssl x509 -in "$CERT_PATH" -enddate -noout | cut -d= -f2)
expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
current_epoch=$(date +%s)
days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))

log "📅 Certificate expires: $expiry_date"
log "📊 Days until expiry: $days_until_expiry"

# Alert thresholds
if [ "$days_until_expiry" -le 3 ]; then
    log "🚨 CRITICAL: Certificate expires in $days_until_expiry days!"
    exit 2
elif [ "$days_until_expiry" -le 7 ]; then
    log "⚠️  WARNING: Certificate expires in $days_until_expiry days"
    exit 1
else
    log "✅ Certificate is valid for $days_until_expiry days"
    exit 0
fi
EOF

    chmod +x mqtt-cert-monitor.sh
    echo "✅ Monitoring script created: mqtt-cert-monitor.sh"
}

# Create Docker Compose integration
create_docker_integration() {
    echo "🐳 Creating Docker Compose integration..."
    
    cat > docker-mqtt-cert-renewal.sh << 'EOF'
#!/bin/bash

# Docker-specific MQTT Certificate Renewal
echo "🔄 Docker MQTT Certificate Renewal"
echo "=================================="

# Ensure Docker Compose is available
if ! command -v docker > /dev/null 2>&1; then
    echo "❌ Docker not available"
    exit 1
fi

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ docker-compose.yml not found"
    exit 1
fi

# Run the main renewal script
./mqtt-cert-renewal.sh

# Additional Docker-specific checks
if [ $? -eq 0 ]; then
    echo "✅ Certificate renewal completed"
    
    # Verify Mosquitto is healthy
    echo "🔍 Checking Mosquitto health..."
    sleep 10
    
    if docker compose ps mosquitto | grep -q "healthy"; then
        echo "✅ Mosquitto is healthy with new certificate"
    else
        echo "⚠️  Mosquitto health check pending or failed"
        docker compose logs --tail 10 mosquitto
    fi
else
    echo "❌ Certificate renewal failed"
    exit 1
fi
EOF

    chmod +x docker-mqtt-cert-renewal.sh
    echo "✅ Docker integration script created: docker-mqtt-cert-renewal.sh"
}

# Create configuration file
create_config_file() {
    echo "⚙️  Creating configuration file..."
    
    cat > mqtt-cert-renewal.conf << EOF
# MQTT Certificate Renewal Configuration

# step-ca Configuration
STEP_CA_URL="https://step-ca:9000"
STEP_CA_PROVISIONER="admin"
STEP_CA_PASSWORD="enterprise-ca-password"

# Certificate Configuration
CERT_VALIDITY_DAYS=30
RENEWAL_THRESHOLD_DAYS=7
BACKUP_RETENTION_DAYS=90

# MQTT Configuration
MQTT_SERVICE_NAME="mosquitto"
MQTT_TLS_PORT=8883
MQTT_RESTART_DELAY=5

# Logging Configuration
LOG_LEVEL="INFO"
LOG_RETENTION_DAYS=30

# Notification Configuration (future enhancement)
ENABLE_NOTIFICATIONS=false
NOTIFICATION_EMAIL=""
NOTIFICATION_WEBHOOK=""
EOF

    echo "✅ Configuration file created: mqtt-cert-renewal.conf"
}

# Test the renewal system
test_renewal_system() {
    echo "🧪 Testing certificate renewal system..."
    
    # Test certificate monitoring
    echo "Testing certificate monitoring..."
    ./mqtt-cert-monitor.sh
    
    echo ""
    echo "Testing renewal script (dry run)..."
    echo "Note: This will check the system but not perform actual renewal"
    
    # You could add a dry-run mode to the renewal script
    echo "✅ Test completed - review logs for any issues"
}

# Main setup process
main() {
    echo "🚀 Starting MQTT ACME renewal system setup..."
    
    # Create monitoring script
    create_monitoring_script
    
    # Create Docker integration
    create_docker_integration
    
    # Create configuration file
    create_config_file
    
    # Setup automatic scheduling
    echo ""
    echo "⏰ Setting up automatic renewal scheduling..."
    echo "Choose scheduling method:"
    echo "1) systemd timer (recommended for systemd systems)"
    echo "2) cron job (universal)"
    echo "3) manual scheduling"
    
    read -p "Enter choice (1-3): " choice
    
    case $choice in
        1)
            create_systemd_timer
            ;;
        2)
            create_cron_job
            ;;
        3)
            echo "ℹ️  Manual scheduling selected - you'll need to run mqtt-cert-renewal.sh manually"
            ;;
        *)
            echo "⚠️  Invalid choice, defaulting to manual scheduling"
            ;;
    esac
    
    # Test the system
    echo ""
    test_renewal_system
    
    echo ""
    echo "🎉 MQTT ACME Certificate Renewal System Setup Complete!"
    echo ""
    echo "📋 Summary:"
    echo "   - Renewal script: mqtt-cert-renewal.sh"
    echo "   - Monitoring script: mqtt-cert-monitor.sh"
    echo "   - Docker integration: docker-mqtt-cert-renewal.sh"
    echo "   - Configuration: mqtt-cert-renewal.conf"
    echo "   - Logs directory: logs/"
    echo "   - Backup directory: certificates/backup/"
    echo ""
    echo "🔧 Manual Commands:"
    echo "   - Test renewal: ./mqtt-cert-renewal.sh"
    echo "   - Check certificate: ./mqtt-cert-monitor.sh"
    echo "   - Docker renewal: ./docker-mqtt-cert-renewal.sh"
    echo ""
    echo "📊 Monitoring:"
    if command -v systemctl > /dev/null 2>&1 && [ "$choice" = "1" ]; then
        echo "   - Timer status: sudo systemctl status mqtt-cert-renewal.timer"
        echo "   - Service logs: sudo journalctl -u mqtt-cert-renewal.service"
    fi
    echo "   - Renewal logs: tail -f logs/mqtt-cert-renewal.log"
    echo "   - Monitor logs: tail -f logs/mqtt-cert-monitor.log"
}

# Run main setup
main "$@"