#!/bin/bash

# Wait for step-ca to be ready
echo "⏳ Waiting for step-ca to be ready..."
until curl -k https://localhost:9000/health > /dev/null 2>&1; do
    sleep 2
done

# Get root certificate
echo "📥 Downloading root certificate..."
curl -k https://localhost:9000/root > certificates/root_ca.crt

# Generate Mosquitto server certificate
echo "🦟 Generating Mosquitto server certificate..."
docker run --rm --network host -v $(pwd)/certificates:/certs \
    smallstep/step-cli:latest \
    step ca certificate mosquitto /certs/mosquitto.crt /certs/mosquitto.key \
    --ca-url https://localhost:9000 \
    --root /certs/root_ca.crt \
    --san mosquitto \
    --san localhost \
    --san 127.0.0.1 \
    --insecure

echo "✅ Certificates generated successfully!"
