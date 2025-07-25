#!/bin/bash
# Automatic extra_hosts configuration for step-ca container
# This script dynamically determines container IPs and updates docker-compose.yml

set -e

echo "🔧 Setting up dynamic extra_hosts for step-ca container..."

# Get container IPs from the running containers
DEVICE_IP=$(docker inspect certbot-device --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "")
APP_IP=$(docker inspect certbot-app --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "")
MQTT_IP=$(docker inspect certbot-mqtt --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "")

# If containers aren't running, use the static IPs from docker-compose.yml
if [ -z "$DEVICE_IP" ]; then DEVICE_IP="172.20.0.50"; fi
if [ -z "$APP_IP" ]; then APP_IP="172.20.0.60"; fi  
if [ -z "$MQTT_IP" ]; then MQTT_IP="172.20.0.70"; fi

echo "📍 Detected container IPs:"
echo "  device.localtest.me -> $DEVICE_IP"
echo "  app.localtest.me -> $APP_IP"
echo "  mqtt.localtest.me -> $MQTT_IP"

# Create a docker-compose override file with the correct IPs
cat > docker-compose.extra-hosts.yml << EOF
version: '3.8'

services:
  step-ca:
    extra_hosts:
      - "device.localtest.me:$DEVICE_IP"
      - "app.localtest.me:$APP_IP"
      - "mqtt.localtest.me:$MQTT_IP"
EOF

echo "✅ Created docker-compose.extra-hosts.yml with dynamic IPs"
echo "🚀 To apply: docker compose -f docker-compose.yml -f docker-compose.extra-hosts.yml up -d step-ca"
echo ""
echo "💡 Alternative: Add these lines to your docker-compose.yml under step-ca service:"
echo "    extra_hosts:"
echo "      - \"device.localtest.me:$DEVICE_IP\""
echo "      - \"app.localtest.me:$APP_IP\""
echo "      - \"mqtt.localtest.me:$MQTT_IP\""