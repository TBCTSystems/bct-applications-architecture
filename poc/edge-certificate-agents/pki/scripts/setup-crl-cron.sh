#!/bin/bash
# ==============================================================================
# Setup CRL Generation Cron Job
# ==============================================================================
# Configures hourly CRL generation via cron
#
# Schedule: Every hour at :05 (e.g., 00:05, 01:05, 02:05, etc.)
# ==============================================================================

set -e

CRL_SCRIPT="/home/step/scripts/generate-crl.sh"

echo "[CRL-CRON] Setting up CRL generation cron job..."

# Install user crontab entry (run every hour at :05)
if command -v crontab > /dev/null 2>&1; then
    TMP_CRON=$(mktemp)
    trap 'rm -f "$TMP_CRON"' EXIT
    echo "5 * * * * $CRL_SCRIPT" > "$TMP_CRON"
    crontab "$TMP_CRON"
    echo "[CRL-CRON] Cron job installed for user $(id -un)"
    rm -f "$TMP_CRON"
    trap - EXIT
else
    echo "[CRL-CRON] WARNING: crontab command not found - skipping cron installation"
fi

# Start crond if not running (Alpine Linux)
if command -v crond > /dev/null 2>&1; then
    if ! pidof crond > /dev/null 2>&1; then
        echo "[CRL-CRON] Starting crond..."
        crond -b -l 2
        echo "[CRL-CRON] crond started successfully"
    else
        echo "[CRL-CRON] crond already running"
    fi
else
    echo "[CRL-CRON] WARNING: crond not found - install with 'apk add dcron'"
fi

# Run initial CRL generation
echo "[CRL-CRON] Running initial CRL generation..."
"$CRL_SCRIPT"

echo "[CRL-CRON] CRL cron setup complete"
