#!/bin/bash
set -e

# Certificate renewal script for step-ca ACME
# This script runs continuously and renews certificates every RENEWAL_INTERVAL seconds

# Configuration from environment variables
SERVICE_NAME=${SERVICE_NAME:-"default"}
CERT_DOMAIN=${CERT_DOMAIN:-"localhost"}
STEP_CA_URL=${STEP_CA_URL:-"https://ca.localtest.me:9000"}
RENEWAL_INTERVAL=${RENEWAL_INTERVAL:-300}  # 5 minutes default
DEBUG=${DEBUG:-false}
LOG_LEVEL=${LOG_LEVEL:-info}

# Directories
CERT_DIR="/certs"
CA_CERT_DIR="/ca-certs"
LOG_DIR="/var/log/certbot"

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    
    echo "{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"service\":\"certbot-$SERVICE_NAME\",\"message\":\"$message\",\"cert_domain\":\"$CERT_DOMAIN\"}" | tee -a "$LOG_DIR/certbot.log"
}

# Wait for step-ca to be ready
wait_for_step_ca() {
    log "info" "Waiting for step-ca to be ready at $STEP_CA_URL"
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -k -s "$STEP_CA_URL/health" > /dev/null 2>&1; then
            log "info" "step-ca is ready"
            return 0
        fi
        
        log "info" "Attempt $attempt/$max_attempts: step-ca not ready, waiting 10 seconds..."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    log "error" "step-ca failed to become ready after $max_attempts attempts"
    exit 1
}

# Download CA certificate
download_ca_cert() {
    log "info" "Downloading CA certificates from step-ca"
    
    # Create CA cert directory if it doesn't exist
    mkdir -p "$CA_CERT_DIR"
    
    # Download root CA certificate
    if curl -k -s "$STEP_CA_URL/roots.pem" -o "$CA_CERT_DIR/root_ca.crt"; then
        log "info" "Successfully downloaded root CA certificate"
        
        # Verify the root certificate
        if openssl x509 -in "$CA_CERT_DIR/root_ca.crt" -text -noout > /dev/null 2>&1; then
            log "info" "Root CA certificate is valid"
        else
            log "error" "Downloaded root CA certificate is invalid"
            exit 1
        fi
    else
        log "error" "Failed to download root CA certificate"
        exit 1
    fi
    
    # Download intermediate CA certificate from step-ca
    log "info" "Downloading intermediate CA certificate"
    
    # Try multiple methods to get the intermediate CA
    local intermediate_downloaded=false
    
    # Method 1: Try to get it via HTTP endpoint (if available)
    if curl -k -s "$STEP_CA_URL/intermediate.pem" -o "$CA_CERT_DIR/intermediate_ca.crt" 2>/dev/null; then
        if openssl x509 -in "$CA_CERT_DIR/intermediate_ca.crt" -text -noout > /dev/null 2>&1; then
            log "info" "Successfully downloaded intermediate CA via HTTP endpoint"
            intermediate_downloaded=true
        fi
    fi
    
    # Method 2: Try docker cp from step-ca container
    if [ "$intermediate_downloaded" = false ]; then
        if docker cp step-ca:/home/step/certs/intermediate_ca.crt "$CA_CERT_DIR/intermediate_ca.crt" 2>/dev/null; then
            if openssl x509 -in "$CA_CERT_DIR/intermediate_ca.crt" -text -noout > /dev/null 2>&1; then
                log "info" "Successfully downloaded intermediate CA via docker cp"
                intermediate_downloaded=true
            fi
        fi
    fi
    
    # Method 3: Try docker exec to extract from step-ca
    if [ "$intermediate_downloaded" = false ]; then
        if docker exec step-ca cat /home/step/certs/intermediate_ca.crt > "$CA_CERT_DIR/intermediate_ca.crt" 2>/dev/null; then
            if openssl x509 -in "$CA_CERT_DIR/intermediate_ca.crt" -text -noout > /dev/null 2>&1; then
                log "info" "Successfully extracted intermediate CA via docker exec"
                intermediate_downloaded=true
            fi
        fi
    fi
    
    # If no intermediate CA found, use root CA only
    if [ "$intermediate_downloaded" = false ]; then
        log "warning" "No intermediate CA certificate found, using root CA only"
        cp "$CA_CERT_DIR/root_ca.crt" "$CA_CERT_DIR/ca_chain.crt"
        return 0
    fi
    
    # Create certificate chain (root + intermediate)
    log "info" "Creating certificate chain"
    cat "$CA_CERT_DIR/root_ca.crt" "$CA_CERT_DIR/intermediate_ca.crt" > "$CA_CERT_DIR/ca_chain.crt"
    
    # Verify the chain
    if openssl verify -CAfile "$CA_CERT_DIR/ca_chain.crt" "$CA_CERT_DIR/intermediate_ca.crt" > /dev/null 2>&1; then
        log "info" "Certificate chain is valid"
    else
        log "warning" "Certificate chain verification failed, but continuing"
    fi
    
    # Distribute certificate chain to other containers
    distribute_certificate_chain
}

