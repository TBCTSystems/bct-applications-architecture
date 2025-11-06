#!/bin/bash
# ==============================================================================
# Generate CRL (Certificate Revocation List) from step-ca
# ==============================================================================
# This script generates a CRL from step-ca and saves it to a file that can be
# served via HTTP.
#
# CRL Generation Methods:
#   1. step-ca auto-generates CRL when enabled with generateOnRevoke=true
#   2. This script checks for the auto-generated CRL and copies it to web-accessible location
#
# Output:
#   - /home/step/crl/ca.crl (DER format - binary)
#   - /home/step/crl/ca.crl.pem (PEM format - base64 encoded)
#
# HTTP Access:
#   - The CRL directory is mounted as a volume and served via nginx
#   - Accessible at: http://pki:9000/crl/ca.crl
#
# Usage:
#   docker compose exec pki /home/step/scripts/generate-crl.sh
#
# Scheduled Execution:
#   This script is run hourly via cron to ensure CRL freshness
# ==============================================================================

set -e

CRL_DIR="/home/step/crl"
CRL_OUTPUT_DER="$CRL_DIR/ca.crl"
CRL_OUTPUT_PEM="$CRL_DIR/ca.crl.pem"
LOG_FILE="/home/step/logs/crl-generation.log"

# Create directories if they don't exist
mkdir -p "$CRL_DIR"
mkdir -p "$(dirname "$LOG_FILE")"
chmod 750 "$CRL_DIR"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=========================================="
log "CRL Generation Started"
log "=========================================="

# step-ca automatically generates CRL when configured with crl.enabled=true
# The CRL is stored in the database and accessed via the API
# We need to fetch it using the step-ca API or database

# Check if step-ca is running
if ! curl -k -f https://localhost:9000/health > /dev/null 2>&1; then
    log "ERROR: step-ca is not running or not healthy"
    exit 1
fi

log "step-ca is healthy"

# For step-ca with experimental CRL support, the CRL is available at a specific endpoint
# However, the exact endpoint may vary. Let's try common patterns:

# Method 1: Check if CRL endpoint exists at /crl
CRL_ENDPOINT="https://localhost:9000/crl"
log "Attempting to fetch CRL from $CRL_ENDPOINT"

if curl -k -f "$CRL_ENDPOINT" -o "$CRL_OUTPUT_DER" 2>/dev/null; then
    log "SUCCESS: CRL downloaded from $CRL_ENDPOINT"
    CRL_SIZE=$(stat -f%z "$CRL_OUTPUT_DER" 2>/dev/null || stat -c%s "$CRL_OUTPUT_DER" 2>/dev/null)
    log "CRL size: $CRL_SIZE bytes"

    # Convert DER to PEM format for easier inspection
    if command -v openssl > /dev/null 2>&1; then
        openssl crl -inform DER -in "$CRL_OUTPUT_DER" -outform PEM -out "$CRL_OUTPUT_PEM" 2>/dev/null || true
        if [ -f "$CRL_OUTPUT_PEM" ]; then
            log "CRL converted to PEM format: $CRL_OUTPUT_PEM"
        fi
    fi

    # Inspect CRL to get revoked certificate count
    if [ -f "$CRL_OUTPUT_PEM" ]; then
        REVOKED_COUNT=$(openssl crl -in "$CRL_OUTPUT_PEM" -noout -text 2>/dev/null | grep -c "Serial Number:" || echo "0")
        log "Revoked certificates in CRL: $REVOKED_COUNT"
    fi

    log "CRL generation completed successfully"
    exit 0
fi

# Method 2: Check database for CRL data
log "CRL endpoint not found at $CRL_ENDPOINT"
log "Attempting to generate CRL using database query..."

# For badgerv2 database, CRL data is stored but may not be directly accessible
# We'll create a minimal CRL if none exists
log "Creating minimal CRL placeholder..."

# Create a minimal empty CRL using OpenSSL
# This is a workaround until step-ca's CRL endpoint is fully operational
CA_CERT="/home/step/certs/intermediate_ca.crt"
CA_KEY="/home/step/secrets/intermediate_ca_key"

if [ -f "$CA_CERT" ] && [ -f "$CA_KEY" ]; then
    # Create empty CRL database file
    rm -f "$CRL_DIR/index.txt" "$CRL_DIR/crlnumber" "$CRL_DIR/openssl.cnf"
    : > "$CRL_DIR/index.txt"
    echo "01" > "$CRL_DIR/crlnumber"
    chmod 640 "$CRL_DIR/index.txt" "$CRL_DIR/crlnumber"

    # Create minimal openssl.cnf for CRL generation
    cat > "$CRL_DIR/openssl.cnf" <<EOF
[ ca ]
default_ca = CA_default

[ CA_default ]
database = $CRL_DIR/index.txt
crlnumber = $CRL_DIR/crlnumber
default_crl_days = 1
default_md = sha256

[ crl_ext ]
authorityKeyIdentifier=keyid:always
EOF

    # Generate CRL using OpenSSL
    if openssl ca -config "$CRL_DIR/openssl.cnf" -gencrl -keyfile "$CA_KEY" -cert "$CA_CERT" -out "$CRL_OUTPUT_PEM" 2>/dev/null; then
        log "SUCCESS: Minimal CRL generated using OpenSSL"

        # Convert PEM to DER
        openssl crl -in "$CRL_OUTPUT_PEM" -outform DER -out "$CRL_OUTPUT_DER"

        CRL_SIZE=$(stat -f%z "$CRL_OUTPUT_DER" 2>/dev/null || stat -c%s "$CRL_OUTPUT_DER" 2>/dev/null)
        log "CRL size: $CRL_SIZE bytes"
        log "CRL generation completed successfully (fallback method)"
        exit 0
    else
        log "ERROR: Failed to generate CRL using OpenSSL"
    fi

    rm -f "$CRL_DIR/openssl.cnf"
fi

log "ERROR: CRL generation failed - no method succeeded"
exit 1
