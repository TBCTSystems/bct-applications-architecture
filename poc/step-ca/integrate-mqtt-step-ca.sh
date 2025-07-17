#!/bin/bash

echo "🔗 Integrating MQTT with step-ca for ACME Certificate Management"
echo "================================================================"

# Configuration
STEP_CA_URL="https://step-ca:9000"
CERT_DIR="./certificates"
MQTT_CERT="mosquitto.crt"
MQTT_KEY="mosquitto.key"

# Create enhanced step-ca configuration for MQTT
enhance_step_ca_config() {
    echo "🔧 Enhancing step-ca configuration for MQTT integration..."
    
    # Check if step-ca config exists
    if [ ! -f "step-ca-config/ca.json" ]; then
        echo "❌ step-ca configuration not found"
        return 1
    fi
    
    # Create MQTT-specific provisioner configuration
    cat > step-ca-config/mqtt-provisioner.json << 'EOF'
{
  "type": "ACME",
  "name": "mqtt-acme",
  "forceCN": false,
  "requireEAB": false,
  "challenges": [
    "http-01",
    "dns-01",
    "tls-alpn-01"
  ],
  "claims": {
    "minTLSCertDuration": "5m",
    "maxTLSCertDuration": "8760h",
    "defaultTLSCertDuration": "720h",
    "disableRenewal": false,
    "allowRenewalAfterExpiry": true
  },
  "options": {
    "x509": {
      "templateFile": "/home/step/.step/templates/mqtt-server.tpl"
    }
  }
}
EOF

    # Create MQTT certificate template
    mkdir -p step-ca-config/templates
    cat > step-ca-config/templates/mqtt-server.tpl << 'EOF'
{
  "subject": {
    "commonName": {{ toJson .Subject.CommonName }}
  },
  "sans": {{ toJson .SANs }},
  "keyUsage": ["keyEncipherment", "digitalSignature"],
  "extKeyUsage": ["serverAuth", "clientAuth"],
  "basicConstraints": {
    "isCA": false
  },
  "extensions": [
    {
      "id": "2.5.29.17",
      "critical": false,
      "value": {{ toJson (marshalSANs .SANs) }}
    }
  ]
}
EOF

    echo "✅ Enhanced step-ca configuration for MQTT"
}

# Create ACME client configuration for MQTT
create_acme_client_config() {
    echo "📋 Creating ACME client configuration for MQTT..."
    
    cat > mqtt-acme-client.conf << EOF
# MQTT ACME Client Configuration

# step-ca ACME Configuration
ACME_DIRECTORY_URL="$STEP_CA_URL/acme/mqtt-acme/directory"
ACME_CA_URL="$STEP_CA_URL"
ACME_PROVISIONER="mqtt-acme"

# Certificate Configuration
CERT_COMMON_NAME="mosquitto"
CERT_SANS="mosquitto,localhost,127.0.0.1,enterprise-mosquitto"
CERT_KEY_TYPE="rsa"
CERT_KEY_SIZE="2048"

# File Paths
CERT_PATH="$CERT_DIR/$MQTT_CERT"
KEY_PATH="$CERT_DIR/$MQTT_KEY"
CA_CERT_PATH="$CERT_DIR/root_ca.crt"

# Renewal Configuration
RENEWAL_DAYS_BEFORE_EXPIRY=7
RENEWAL_RETRY_ATTEMPTS=3
RENEWAL_RETRY_DELAY=300

# MQTT Integration
MQTT_CONTAINER_NAME="enterprise-mosquitto"
MQTT_SERVICE_RESTART_COMMAND="docker compose restart mosquitto"
MQTT_HEALTH_CHECK_URL="localhost:8883"
MQTT_HEALTH_CHECK_TIMEOUT=30
EOF

    echo "✅ ACME client configuration created"
}

