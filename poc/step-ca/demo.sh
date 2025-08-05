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
