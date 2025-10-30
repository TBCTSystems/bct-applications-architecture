#!/bin/bash
set -eo pipefail

echo "[INIT] Starting simple PKI initialization..."

export STEPPATH="/home/step"

# Check if CA is already initialized
if [ ! -f "${STEPPATH}/config/ca.json" ]; then
    echo "[INIT] CA not initialized, running step ca init..."

    # Create password file with empty password
    mkdir -p "${STEPPATH}"
    echo "" > "${STEPPATH}/password"
    chmod 600 "${STEPPATH}/password"

    # CRITICAL: step ca init has TWO password prompts:
    # 1. CA key password (satisfied by --password-file)
    # 2. Provisioner password (hidden prompt that STILL appears!)
    # Solution: Pipe password to stdin using here-string to satisfy provisioner prompt
    step ca init \
        --name="ECA-PoC-CA" \
        --dns="pki,localhost" \
        --address=":9000" \
        --provisioner="admin" \
        --password-file="${STEPPATH}/password" \
        <<<"$(cat ${STEPPATH}/password)"

    echo "[INIT] CA initialized successfully"

    # Move password file to secrets directory for step-ca to use
    mkdir -p "${STEPPATH}/secrets"
    mv "${STEPPATH}/password" "${STEPPATH}/secrets/password"
    rm -f "${STEPPATH}/provisioner_password"  # Don't need this after init
else
    echo "[INIT] CA already initialized, skipping init"
fi

echo "[INIT] Starting step-ca..."
exec step-ca "${STEPPATH}/config/ca.json" --password-file="${STEPPATH}/secrets/password"