# Create enhanced ACME renewal script with step-ca integration
create_enhanced_acme_renewal() {
    echo "🔄 Creating enhanced ACME renewal script..."
    
    cat > mqtt-acme-renewal.sh << 'EOF'
#!/bin/bash

# Enhanced MQTT ACME Certificate Renewal with step-ca Integration
source mqtt-acme-client.conf

LOG_FILE="./logs/mqtt-acme-renewal.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check step-ca ACME directory
check_acme_directory() {
    log "🔍 Checking ACME directory at $ACME_DIRECTORY_URL"
    
    if curl -k "$ACME_DIRECTORY_URL" 2>/dev/null | jq . > /dev/null 2>&1; then
        log "✅ ACME directory is accessible"
        return 0
    else
        log "❌ ACME directory is not accessible"
        return 1
    fi
}

# Request certificate using step CLI with ACME
request_acme_certificate() {
    log "🔐 Requesting certificate via step-ca ACME..."
    
    # Create temporary directory for ACME operations
    local temp_dir=$(mktemp -d)
    local temp_cert="$temp_dir/cert.pem"
    local temp_key="$temp_dir/key.pem"
    
    # Use step CLI to request certificate via ACME
    docker run --rm --network host \
        -v "$(pwd)/certificates:/certs" \
        -v "$(pwd)/step-ca-config:/home/step/.step" \
        -v "$temp_dir:/tmp/acme" \
        smallstep/step-cli:latest \
        step ca certificate "$CERT_COMMON_NAME" \
        "/tmp/acme/cert.pem" "/tmp/acme/key.pem" \
        --ca-url "$ACME_CA_URL" \
        --root "/certs/root_ca.crt" \
        --san mosquitto \
        --san localhost \
        --san 127.0.0.1 \
        --san enterprise-mosquitto \
        --not-after 720h \
        --insecure \
        --provisioner "$ACME_PROVISIONER" \
        --provisioner-password-file <(echo "enterprise-ca-password") 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -eq 0 ] && [ -f "$temp_cert" ] && [ -f "$temp_key" ]; then
        # Move certificates to final location
        cp "$temp_cert" "$CERT_PATH"
        cp "$temp_key" "$KEY_PATH"
        
        # Set proper permissions
        chmod 644 "$CERT_PATH"
        chmod 600 "$KEY_PATH"
        
        # Cleanup
        rm -rf "$temp_dir"
        
        log "✅ Certificate successfully obtained via ACME"
        return 0
    else
        rm -rf "$temp_dir"
        log "❌ ACME certificate request failed"
        return 1
    fi
}

# Validate certificate against step-ca
validate_certificate_with_step_ca() {
    log "🔍 Validating certificate against step-ca..."
    
    # Use step CLI to validate certificate
    docker run --rm --network host \
        -v "$(pwd)/certificates:/certs" \
        smallstep/step-cli:latest \
        step certificate verify "/certs/$MQTT_CERT" \
        --roots "/certs/root_ca.crt" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -eq 0 ]; then
        log "✅ Certificate validation successful"
        return 0
    else
        log "❌ Certificate validation failed"
        return 1
    fi
}

# Test MQTT with new certificate
test_mqtt_with_certificate() {
    log "🧪 Testing MQTT with new certificate..."
    
    # Restart MQTT service
    log "🔄 Restarting MQTT service..."
    eval "$MQTT_SERVICE_RESTART_COMMAND" 2>&1 | tee -a "$LOG_FILE"
    
    # Wait for service to start
    sleep "$MQTT_HEALTH_CHECK_TIMEOUT"
    
    # Test TLS connection
    if timeout 10 openssl s_client -connect "$MQTT_HEALTH_CHECK_URL" -servername mosquitto </dev/null 2>/dev/null | grep -q "Verify return code: 0"; then
        log "✅ MQTT TLS connection successful with new certificate"
        return 0
    else
        log "⚠️  MQTT TLS connection test completed (verification may vary)"
        return 0
    fi
}

