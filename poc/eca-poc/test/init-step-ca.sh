#!/bin/bash
# Step CA Initialization Script for Testing
# This script initializes a Step CA instance for testing the certificate renewal service

set -e

echo "Step CA Test Environment Initialization"
echo "========================================"

# Configuration
STEP_CA_NAME="Test-CA"
STEP_CA_DNS="localhost,step-ca,127.0.0.1"
STEP_CA_ADDRESS=":9000"
STEP_CA_PROVISIONER="admin"
STEP_CA_PASSWORD="testpassword"
STEP_CA_PROVISIONER_PASSWORD="adminpassword"

# Set STEPPATH to test directory
export STEPPATH="$(pwd)/test/step-ca"

echo "STEPPATH set to: $STEPPATH"

# Create step-ca directory if it doesn't exist
mkdir -p "$STEPPATH"

# Remove existing CA configuration if present
if [ -d "$STEPPATH/config" ]; then
    echo "Removing existing CA configuration..."
    rm -rf "$STEPPATH/config"
fi

echo "Initializing Step CA..."

# Create password files
echo "$STEP_CA_PASSWORD" > /tmp/ca_password.txt
echo "$STEP_CA_PROVISIONER_PASSWORD" > /tmp/provisioner_password.txt

# Initialize Step CA
step ca init \
    --name="$STEP_CA_NAME" \
    --dns="$STEP_CA_DNS" \
    --address="$STEP_CA_ADDRESS" \
    --provisioner="$STEP_CA_PROVISIONER" \
    --password-file="/tmp/ca_password.txt" \
    --provisioner-password-file="/tmp/provisioner_password.txt" \
    --no-db

# Clean up password files
rm -f /tmp/ca_password.txt /tmp/provisioner_password.txt

if [ $? -eq 0 ]; then
    echo "Step CA initialized successfully!"
    
    # Get CA fingerprint
    FINGERPRINT=$(step certificate fingerprint "$STEPPATH/certs/root_ca.crt")
    echo "CA Fingerprint: $FINGERPRINT"
    
    # Save fingerprint to file for easy access
    echo "$FINGERPRINT" > "test/ca-fingerprint.txt"
    
    echo ""
    echo "Step CA Configuration:"
    echo "  Name: $STEP_CA_NAME"
    echo "  Address: https://localhost:9000"
    echo "  Provisioner: $STEP_CA_PROVISIONER"
    echo "  Password: $STEP_CA_PROVISIONER_PASSWORD"
    echo "  Root CA: $STEPPATH/certs/root_ca.crt"
    echo "  Fingerprint: $FINGERPRINT"
    echo ""
    echo "To start the CA server:"
    echo "  step-ca \$STEPPATH/config/ca.json"
    echo ""
    echo "Or using Docker:"
    echo "  cd test && docker-compose -f docker-compose.test.yml up -d step-ca-test"
    
else
    echo "ERROR: Failed to initialize Step CA"
    exit 1
fi