#!/bin/bash
set -e

# Certificate monitoring script
# Provides health checks and certificate status information

SERVICE_NAME=${SERVICE_NAME:-"default"}
CERT_DIR="/certs"
CA_CERT_DIR="/ca-certs"

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    
    echo "{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"service\":\"cert-monitor-$SERVICE_NAME\",\"message\":\"$message\"}"
}

# Check certificate validity
check_certificate() {
    local cert_file="$CERT_DIR/cert.pem"
    
    if [ ! -f "$cert_file" ]; then
        log "error" "Certificate file not found: $cert_file"
        return 1
    fi
    
    # Verify certificate
    if ! openssl x509 -in "$cert_file" -noout -checkend 0 > /dev/null 2>&1; then
        log "error" "Certificate is expired or invalid"
        return 1
    fi
    
    # Get certificate details
    local subject=$(openssl x509 -in "$cert_file" -noout -subject | sed 's/subject=//')
    local issuer=$(openssl x509 -in "$cert_file" -noout -issuer | sed 's/issuer=//')
    local not_before=$(openssl x509 -in "$cert_file" -noout -startdate | sed 's/notBefore=//')
    local not_after=$(openssl x509 -in "$cert_file" -noout -enddate | sed 's/notAfter=//')
    
    # Calculate time until expiry
    local expiry_epoch=$(date -d "$not_after" +%s)
    local current_epoch=$(date +%s)
    local time_until_expiry=$((expiry_epoch - current_epoch))
    
    log "info" "Certificate is valid - Subject: $subject, Expires in: ${time_until_expiry}s"
    return 0
}

# Health check endpoint
health_check() {
    if check_certificate; then
        echo "OK"
        exit 0
    else
        echo "FAIL"
        exit 1
    fi
}

# Certificate status
cert_status() {
    local cert_file="$CERT_DIR/cert.pem"
    
    if [ ! -f "$cert_file" ]; then
        echo "{\"status\":\"missing\",\"message\":\"Certificate file not found\"}"
        return 1
    fi
    
    local subject=$(openssl x509 -in "$cert_file" -noout -subject | sed 's/subject=//')
    local issuer=$(openssl x509 -in "$cert_file" -noout -issuer | sed 's/issuer=//')
    local not_before=$(openssl x509 -in "$cert_file" -noout -startdate | sed 's/notBefore=//')
    local not_after=$(openssl x509 -in "$cert_file" -noout -enddate | sed 's/notAfter=//')
    local serial=$(openssl x509 -in "$cert_file" -noout -serial | sed 's/serial=//')
    
    # Calculate time until expiry
    local expiry_epoch=$(date -d "$not_after" +%s)
    local current_epoch=$(date +%s)
    local time_until_expiry=$((expiry_epoch - current_epoch))
    
    local status="valid"
    if [ $time_until_expiry -lt 0 ]; then
        status="expired"
    elif [ $time_until_expiry -lt 300 ]; then  # 5 minutes
        status="expiring_soon"
    fi
    
    echo "{
        \"status\":\"$status\",
        \"subject\":\"$subject\",
        \"issuer\":\"$issuer\",
        \"not_before\":\"$not_before\",
        \"not_after\":\"$not_after\",
        \"serial\":\"$serial\",
        \"time_until_expiry_seconds\":$time_until_expiry,
        \"service_name\":\"$SERVICE_NAME\"
    }"
}

# Main function
case "${1:-status}" in
    "health")
        health_check
        ;;
    "status")
        cert_status
        ;;
    *)
        echo "Usage: $0 {health|status}"
        exit 1
        ;;
esac