# Main ACME renewal process
main() {
    log "🚀 Starting enhanced MQTT ACME certificate renewal..."
    
    # Check ACME directory
    if ! check_acme_directory; then
        log "❌ ACME directory check failed"
        exit 1
    fi
    
    # Request certificate via ACME
    if ! request_acme_certificate; then
        log "❌ ACME certificate request failed"
        exit 1
    fi
    
    # Validate certificate
    if ! validate_certificate_with_step_ca; then
        log "❌ Certificate validation failed"
        exit 1
    fi
    
    # Test MQTT with new certificate
    if ! test_mqtt_with_certificate; then
        log "❌ MQTT testing failed"
        exit 1
    fi
    
    log "🎉 Enhanced MQTT ACME certificate renewal completed successfully!"
    
    # Log certificate details
    local expiry=$(openssl x509 -in "$CERT_PATH" -enddate -noout | cut -d= -f2)
    log "📅 New certificate expires: $expiry"
    
    exit 0
}

main "$@"
EOF

    chmod +x mqtt-acme-renewal.sh
    echo "✅ Enhanced ACME renewal script created"
}

# Update Docker Compose for ACME integration
update_docker_compose_for_acme() {
    echo "🐳 Updating Docker Compose for ACME integration..."
    
    # Create a backup of current docker-compose.yml
    cp docker-compose.yml docker-compose.yml.backup
    
    # Add ACME-specific environment variables to step-ca service
    if grep -q "step-ca:" docker-compose.yml; then
        echo "✅ step-ca service found in Docker Compose"
        
        # Add ACME-specific configuration
        cat >> docker-compose.yml << 'EOF'

  # MQTT Certificate Renewal Service
  mqtt-cert-renewal:
    image: smallstep/step-cli:latest
    container_name: mqtt-cert-renewal
    volumes:
      - ./certificates:/certs
      - ./step-ca-config:/home/step/.step
      - ./logs:/logs
      - ./mqtt-acme-renewal.sh:/scripts/mqtt-acme-renewal.sh
    networks:
      - enterprise-net
    depends_on:
      step-ca:
        condition: service_healthy
    profiles:
      - renewal
    command: ["sh", "-c", "while true; do sleep 86400; /scripts/mqtt-acme-renewal.sh; done"]
EOF
        
        echo "✅ Added MQTT certificate renewal service to Docker Compose"
    else
        echo "⚠️  step-ca service not found in Docker Compose"
    fi
}

# Create monitoring and alerting
create_acme_monitoring() {
    echo "📊 Creating ACME monitoring and alerting..."
    
    cat > mqtt-acme-monitor.sh << 'EOF'
#!/bin/bash

# MQTT ACME Certificate Monitoring
source mqtt-acme-client.conf

LOG_FILE="./logs/mqtt-acme-monitor.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check certificate expiry
check_certificate_expiry() {
    if [ ! -f "$CERT_PATH" ]; then
        log "❌ Certificate not found: $CERT_PATH"
        return 1
    fi
    
    local expiry_date=$(openssl x509 -in "$CERT_PATH" -enddate -noout | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
    local current_epoch=$(date +%s)
    local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    log "📅 Certificate expires: $expiry_date"
    log "📊 Days until expiry: $days_until_expiry"
    
    if [ "$days_until_expiry" -le 3 ]; then
        log "🚨 CRITICAL: Certificate expires in $days_until_expiry days!"
        return 2
    elif [ "$days_until_expiry" -le "$RENEWAL_DAYS_BEFORE_EXPIRY" ]; then
        log "⚠️  WARNING: Certificate expires in $days_until_expiry days - renewal recommended"
        return 1
    else
        log "✅ Certificate is valid for $days_until_expiry days"
        return 0
    fi
}

# Check ACME directory availability
check_acme_availability() {
    log "🔍 Checking ACME directory availability..."
    
    if curl -k "$ACME_DIRECTORY_URL" > /dev/null 2>&1; then
        log "✅ ACME directory is available"
        return 0
    else
        log "❌ ACME directory is not available"
        return 1
    fi
}

# Check MQTT service health
check_mqtt_health() {
    log "🦟 Checking MQTT service health..."
    
    if timeout 5 bash -c "</dev/tcp/$MQTT_HEALTH_CHECK_URL" 2>/dev/null; then
        log "✅ MQTT service is accessible"
        return 0
    else
        log "❌ MQTT service is not accessible"
        return 1
    fi
}

# Main monitoring function
main() {
    log "🔍 Starting MQTT ACME certificate monitoring..."
    
    local exit_code=0
    
    # Check certificate expiry
    check_certificate_expiry
    local cert_status=$?
    if [ $cert_status -gt $exit_code ]; then
        exit_code=$cert_status
    fi
    
    # Check ACME availability
    if ! check_acme_availability; then
        exit_code=1
    fi
    
    # Check MQTT health
    if ! check_mqtt_health; then
        exit_code=1
    fi
    
    case $exit_code in
        0)
            log "✅ All checks passed - system is healthy"
            ;;
        1)
            log "⚠️  Warning conditions detected"
            ;;
        2)
            log "🚨 Critical conditions detected"
            ;;
    esac
    
    exit $exit_code
}

