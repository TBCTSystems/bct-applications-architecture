#!/usr/bin/env bash
################################################################################
# EST Server Startup Script
#
# Purpose: Initialize EST server and start the service (without client cert validation)
#
# This script:
#   1. Runs initialization to get certificates from step-ca
#   2. Starts the estserver process WITHOUT client certificate validation
#      to demonstrate the complete EST enrollment and renewal lifecycle
#
################################################################################

set -e

echo "[START] Starting EST server..."

# Run initialization
/usr/local/bin/init-est.sh

# Start EST server WITHOUT client certificate validation
# This allows the agent to test initial enrollment and re-enrollment workflows
# Note: Removing -client-cas parameter allows open enrollment for PoC purposes
echo "[INFO] Starting EST server on port 8443 (OPEN ENROLLMENT MODE FOR PoC)"
echo "[INFO] Client certificate validation: DISABLED"
echo "[INFO] EST endpoints: https://<host>:8443/.well-known/est/"
echo ""

exec /usr/local/bin/estserver \
    -root-cert /est/data/root_ca.pem \
    -tls-cert /est/data/est-tls.pem \
    -tls-key /est/secrets/est-tls.key \
    -ca-cert /est/data/est-ca.pem \
    -ca-key /est/secrets/est-ca.key \
    -port 8443