# Distribute certificate chain to consuming containers
distribute_certificate_chain() {
    log "info" "Distributing certificate chain to consuming containers"
    
    # List of containers that need the certificate chain
    local containers=("mosquitto" "device-simulator")
    
    for container in "${containers[@]}"; do
        # Check if container exists and is running
        if docker ps --format "table {{.Names}}" | grep -q "^${container}$"; then
            log "info" "Distributing certificates to container: $container"
            
            # Determine the target directory based on container
            local target_dir
            case $container in
                "mosquitto")
                    target_dir="/mosquitto/ca"
                    ;;
                "device-simulator")
                    target_dir="/ca-certs"
                    ;;
                *)
                    target_dir="/ca-certs"
                    ;;
            esac
            
            # Copy certificates to the container
            if docker exec "$container" mkdir -p "$target_dir" 2>/dev/null; then
                # Copy individual certificates
                docker cp "$CA_CERT_DIR/root_ca.crt" "$container:$target_dir/root_ca.crt" 2>/dev/null || log "warning" "Failed to copy root CA to $container"
                
                if [ -f "$CA_CERT_DIR/intermediate_ca.crt" ]; then
                    docker cp "$CA_CERT_DIR/intermediate_ca.crt" "$container:$target_dir/intermediate_ca.crt" 2>/dev/null || log "warning" "Failed to copy intermediate CA to $container"
                fi
                
                # Copy complete chain
                docker cp "$CA_CERT_DIR/ca_chain.crt" "$container:$target_dir/ca_chain.crt" 2>/dev/null || log "warning" "Failed to copy certificate chain to $container"
                
                log "info" "Successfully distributed certificates to $container"
            else
                log "warning" "Failed to create certificate directory in container: $container"
            fi
        else
            log "info" "Container $container not running, skipping certificate distribution"
        fi
    done
}

# Request certificate using certbot
request_certificate() {
    log "info" "Requesting certificate for domain: $CERT_DOMAIN"
    
    # Create certificate directory
    mkdir -p "$CERT_DIR"
    
    # Install CA certificate for SSL verification
    if [ -f "$CA_CERT_DIR/ca_chain.crt" ]; then
        cp "$CA_CERT_DIR/ca_chain.crt" /usr/local/share/ca-certificates/step-ca-chain.crt
        update-ca-certificates
        log "info" "Installed step-ca certificate chain for SSL verification"
    elif [ -f "$CA_CERT_DIR/root_ca.crt" ]; then
        cp "$CA_CERT_DIR/root_ca.crt" /usr/local/share/ca-certificates/step-ca.crt
        update-ca-certificates
        log "info" "Installed step-ca root certificate for SSL verification"
    fi
    
    # Prepare certbot command with standalone mode for HTTP-01 challenge
    local certbot_cmd="certbot certonly \
        --server $STEP_CA_URL/acme/acme/directory \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email admin@$CERT_DOMAIN \
        --domains $CERT_DOMAIN \
        --config-dir /etc/letsencrypt \
        --work-dir /var/lib/letsencrypt \
        --logs-dir /var/log/letsencrypt \
        --no-verify-ssl"
    
    if [ "$DEBUG" = "true" ]; then
        certbot_cmd="$certbot_cmd --verbose"
    fi
    
    # Execute certbot
    if eval $certbot_cmd; then
        log "info" "Certificate requested successfully"
        
        # Copy certificates to the expected locations
        copy_certificates
        
        return 0
    else
        log "error" "Failed to request certificate"
        return 1
    fi
}

# Copy certificates to expected locations
copy_certificates() {
    local live_dir="/etc/letsencrypt/live/$CERT_DOMAIN"
    
    if [ -d "$live_dir" ]; then
        log "info" "Copying certificates to $CERT_DIR"
        
        cp "$live_dir/fullchain.pem" "$CERT_DIR/fullchain.pem" 2>/dev/null || true
        cp "$live_dir/privkey.pem" "$CERT_DIR/privkey.pem" 2>/dev/null || true
        cp "$live_dir/cert.pem" "$CERT_DIR/cert.pem" 2>/dev/null || true
        cp "$live_dir/chain.pem" "$CERT_DIR/chain.pem" 2>/dev/null || true
        
        # Set appropriate permissions
        chmod 644 "$CERT_DIR"/*.pem 2>/dev/null || true
        chmod 600 "$CERT_DIR/privkey.pem" 2>/dev/null || true
        
        log "info" "Certificates copied successfully"
    else
        log "error" "Certificate directory $live_dir not found"
    fi
}

# Check if certificate needs renewal
needs_renewal() {
    local cert_file="$CERT_DIR/cert.pem"
    
    if [ ! -f "$cert_file" ]; then
        log "info" "Certificate file not found, renewal needed"
        return 0
    fi
    
    # Check certificate expiration (renew if expires within 2 minutes)
    local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s)
    local current_epoch=$(date +%s)
    local time_until_expiry=$((expiry_epoch - current_epoch))
    
    if [ $time_until_expiry -lt 120 ]; then  # 2 minutes
        log "info" "Certificate expires in $time_until_expiry seconds, renewal needed"
        return 0
    else
        log "info" "Certificate valid for $time_until_expiry seconds, no renewal needed"
        return 1
    fi
}

# Main renewal loop
main() {
    log "info" "Starting certbot renewal service for $SERVICE_NAME"
    log "info" "Configuration: domain=$CERT_DOMAIN, renewal_interval=${RENEWAL_INTERVAL}s, debug=$DEBUG"
    
    # Initial setup
    wait_for_step_ca
    download_ca_cert
    
    # Initial certificate request
    if ! request_certificate; then
        log "error" "Failed to obtain initial certificate"
        exit 1
    fi
    
    # Continuous renewal loop
    while true; do
        log "info" "Checking if certificate renewal is needed"
        
        if needs_renewal; then
            log "info" "Starting certificate renewal"
            
            if request_certificate; then
                log "info" "Certificate renewed successfully"
            else
                log "error" "Certificate renewal failed"
            fi
        fi
        
        log "info" "Sleeping for $RENEWAL_INTERVAL seconds until next check"
        sleep $RENEWAL_INTERVAL
    done
}

# Handle signals for graceful shutdown
trap 'log "info" "Received shutdown signal, exiting..."; exit 0' SIGTERM SIGINT

# Start the main process
main