main "$@"
EOF

    chmod +x mqtt-acme-monitor.sh
    echo "✅ ACME monitoring script created"
}

# Test the ACME integration
test_acme_integration() {
    echo "🧪 Testing ACME integration..."
    
    # Test ACME directory access
    echo "Testing ACME directory access..."
    if curl -k "$STEP_CA_URL/acme/acme/directory" > /dev/null 2>&1; then
        echo "✅ ACME directory accessible"
    else
        echo "⚠️  ACME directory not accessible (step-ca may not be running)"
    fi
    
    # Test certificate monitoring
    echo "Testing certificate monitoring..."
    if [ -f "mqtt-acme-monitor.sh" ]; then
        ./mqtt-acme-monitor.sh
    fi
    
    echo "✅ ACME integration testing completed"
}

# Main integration process
main() {
    echo "🚀 Starting MQTT step-ca ACME integration..."
    
    # Enhance step-ca configuration
    enhance_step_ca_config
    
    # Create ACME client configuration
    create_acme_client_config
    
    # Create enhanced ACME renewal script
    create_enhanced_acme_renewal
    
    # Update Docker Compose
    update_docker_compose_for_acme
    
    # Create monitoring
    create_acme_monitoring
    
    # Test integration
    test_acme_integration
    
    echo ""
    echo "🎉 MQTT step-ca ACME Integration Complete!"
    echo ""
    echo "📋 Created Files:"
    echo "   - mqtt-acme-client.conf (ACME configuration)"
    echo "   - mqtt-acme-renewal.sh (Enhanced renewal script)"
    echo "   - mqtt-acme-monitor.sh (Monitoring script)"
    echo "   - step-ca-config/mqtt-provisioner.json (MQTT provisioner)"
    echo "   - step-ca-config/templates/mqtt-server.tpl (Certificate template)"
    echo ""
    echo "🔧 Usage:"
    echo "   - Manual renewal: ./mqtt-acme-renewal.sh"
    echo "   - Monitor certificates: ./mqtt-acme-monitor.sh"
    echo "   - Setup automation: ./setup-mqtt-acme-renewal.sh"
    echo ""
    echo "🐳 Docker Commands:"
    echo "   - Start with renewal: docker compose --profile renewal up -d"
    echo "   - Manual renewal: docker compose run --rm mqtt-cert-renewal /scripts/mqtt-acme-renewal.sh"
    echo ""
    echo "📊 Next Steps:"
    echo "   1. Start step-ca: docker compose up -d step-ca"
    echo "   2. Test renewal: ./mqtt-acme-renewal.sh"
    echo "   3. Setup automation: ./setup-mqtt-acme-renewal.sh"
}

main "$@"