#!/bin/bash
# OpenXPKI CA Initialization Script
# This script imports the step-ca intermediate CA into OpenXPKI
# and configures it for EST enrollment

set -e

echo "=========================================="
echo "OpenXPKI EST Integration - CA Import"
echo "=========================================="

REALM="democa"
CA_NAME="est-ca"

echo ""
echo "[1/5] Verifying step-ca intermediate CA files..."
if [ ! -f "/etc/openxpki/local/secrets/est-ca.crt" ]; then
    echo "ERROR: EST CA certificate not found at /etc/openxpki/local/secrets/est-ca.crt"
    exit 1
fi

if [ ! -f "/etc/openxpki/local/secrets/est-ca.key" ]; then
    echo "ERROR: EST CA private key not found at /etc/openxpki/local/secrets/est-ca.key"
    exit 1
fi

if [ ! -f "/etc/openxpki/local/secrets/root-ca.crt" ]; then
    echo "ERROR: Root CA certificate not found at /etc/openxpki/local/secrets/root-ca.crt"
    exit 1
fi

echo "✓ All CA files found"

echo ""
echo "[2/5] Creating CA directories..."
mkdir -p /etc/openxpki/local/keys/${REALM}
mkdir -p /etc/openxpki/ca/${REALM}

echo "✓ Directories created"

echo ""
echo "[3/5] Importing EST intermediate CA..."

# Import the CA certificate
cp /etc/openxpki/local/secrets/est-ca.crt /etc/openxpki/ca/${REALM}/${CA_NAME}.crt
chmod 644 /etc/openxpki/ca/${REALM}/${CA_NAME}.crt

# Import the CA private key (OpenXPKI expects password-protected keys)
# For this PoC we're using an unencrypted key, which OpenXPKI supports
cp /etc/openxpki/local/secrets/est-ca.key /etc/openxpki/local/keys/${REALM}/${CA_NAME}.pem
chmod 600 /etc/openxpki/local/keys/${REALM}/${CA_NAME}.pem

# Import the root CA for chain building
cp /etc/openxpki/local/secrets/root-ca.crt /etc/openxpki/ca/${REALM}/root.crt
chmod 644 /etc/openxpki/ca/${REALM}/root.crt

echo "✓ CA imported successfully"

echo ""
echo "[4/5] Displaying CA information..."
openssl x509 -in /etc/openxpki/ca/${REALM}/${CA_NAME}.crt -noout -subject -issuer -dates

echo ""
echo "[5/5] Verifying certificate chain..."
openssl verify -CAfile /etc/openxpki/ca/${REALM}/root.crt /etc/openxpki/ca/${REALM}/${CA_NAME}.crt

echo ""
echo "=========================================="
echo "✓ OpenXPKI CA import completed"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Configure realm to use ${CA_NAME}"
echo "2. Restart OpenXPKI server"
echo "3. Run sample configuration: /etc/openxpki/contrib/sampleconfig.sh"
echo "4. Test EST endpoint: https://localhost:8443/.well-known/est/"
echo ""
