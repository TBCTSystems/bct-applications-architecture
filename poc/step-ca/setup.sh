#!/bin/bash

# Enterprise Certificate Management PoC Setup Script
# This script sets up the complete environment for the demo

set -e

echo "🚀 Setting up Enterprise Certificate Management PoC..."

# Create necessary directories
echo "📁 Creating directory structure..."
mkdir -p step-ca-config
mkdir -p mosquitto-config
mkdir -p certificates
mkdir -p src/{ProvisioningService,LumiaApp,ReveosSimpleMocker,DemoWeb}

# Initialize step-ca configuration
echo "🔐 Initializing step-ca configuration..."
if [ ! -f "step-ca-config/config.json" ]; then
    docker run --rm -v $(pwd)/step-ca-config:/home/step \
        smallstep/step-ca:latest \
        step ca init \
        --name="Enterprise Root CA" \
        --dns="step-ca,localhost,127.0.0.1" \
        --address=":9000" \
        --provisioner="admin" \
        --password-file=/dev/stdin <<< "enterprise-ca-password"
    
    # Add ACME provisioner
    docker run --rm -v $(pwd)/step-ca-config:/home/step \
        smallstep/step-ca:latest \
        step ca provisioner add acme --type ACME
fi

# Create Mosquitto configuration
echo "🦟 Creating Mosquitto configuration..."
cat > mosquitto-config/mosquitto.conf << 'EOF'
# Mosquitto configuration for Enterprise Certificate Management
listener 8883
protocol mqtt

# TLS Configuration
cafile /mosquitto/certs/root_ca.crt
certfile /mosquitto/certs/mosquitto.crt
keyfile /mosquitto/certs/mosquitto.key

# Require certificates from clients
require_certificate true
use_identity_as_username true

# Logging
log_dest file /mosquitto/log/mosquitto.log
log_type error
log_type warning
log_type notice
log_type information
log_type debug

# Security
allow_anonymous false
EOF

# Create certificate generation script
echo "📜 Creating certificate generation script..."
cat > generate-certificates.sh << 'EOF'
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
EOF

chmod +x generate-certificates.sh

echo "🏗️  Building .NET applications..."

# Create Provisioning Service
echo "🔧 Creating Provisioning Service..."
cat > src/ProvisioningService/Dockerfile << 'EOF'
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 5000 5001

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["ProvisioningService.csproj", "."]
RUN dotnet restore "ProvisioningService.csproj"
COPY . .
RUN dotnet build "ProvisioningService.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "ProvisioningService.csproj" -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "ProvisioningService.dll"]
EOF

# Create other Dockerfiles
for service in LumiaApp ReveosSimpleMocker DemoWeb; do
    cat > src/$service/Dockerfile << EOF
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 8080

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["$service.csproj", "."]
RUN dotnet restore "$service.csproj"
COPY . .
RUN dotnet build "$service.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "$service.csproj" -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "$service.dll"]
EOF
done

echo "📋 Creating demo script..."
cat > demo.sh << 'EOF'
#!/bin/bash

echo "🎭 Enterprise Certificate Management Demo"
echo "========================================"

echo "1. 🚀 Starting all services..."
docker-compose up -d

echo "2. ⏳ Waiting for services to be ready..."
sleep 10

echo "3. 🔐 Generating certificates..."
./generate-certificates.sh

echo "4. 🔄 Restarting services with certificates..."
docker-compose restart mosquitto

echo "5. 🎯 Demo is ready!"
echo ""
echo "🌐 Access points:"
echo "   - Demo Web Interface: http://localhost:8080"
echo "   - Provisioning Service: https://localhost:5001"
echo "   - step-ca: https://localhost:9000"
echo "   - MQTT Broker: localhost:8883 (TLS)"
echo ""
echo "📊 Monitor logs with:"
echo "   docker-compose logs -f [service-name]"
echo ""
echo "🛑 Stop demo with:"
echo "   docker-compose down"
EOF

chmod +x demo.sh

echo "✅ Setup complete!"
echo ""
echo "🎯 Next steps:"
echo "1. Run './demo.sh' to start the complete demo"
echo "2. Access the demo web interface at http://localhost:8080"
echo "3. Watch the magic happen! 🪄"