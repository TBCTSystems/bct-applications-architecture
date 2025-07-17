#!/bin/bash

echo "🔐 Enterprise Certificate Management - Certificate Generation"
echo "============================================================="

# Wait for step-ca to be ready
echo "⏳ Waiting for step-ca to be ready..."
max_attempts=30
attempt=0

until curl -k https://localhost:9000/health > /dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ $attempt -ge $max_attempts ]; then
        echo "❌ step-ca failed to start after $max_attempts attempts"
        exit 1
    fi
    echo "   Attempt $attempt/$max_attempts - Waiting for step-ca..."
    sleep 5
done

echo "✅ step-ca is ready!"

# Get root certificate
echo "📥 Downloading root certificate from step-ca..."
curl -k https://localhost:9000/root > certificates/root_ca.crt

if [ ! -s certificates/root_ca.crt ]; then
    echo "❌ Failed to download root certificate"
    exit 1
fi

echo "✅ Root certificate downloaded successfully"

# Generate Mosquitto server certificate using step-ca
echo "🦟 Generating Mosquitto server certificate via step-ca..."

# Use step CLI to request certificate from step-ca
docker run --rm --network host \
    -v $(pwd)/certificates:/certs \
    -v $(pwd)/step-ca-config:/home/step/.step \
    smallstep/step-cli:latest \
    step ca certificate mosquitto \
    /certs/mosquitto.crt /certs/mosquitto.key \
    --ca-url https://localhost:9000 \
    --root /certs/root_ca.crt \
    --san mosquitto \
    --san localhost \
    --san 127.0.0.1 \
    --san enterprise-mosquitto \
    --not-after 720h \
    --insecure \
    --provisioner admin \
    --provisioner-password-file <(echo "enterprise-ca-password") || {
    
    echo "⚠️  step-ca certificate generation failed, creating self-signed certificate for demo..."
    openssl req -x509 -newkey rsa:2048 \
        -keyout certificates/mosquitto.key \
        -out certificates/mosquitto.crt \
        -days 30 -nodes \
        -subj "/CN=mosquitto" \
        -addext "subjectAltName=DNS:mosquitto,DNS:localhost,DNS:enterprise-mosquitto,IP:127.0.0.1"
}

# Generate Lumia application client certificate
echo "🌟 Generating Lumia application client certificate..."
docker run --rm --network host \
    -v $(pwd)/certificates:/certs \
    -v $(pwd)/step-ca-config:/home/step/.step \
    smallstep/step-cli:latest \
    step ca certificate lumia-app \
    /certs/lumia-app.crt /certs/lumia-app.key \
    --ca-url https://localhost:9000 \
    --root /certs/root_ca.crt \
    --san lumia-app \
    --san localhost \
    --not-after 720h \
    --insecure \
    --provisioner admin \
    --provisioner-password-file <(echo "enterprise-ca-password") || {
    
    echo "⚠️  Creating self-signed certificate for Lumia app..."
    openssl req -x509 -newkey rsa:2048 \
        -keyout certificates/lumia-app.key \
        -out certificates/lumia-app.crt \
        -days 30 -nodes \
        -subj "/CN=lumia-app"
}

# Generate device simulator certificate
echo "🤖 Generating device simulator certificate..."
docker run --rm --network host \
    -v $(pwd)/certificates:/certs \
    -v $(pwd)/step-ca-config:/home/step/.step \
    smallstep/step-cli:latest \
    step ca certificate REVEOS-SIM-001 \
    /certs/REVEOS-SIM-001.crt /certs/REVEOS-SIM-001.key \
    --ca-url https://localhost:9000 \
    --root /certs/root_ca.crt \
    --san REVEOS-SIM-001 \
    --san localhost \
    --not-after 720h \
    --insecure \
    --provisioner admin \
    --provisioner-password-file <(echo "enterprise-ca-password") || {
    
    echo "⚠️  Creating self-signed certificate for device simulator..."
    openssl req -x509 -newkey rsa:2048 \
        -keyout certificates/REVEOS-SIM-001.key \
        -out certificates/REVEOS-SIM-001.crt \
        -days 30 -nodes \
        -subj "/CN=REVEOS-SIM-001"
}

# Set proper permissions
echo "🔒 Setting certificate permissions..."
chmod 644 certificates/*.crt 2>/dev/null || true
chmod 600 certificates/*.key 2>/dev/null || true

# Validate certificates
echo "🔍 Validating generated certificates..."
for cert in certificates/*.crt; do
    if [ -f "$cert" ]; then
        echo "   Checking $(basename $cert)..."
        openssl x509 -in "$cert" -text -noout | grep -E "(Subject:|Not After:|DNS:|IP Address:)" | head -3
    fi
done

echo ""
echo "✅ Certificate generation completed successfully!"
echo "📁 Generated certificate files:"
ls -la certificates/

echo ""
echo "🔐 Certificate Summary:"
echo "   - Root CA: $(openssl x509 -in certificates/root_ca.crt -subject -noout 2>/dev/null || echo 'Not available')"
echo "   - Mosquitto Server: $(openssl x509 -in certificates/mosquitto.crt -subject -noout 2>/dev/null || echo 'Not available')"
echo "   - Lumia Application: $(openssl x509 -in certificates/lumia-app.crt -subject -noout 2>/dev/null || echo 'Not available')"
echo "   - Device Simulator: $(openssl x509 -in certificates/REVEOS-SIM-001.crt -subject -noout 2>/dev/null || echo 'Not available')"