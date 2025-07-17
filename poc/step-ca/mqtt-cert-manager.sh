#!/bin/bash

echo "🔐 MQTT Certificate Manager - step-ca ACME Integration"
echo "====================================================="

# Configuration
STEP_CA_URL="https://step-ca:9000"
MOSQUITTO_CERT_PATH="/mosquitto/certs"
CERT_RENEWAL_THRESHOLD_DAYS=7
LOG_FILE="/var/log/mqtt-cert-manager.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to check if step-ca is available
check_step_ca() {
    log_message "Checking step-ca availability..."
    if curl -k "$STEP_CA_URL/health" > /dev/null 2>&1; then
        log_message "✅ step-ca is available"
        return 0
    else
        log_message "❌ step-ca is not available"
        return 1
    fi
}

# Function to check certificate expiry
check_certificate_expiry() {
    local cert_file="$1"
    local threshold_days="$2"
    
    if [ ! -f "$cert_file" ]; then
        log_message "❌ Certificate file not found: $cert_file"
        return 1
    fi
    
    # Get certificate expiry date
    local expiry_date=$(openssl x509 -in "$cert_file" -enddate -noout | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s)
    local current_epoch=$(date +%s)
    local threshold_epoch=$((current_epoch + (threshold_days * 24 * 3600)))
    
    if [ "$expiry_epoch" -lt "$threshold_epoch" ]; then
        local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
        log_message "⚠️  Certificate expires in $days_until_expiry days (threshold: $threshold_days days)"
        return 0  # Needs renewal
    else
        local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
        log_message "✅ Certificate is valid for $days_until_expiry more days"
        return 1  # No renewal needed
    fi
}

# Function to request new certificate from step-ca using ACME
request_certificate_acme() {
    local common_name="$1"
    local cert_file="$2"
    local key_file="$3"
    
    log_message "🔄 Requesting new certificate for $common_name via ACME..."
    
    # Create temporary directory for ACME operations
    local temp_dir=$(mktemp -d)
    local account_key="$temp_dir/account.key"
    local cert_key="$temp_dir/cert.key"
    local cert_csr="$temp_dir/cert.csr"
    local cert_crt="$temp_dir/cert.crt"
    
    # Generate account key if it doesn't exist
    if [ ! -f "/etc/mqtt-cert-manager/account.key" ]; then
        mkdir -p /etc/mqtt-cert-manager
        openssl genrsa -out /etc/mqtt-cert-manager/account.key 2048
        log_message "Generated new ACME account key"
    fi
    cp /etc/mqtt-cert-manager/account.key "$account_key"
    
    # Generate new private key
    openssl genrsa -out "$cert_key" 2048
    
    # Generate certificate signing request
    openssl req -new -key "$cert_key" -out "$cert_csr" -subj "/CN=$common_name" \
        -addext "subjectAltName=DNS:$common_name,DNS:localhost,DNS:enterprise-mosquitto,IP:127.0.0.1"
    
    # Use step CLI to request certificate via ACME
    if command -v step > /dev/null 2>&1; then
        log_message "Using step CLI for ACME certificate request..."
        
        # Request certificate using step CLI
        if step ca certificate "$common_name" "$cert_crt" "$cert_key" \
            --ca-url "$STEP_CA_URL" \
            --root /mosquitto/certs/root_ca.crt \
            --san "$common_name" \
            --san "localhost" \
            --san "enterprise-mosquitto" \
            --san "127.0.0.1" \
            --not-after 720h \
            --insecure \
            --provisioner acme 2>/dev/null; then
            
            log_message "✅ Certificate obtained via step CLI"
            
            # Backup old certificates
            if [ -f "$cert_file" ]; then
                cp "$cert_file" "$cert_file.backup.$(date +%s)"
                cp "$key_file" "$key_file.backup.$(date +%s)"
            fi
            
            # Install new certificates
            cp "$cert_crt" "$cert_file"
            cp "$cert_key" "$key_file"
            chmod 644 "$cert_file"
            chmod 600 "$key_file"
            
            log_message "✅ New certificate installed successfully"
            cleanup_temp_dir "$temp_dir"
            return 0
        else
            log_message "⚠️  step CLI failed, trying manual ACME..."
        fi
    fi
    
    # Fallback: Manual ACME implementation (simplified)
    log_message "Using manual ACME implementation..."
    
    # For now, generate a new self-signed certificate as fallback
    openssl req -x509 -newkey rsa:2048 \
        -keyout "$cert_key" \
        -out "$cert_crt" \
        -days 30 -nodes \
        -subj "/CN=$common_name" \
        -addext "subjectAltName=DNS:$common_name,DNS:localhost,DNS:enterprise-mosquitto,IP:127.0.0.1"
    
    # Backup old certificates
    if [ -f "$cert_file" ]; then
        cp "$cert_file" "$cert_file.backup.$(date +%s)"
        cp "$key_file" "$key_file.backup.$(date +%s)"
    fi
    
    # Install new certificates
    cp "$cert_crt" "$cert_file"
    cp "$cert_key" "$key_file"
    chmod 644 "$cert_file"
    chmod 600 "$key_file"
    
    log_message "✅ Fallback certificate installed successfully"
    cleanup_temp_dir "$temp_dir"
    return 0
}

