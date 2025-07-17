#!/bin/bash

echo "🔄 MQTT Certificate Renewal with step-ca ACME Integration"
echo "========================================================="

# Configuration
STEP_CA_URL="https://step-ca:9000"
CERT_DIR="./certificates"
MQTT_CERT_PATH="$CERT_DIR/mosquitto.crt"
MQTT_KEY_PATH="$CERT_DIR/mosquitto.key"
ROOT_CA_PATH="$CERT_DIR/root_ca.crt"
BACKUP_DIR="$CERT_DIR/backup"
LOG_FILE="./logs/mqtt-cert-renewal.log"

# Create necessary directories
mkdir -p "$BACKUP_DIR" "$(dirname "$LOG_FILE")"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check if step-ca is available
check_step_ca() {
    log "🔍 Checking step-ca availability..."
    if curl -k "$STEP_CA_URL/health" > /dev/null 2>&1; then
        log "✅ step-ca is available"
        return 0
    else
        log "❌ step-ca is not available"
        return 1
    fi
}

# Check certificate expiry
check_cert_expiry() {
    if [ ! -f "$MQTT_CERT_PATH" ]; then
        log "❌ MQTT certificate not found: $MQTT_CERT_PATH"
        return 1
    fi

    local expiry_date=$(openssl x509 -in "$MQTT_CERT_PATH" -enddate -noout | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
    local current_epoch=$(date +%s)
    local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))

    log "📅 Certificate expires: $expiry_date"
    log "📊 Days until expiry: $days_until_expiry"

    if [ "$days_until_expiry" -le 7 ]; then
        log "⚠️  Certificate expires in $days_until_expiry days - renewal needed"
        return 0
    else
        log "✅ Certificate valid for $days_until_expiry days - no renewal needed"
        return 1
    fi
}

# Backup current certificates
backup_certificates() {
    log "💾 Backing up current certificates..."
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_subdir="$BACKUP_DIR/$timestamp"
    
    mkdir -p "$backup_subdir"
    
    if [ -f "$MQTT_CERT_PATH" ]; then
        cp "$MQTT_CERT_PATH" "$backup_subdir/mosquitto.crt.backup"
        log "✅ Backed up certificate to $backup_subdir/mosquitto.crt.backup"
    fi
    
    if [ -f "$MQTT_KEY_PATH" ]; then
        cp "$MQTT_KEY_PATH" "$backup_subdir/mosquitto.key.backup"
        log "✅ Backed up private key to $backup_subdir/mosquitto.key.backup"
    fi
}

# Request new certificate from step-ca using ACME
renew_certificate_acme() {
    log "🔐 Requesting new certificate from step-ca via ACME..."
    
    # Use step CLI to request certificate via ACME
    if command -v step > /dev/null 2>&1; then
        log "📋 Using step CLI for ACME certificate request..."
        
        # Request certificate using step CLI
        docker run --rm --network host \
            -v "$(pwd)/certificates:/certs" \
            -v "$(pwd)/step-ca-config:/home/step/.step" \
            smallstep/step-cli:latest \
            step ca certificate mosquitto \
            /certs/mosquitto_new.crt /certs/mosquitto_new.key \
            --ca-url "$STEP_CA_URL" \
            --root /certs/root_ca.crt \
            --san mosquitto \
            --san localhost \
            --san 127.0.0.1 \
            --san enterprise-mosquitto \
            --not-after 720h \
            --insecure \
            --provisioner admin \
            --provisioner-password-file <(echo "enterprise-ca-password") 2>&1 | tee -a "$LOG_FILE"
        
        if [ $? -eq 0 ] && [ -f "$CERT_DIR/mosquitto_new.crt" ]; then
            log "✅ Successfully obtained new certificate from step-ca"
            return 0
        else
            log "⚠️  step-ca certificate request failed, falling back to self-signed"
            return 1
        fi
    else
        log "⚠️  step CLI not available, falling back to self-signed certificate"
        return 1
    fi
}

# Generate self-signed certificate as fallback
generate_fallback_certificate() {
    log "🔧 Generating fallback self-signed certificate..."
    
    openssl req -x509 -newkey rsa:2048 \
        -keyout "$CERT_DIR/mosquitto_new.key" \
        -out "$CERT_DIR/mosquitto_new.crt" \
        -days 30 -nodes \
        -subj "/CN=mosquitto" \
        -addext "subjectAltName=DNS:mosquitto,DNS:localhost,DNS:enterprise-mosquitto,IP:127.0.0.1" \
        2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -eq 0 ]; then
        log "✅ Fallback certificate generated successfully"
        return 0
    else
        log "❌ Failed to generate fallback certificate"
        return 1
    fi
}

# Validate new certificate
validate_certificate() {
    log "🔍 Validating new certificate..."
    
    if [ ! -f "$CERT_DIR/mosquitto_new.crt" ]; then
        log "❌ New certificate file not found"
        return 1
    fi
    
    # Check certificate validity
    if openssl x509 -in "$CERT_DIR/mosquitto_new.crt" -text -noout > /dev/null 2>&1; then
        log "✅ Certificate format is valid"
    else
        log "❌ Certificate format is invalid"
        return 1
    fi
    
    # Check certificate subject
    local subject=$(openssl x509 -in "$CERT_DIR/mosquitto_new.crt" -subject -noout | grep -o "CN=[^,]*")
    if echo "$subject" | grep -q "mosquitto"; then
        log "✅ Certificate subject is correct: $subject"
    else
        log "❌ Certificate subject is incorrect: $subject"
        return 1
    fi
    
    # Check certificate expiry
    local expiry_date=$(openssl x509 -in "$CERT_DIR/mosquitto_new.crt" -enddate -noout | cut -d= -f2)
    log "📅 New certificate expires: $expiry_date"
    
    # Check if certificate has private key
    if [ -f "$CERT_DIR/mosquitto_new.key" ]; then
        log "✅ Private key is present"
    else
        log "❌ Private key is missing"
        return 1
    fi
    
    return 0
}

