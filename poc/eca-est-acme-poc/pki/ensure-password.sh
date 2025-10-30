#!/bin/bash
set -eo pipefail

echo "[WRAPPER] Starting PKI initialization wrapper..."

# If CA is not initialized, call base entrypoint to initialize
if [ ! -f "/home/step/config/ca.json" ]; then
    echo "[WRAPPER] CA not initialized, calling base entrypoint for init..."
    # Redirect stdout to suppress the password display that requires TTY
    /bin/bash /entrypoint.sh "$@" 2>&1 | grep -v "Your CA administrative password" || true
    # The base entrypoint will exit after trying to start step-ca and failing
    # That's OK - we'll start it ourselves next
fi

# Ensure password file exists
echo "[WRAPPER] Ensuring password file exists..."
mkdir -p /home/step/secrets
if [ ! -f "/home/step/secrets/password" ]; then
    echo "${DOCKER_STEPCA_INIT_PASSWORD:-}" > /home/step/secrets/password
    chmod 600 /home/step/secrets/password
    chown step:step /home/step/secrets/password 2>/dev/null || true
fi

# Now start step-ca directly, bypassing the base entrypoint
echo "[WRAPPER] Starting step-ca..."

# Pipe empty password to stdin AND use password file to handle all password prompts
echo "" | exec step-ca "/home/step/config/ca.json" --password-file="/home/step/secrets/password"
