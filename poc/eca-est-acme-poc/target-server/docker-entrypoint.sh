#!/bin/sh
# ==============================================================================
# NGINX Target Server Entrypoint Script
# ==============================================================================
#
# This script solves the bootstrap problem where NGINX requires SSL certificates
# to start, but the ACME agent needs NGINX running to complete HTTP-01 validation.
#
# Solution: Create temporary self-signed certificates if real certificates don't exist.
# When the ACME agent obtains real certificates, NGINX reloads automatically.
#
# ==============================================================================

set -e

CERT_PATH="/certs/server/cert.pem"
KEY_PATH="/certs/server/key.pem"

echo "[ENTRYPOINT] Checking for SSL certificates..."

# Check if real certificates exist
if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
    echo "[ENTRYPOINT] SSL certificates not found - creating temporary self-signed certificate"
    echo "[ENTRYPOINT] Certificate path: $CERT_PATH"
    echo "[ENTRYPOINT] Key path: $KEY_PATH"

    # Create /certs/server directory if it doesn't exist
    mkdir -p /certs/server

    # Generate temporary self-signed certificate
    # - Valid for 1 day (will be replaced by real certificate from ACME agent)
    # - Uses RSA 2048-bit key
    # - Subject: CN=target-server-bootstrap
    openssl req -x509 \
        -newkey rsa:2048 \
        -nodes \
        -keyout "$KEY_PATH" \
        -out "$CERT_PATH" \
        -days 1 \
        -subj "/CN=target-server-bootstrap" \
        2>&1 | sed 's/^/[OPENSSL] /'

    # Set correct permissions
    chmod 644 "$CERT_PATH"
    chmod 600 "$KEY_PATH"

    echo "[ENTRYPOINT] Temporary self-signed certificate created successfully"
    echo "[ENTRYPOINT] This certificate will be automatically replaced when ACME agent obtains a real certificate"
else
    echo "[ENTRYPOINT] SSL certificates found - using existing certificates"
fi

echo "[ENTRYPOINT] Starting NGINX..."

# Execute the official NGINX entrypoint script
# This handles all the standard NGINX initialization (templates, configuration, etc.)
exec /docker-entrypoint.sh "$@"
