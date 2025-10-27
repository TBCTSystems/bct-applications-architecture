#!/bin/bash
# ==============================================================================
# Setup CRL Generation Cron Job
# ==============================================================================
# Configures hourly CRL generation via cron
#
# Schedule: Every hour at :05 (e.g., 00:05, 01:05, 02:05, etc.)
# ==============================================================================

set -e

CRON_FILE="/etc/crontabs/step"
CRL_SCRIPT="/home/step/scripts/generate-crl.sh"

echo "[CRL-CRON] Setting up CRL generation cron job..."

# Create crontab directory if it doesn't exist
mkdir -p "$(dirname "$CRON_FILE")"

# Add cron job (run every hour at :05)
# Format: minute hour day month weekday command
echo "5 * * * * $CRL_SCRIPT" > "$CRON_FILE"

echo "[CRL-CRON] Cron job configured:"
cat "$CRON_FILE"

# Start crond if not running (Alpine Linux)
if command -v crond > /dev/null 2>&1; then
    echo "[CRL-CRON] Starting crond..."
    crond -b -l 2
    echo "[CRL-CRON] crond started successfully"
else
    echo "[CRL-CRON] WARNING: crond not found - install with 'apk add dcron'"
fi

# Run initial CRL generation
echo "[CRL-CRON] Running initial CRL generation..."
"$CRL_SCRIPT"

echo "[CRL-CRON] CRL cron setup complete"