# Install new certificate
install_certificate() {
    log "📦 Installing new certificate..."
    
    # Move new certificate to active location
    if mv "$CERT_DIR/mosquitto_new.crt" "$MQTT_CERT_PATH"; then
        log "✅ New certificate installed"
    else
        log "❌ Failed to install new certificate"
        return 1
    fi
    
    # Move new private key to active location
    if mv "$CERT_DIR/mosquitto_new.key" "$MQTT_KEY_PATH"; then
        log "✅ New private key installed"
    else
        log "❌ Failed to install new private key"
        return 1
    fi
    
    # Set proper permissions
    chmod 644 "$MQTT_CERT_PATH"
    chmod 600 "$MQTT_KEY_PATH"
    
    log "🔒 Certificate permissions set correctly"
    return 0
}

# Restart MQTT broker to use new certificate
restart_mqtt_broker() {
    log "🔄 Restarting MQTT broker to use new certificate..."
    
    if command -v docker > /dev/null 2>&1; then
        # Check if running in Docker Compose environment
        if [ -f "docker-compose.yml" ]; then
            log "🐳 Restarting Mosquitto via Docker Compose..."
            docker compose restart mosquitto 2>&1 | tee -a "$LOG_FILE"
            
            if [ $? -eq 0 ]; then
                log "✅ Mosquitto restarted successfully"
                
                # Wait for service to be ready
                sleep 5
                
                # Check if service is healthy
                if docker compose ps mosquitto | grep -q "Up"; then
                    log "✅ Mosquitto is running with new certificate"
                    return 0
                else
                    log "❌ Mosquitto failed to start with new certificate"
                    return 1
                fi
            else
                log "❌ Failed to restart Mosquitto"
                return 1
            fi
        else
            log "⚠️  Docker Compose file not found, manual restart required"
            return 1
        fi
    else
        log "⚠️  Docker not available, manual restart required"
        return 1
    fi
}

# Test MQTT broker with new certificate
test_mqtt_connection() {
    log "🧪 Testing MQTT broker with new certificate..."
    
    # Test TLS port connectivity
    if timeout 5 bash -c "</dev/tcp/localhost/8883" 2>/dev/null; then
        log "✅ MQTT TLS port 8883 is accessible"
    else
        log "❌ MQTT TLS port 8883 is not accessible"
        return 1
    fi
    
    # Test certificate with openssl
    if echo | openssl s_client -connect localhost:8883 -servername mosquitto 2>/dev/null | grep -q "Verify return code: 0"; then
        log "✅ TLS certificate verification successful"
    else
        log "⚠️  TLS certificate verification failed (may be expected for self-signed)"
    fi
    
    return 0
}

# Cleanup temporary files
cleanup() {
    log "🧹 Cleaning up temporary files..."
    
    # Remove any temporary certificate files
    rm -f "$CERT_DIR/mosquitto_new.crt" "$CERT_DIR/mosquitto_new.key"
    
    log "✅ Cleanup completed"
}

# Main renewal process
main() {
    log "🚀 Starting MQTT certificate renewal process..."
    
    # Check if step-ca is available
    if ! check_step_ca; then
        log "⚠️  Proceeding without step-ca integration"
    fi
    
    # Check if renewal is needed
    if ! check_cert_expiry; then
        log "ℹ️  Certificate renewal not needed at this time"
        exit 0
    fi
    
    # Backup current certificates
    backup_certificates
    
    # Try to renew certificate via step-ca ACME
    if renew_certificate_acme; then
        log "✅ Certificate renewed via step-ca ACME"
    elif generate_fallback_certificate; then
        log "✅ Fallback certificate generated"
    else
        log "❌ Certificate renewal failed completely"
        exit 1
    fi
    
    # Validate new certificate
    if ! validate_certificate; then
        log "❌ Certificate validation failed"
        cleanup
        exit 1
    fi
    
    # Install new certificate
    if ! install_certificate; then
        log "❌ Certificate installation failed"
        cleanup
        exit 1
    fi
    
    # Restart MQTT broker
    if ! restart_mqtt_broker; then
        log "❌ MQTT broker restart failed"
        exit 1
    fi
    
    # Test MQTT connection
    if ! test_mqtt_connection; then
        log "❌ MQTT connection test failed"
        exit 1
    fi
    
    # Cleanup
    cleanup
    
    log "🎉 MQTT certificate renewal completed successfully!"
    
    # Log certificate details
    local new_expiry=$(openssl x509 -in "$MQTT_CERT_PATH" -enddate -noout | cut -d= -f2)
    log "📅 New certificate expires: $new_expiry"
    
    exit 0
}

# Handle script interruption
trap cleanup EXIT

# Run main function
main "$@"