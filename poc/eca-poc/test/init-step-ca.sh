#!/bin/bash
# Step CA Initialization Script for Testing
# This script initializes a Step CA instance with BOTH JWK and EST provisioners
# for testing the certificate renewal service

set -e

echo "Step CA Test Environment Initialization (JWK + EST Support)"
echo "==========================================================="

# Configuration
STEP_CA_NAME="Test-CA"
STEP_CA_DNS="localhost,step-ca,127.0.0.1"
STEP_CA_ADDRESS=":9000"
STEP_CA_PROVISIONER="admin"
STEP_CA_PASSWORD="testpassword"
STEP_CA_PROVISIONER_PASSWORD="adminpassword"
ENABLE_EST="${ENABLE_EST_PROVISIONER:-true}"

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
    echo "✅ Step CA initialized successfully with JWK provisioner!"
    
    # Add EST provisioner if enabled
    if [ "$ENABLE_EST" = "true" ]; then
        echo ""
        echo "⚙️  Adding EST provisioner for dual protocol support..."
        
        # Add EST provisioner to ca.json
        python3 << 'EOF'
import json
import sys
import os

steppath = os.environ.get('STEPPATH', 'test/step-ca')
config_path = os.path.join(steppath, 'config', 'ca.json')

try:
    with open(config_path, 'r') as f:
        config = json.load(f)
    
    # Check if EST provisioner already exists
    provisioners = config.get("authority", {}).get("provisioners", [])
    est_exists = any(p.get("type") == "EST" for p in provisioners)
    
    if not est_exists:
        # Add EST provisioner
        est_provisioner = {
            "type": "EST",
            "name": "est-provisioner"
        }
        provisioners.append(est_provisioner)
        config["authority"]["provisioners"] = provisioners
        
        with open(config_path, 'w') as f:
            json.dump(config, f, indent=2)
        
        print("✅ EST provisioner added successfully")
    else:
        print("✅ EST provisioner already exists")
    
    sys.exit(0)

except Exception as e:
    print(f"❌ Error adding EST provisioner: {e}", file=sys.stderr)
    sys.exit(1)
EOF
        
        if [ $? -eq 0 ]; then
            echo "✅ EST provisioner configured successfully"
        else
            echo "⚠️  Warning: Could not add EST provisioner automatically"
            echo "   You can add it later using: step ca provisioner add est-provisioner --type EST"
        fi
    fi
    
    # Get CA fingerprint
    FINGERPRINT=$(step certificate fingerprint "$STEPPATH/certs/root_ca.crt")
    echo ""
    echo "🔑 CA Fingerprint: $FINGERPRINT"
    
    # Save fingerprint to file for easy access
    echo "$FINGERPRINT" > "test/ca-fingerprint.txt"
    
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "✅ Step CA Configuration (JWK + EST Support)"
    echo "═══════════════════════════════════════════════════════"
    echo "  Name:            $STEP_CA_NAME"
    echo "  Address:         https://localhost:9000"
    echo "  Root CA:         $STEPPATH/certs/root_ca.crt"
    echo "  Fingerprint:     $FINGERPRINT"
    echo ""
    echo "Provisioners:"
    echo "  1. JWK  (admin)           - Step CA native"
    echo "     Password: $STEP_CA_PROVISIONER_PASSWORD"
    echo ""
    if [ "$ENABLE_EST" = "true" ]; then
        echo "  2. EST  (est-provisioner) - RFC 7030"
        echo "     Username: est-client"
        echo "     Password: est-secret"
    fi
    echo ""
    echo "Endpoints:"
    echo "  JWK: https://localhost:9000"
    if [ "$ENABLE_EST" = "true" ]; then
        echo "  EST: https://localhost:9000/.well-known/est/"
    fi
    echo ""
    echo "To start the CA server:"
    echo "  step-ca $STEPPATH/config/ca.json"
    echo ""
    echo "Or using Docker:"
    echo "  cd test && docker-compose -f docker-compose.test.yml up -d step-ca-test"
    echo ""
    echo "Test JWK: docker exec step-ca-test step ca health"
    if [ "$ENABLE_EST" = "true" ]; then
        echo "Test EST: curl -k https://localhost:9000/.well-known/est/cacerts"
    fi
    echo "═══════════════════════════════════════════════════════"
    
else
    echo "❌ ERROR: Failed to initialize Step CA"
    exit 1
fi