#!/bin/bash
# ==============================================================================
# Enable CRL (Certificate Revocation List) in step-ca
# ==============================================================================
# This script enables experimental CRL support in step-ca by modifying ca.json
# and restarting the CA service.
#
# CRL Configuration:
#   - enabled: true (enable CRL generation)
#   - generateOnRevoke: true (auto-generate CRL when certificate is revoked)
#   - cacheDuration: 1h (CRL validity period - update hourly)
#   - renewPeriod: 40m (renew at ~2/3 of cache duration)
#
# Usage:
#   docker compose exec pki /home/step/scripts/enable-crl.sh
# ==============================================================================

set -e

CONFIG_FILE="/home/step/config/ca.json"
BACKUP_FILE="/home/step/config/ca.json.backup-$(date +%Y%m%d-%H%M%S)"

echo "[CRL] Enabling CRL support in step-ca..."

# Backup current configuration
echo "[CRL] Backing up ca.json to $BACKUP_FILE"
cp "$CONFIG_FILE" "$BACKUP_FILE"

# Check if CRL section already exists
if grep -q '"crl"' "$CONFIG_FILE"; then
    echo "[CRL] CRL section already exists in ca.json - updating configuration"
    # Update existing CRL configuration using jq
    jq '.crl.enabled = true | .crl.generateOnRevoke = true | .crl.cacheDuration = "1h"' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
else
    echo "[CRL] Adding CRL section to ca.json"
    # Add CRL configuration after authority section using jq
    jq '. + {"crl": {"enabled": true, "generateOnRevoke": true, "cacheDuration": "1h"}}' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
fi

echo "[CRL] CRL configuration updated successfully"
echo "[CRL] Configuration:"
jq '.crl' "$CONFIG_FILE"

# Create CRL directory if it doesn't exist
CRL_DIR="/home/step/crl"
if [ ! -d "$CRL_DIR" ]; then
    echo "[CRL] Creating CRL directory: $CRL_DIR"
    mkdir -p "$CRL_DIR"
fi

echo "[CRL] CRL enabled successfully"
echo "[CRL] NOTE: step-ca must be restarted for changes to take effect"
echo "[CRL] Run: docker compose restart pki"