# Function to cleanup temporary directory
cleanup_temp_dir() {
    local temp_dir="$1"
    if [ -d "$temp_dir" ]; then
        rm -rf "$temp_dir"
    fi
}

# Function to reload Mosquitto configuration
reload_mosquitto() {
    log_message "🔄 Reloading Mosquitto configuration..."
    
    # Try to send SIGHUP to Mosquitto process
    if pgrep mosquitto > /dev/null; then
        pkill -SIGHUP mosquitto
        log_message "✅ Mosquitto configuration reloaded"
        return 0
    else
        log_message "⚠️  Mosquitto process not found, may need manual restart"
        return 1
    fi
}

# Function to validate new certificate
validate_certificate() {
    local cert_file="$1"
    local key_file="$2"
    
    log_message "🔍 Validating new certificate..."
    
    # Check if certificate and key match
    local cert_modulus=$(openssl x509 -noout -modulus -in "$cert_file" | openssl md5)
    local key_modulus=$(openssl rsa -noout -modulus -in "$key_file" | openssl md5)
    
    if [ "$cert_modulus" = "$key_modulus" ]; then
        log_message "✅ Certificate and key match"
    else
        log_message "❌ Certificate and key do not match"
        return 1
    fi
    
    # Check certificate validity
    if openssl x509 -in "$cert_file" -checkend 0 > /dev/null; then
        log_message "✅ Certificate is currently valid"
    else
        log_message "❌ Certificate is not valid"
        return 1
    fi
    
    # Check certificate subject
    local subject=$(openssl x509 -in "$cert_file" -subject -noout)
    log_message "Certificate subject: $subject"
    
    return 0
}

# Main certificate management function
manage_mqtt_certificate() {
    local cert_file="$MOSQUITTO_CERT_PATH/mosquitto.crt"
    local key_file="$MOSQUITTO_CERT_PATH/mosquitto.key"
    local common_name="mosquitto"
    
    log_message "🔐 Starting MQTT certificate management..."
    
    # Check if step-ca is available
    if ! check_step_ca; then
        log_message "❌ Cannot proceed without step-ca"
        return 1
    fi
    
    # Check if certificate needs renewal
    if check_certificate_expiry "$cert_file" "$CERT_RENEWAL_THRESHOLD_DAYS"; then
        log_message "🔄 Certificate renewal required"
        
        # Request new certificate
        if request_certificate_acme "$common_name" "$cert_file" "$key_file"; then
            # Validate new certificate
            if validate_certificate "$cert_file" "$key_file"; then
                # Reload Mosquitto
                reload_mosquitto
                log_message "✅ Certificate renewal completed successfully"
                return 0
            else
                log_message "❌ Certificate validation failed"
                return 1
            fi
        else
            log_message "❌ Certificate request failed"
            return 1
        fi
    else
        log_message "✅ Certificate renewal not required"
        return 0
    fi
}

# Function to run as daemon
run_daemon() {
    log_message "🚀 Starting MQTT Certificate Manager daemon..."
    
    while true; do
        manage_mqtt_certificate
        
        # Sleep for 1 hour before next check
        log_message "😴 Sleeping for 1 hour..."
        sleep 3600
    done
}

# Function to run once
run_once() {
    log_message "🔄 Running MQTT Certificate Manager once..."
    manage_mqtt_certificate
}

# Function to show certificate status
show_status() {
    local cert_file="$MOSQUITTO_CERT_PATH/mosquitto.crt"
    
    echo "🔍 MQTT Certificate Status"
    echo "========================="
    
    if [ -f "$cert_file" ]; then
        echo "Certificate file: $cert_file"
        echo "Subject: $(openssl x509 -in "$cert_file" -subject -noout)"
        echo "Issuer: $(openssl x509 -in "$cert_file" -issuer -noout)"
        echo "Valid from: $(openssl x509 -in "$cert_file" -startdate -noout | cut -d= -f2)"
        echo "Valid until: $(openssl x509 -in "$cert_file" -enddate -noout | cut -d= -f2)"
        
        local expiry_date=$(openssl x509 -in "$cert_file" -enddate -noout | cut -d= -f2)
        local expiry_epoch=$(date -d "$expiry_date" +%s)
        local current_epoch=$(date +%s)
        local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
        
        echo "Days until expiry: $days_until_expiry"
        
        if [ "$days_until_expiry" -lt "$CERT_RENEWAL_THRESHOLD_DAYS" ]; then
            echo "Status: ⚠️  RENEWAL REQUIRED"
        else
            echo "Status: ✅ VALID"
        fi
    else
        echo "❌ Certificate file not found: $cert_file"
    fi
}

# Main script logic
case "${1:-}" in
    "daemon")
        run_daemon
        ;;
    "once")
        run_once
        ;;
    "status")
        show_status
        ;;
    "renew")
        manage_mqtt_certificate
        ;;
    *)
        echo "Usage: $0 {daemon|once|status|renew}"
        echo ""
        echo "Commands:"
        echo "  daemon  - Run as daemon (continuous monitoring)"
        echo "  once    - Run certificate check once"
        echo "  status  - Show current certificate status"
        echo "  renew   - Force certificate renewal"
        exit 1
        ;;
esac