#!/bin/bash

echo "🔐 Initializing step-ca Certificate Authority..."

# Create step-ca directories if they don't exist
mkdir -p step-ca-config/certs
mkdir -p step-ca-config/secrets
mkdir -p step-ca-config/db

# Generate step-ca configuration if it doesn't exist
if [ ! -f "step-ca-config/ca.json" ]; then
    echo "📝 Creating step-ca configuration..."
    
    # Initialize step-ca with Docker
    docker run --rm -v $(pwd)/step-ca-config:/home/step/.step \
        smallstep/step-ca:latest \
        step ca init \
        --name="Enterprise Root CA" \
        --dns="step-ca,localhost,127.0.0.1" \
        --address=":9000" \
        --provisioner="admin" \
        --password-file=<(echo "enterprise-ca-password") \
        --no-password-prompt
    
    echo "✅ step-ca initialized successfully"
else
    echo "ℹ️  step-ca already initialized"
fi

# Add ACME provisioner if not present
echo "🔧 Configuring ACME provisioner..."
docker run --rm -v $(pwd)/step-ca-config:/home/step/.step \
    smallstep/step-ca:latest \
    step ca provisioner add acme --type ACME || echo "ACME provisioner may already exist"

# Add X5C provisioner for certificate-based authentication
echo "🔧 Configuring X5C provisioner..."
docker run --rm -v $(pwd)/step-ca-config:/home/step/.step \
    smallstep/step-ca:latest \
    step ca provisioner add x5c --type X5C \
    --x5c-roots /home/step/.step/certs/root_ca.crt || echo "X5C provisioner may already exist"

echo "✅ step-ca configuration complete!"

# Set proper permissions
chmod -R 755 step-ca-config/
chmod 600 step-ca-config/secrets/* 2>/dev/null || true

echo "📋 step-ca Configuration Summary:"
echo "   - Root CA: Enterprise Root CA"
echo "   - Address: :9000"
echo "   - DNS Names: step-ca, localhost, 127.0.0.1"
echo "   - Provisioners: admin (JWK), acme (ACME), x5c (X5C)"
echo "   - Password: enterprise-ca-password"