# PowerShell script for Windows users
# Automatic extra_hosts configuration for step-ca container

Write-Host "🔧 Setting up dynamic extra_hosts for step-ca container..." -ForegroundColor Cyan

# Get container IPs from the running containers
try {
    $DEVICE_IP = docker inspect certbot-device --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>$null
    $APP_IP = docker inspect certbot-app --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>$null
    $MQTT_IP = docker inspect certbot-mqtt --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>$null
} catch {
    Write-Host "⚠️  Some containers not running, using default IPs" -ForegroundColor Yellow
}

# If containers aren't running, use the static IPs from docker-compose.yml
if ([string]::IsNullOrEmpty($DEVICE_IP)) { $DEVICE_IP = "172.20.0.50" }
if ([string]::IsNullOrEmpty($APP_IP)) { $APP_IP = "172.20.0.60" }
if ([string]::IsNullOrEmpty($MQTT_IP)) { $MQTT_IP = "172.20.0.70" }

Write-Host "📍 Detected container IPs:" -ForegroundColor Green
Write-Host "  device.localtest.me -> $DEVICE_IP" -ForegroundColor White
Write-Host "  app.localtest.me -> $APP_IP" -ForegroundColor White
Write-Host "  mqtt.localtest.me -> $MQTT_IP" -ForegroundColor White

# Create a docker-compose override file with the correct IPs
$overrideContent = @"
version: '3.8'

services:
  step-ca:
    extra_hosts:
      - "device.localtest.me:$DEVICE_IP"
      - "app.localtest.me:$APP_IP"
      - "mqtt.localtest.me:$MQTT_IP"
"@

$overrideContent | Out-File -FilePath "docker-compose.extra-hosts.yml" -Encoding UTF8

Write-Host "✅ Created docker-compose.extra-hosts.yml with dynamic IPs" -ForegroundColor Green
Write-Host "🚀 To apply: docker compose -f docker-compose.yml -f docker-compose.extra-hosts.yml up -d step-ca" -ForegroundColor Cyan
Write-Host ""
Write-Host "💡 Alternative: Add these lines to your docker-compose.yml under step-ca service:" -ForegroundColor Yellow
Write-Host "    extra_hosts:" -ForegroundColor White
Write-Host "      - `"device.localtest.me:$DEVICE_IP`"" -ForegroundColor White
Write-Host "      - `"app.localtest.me:$APP_IP`"" -ForegroundColor White
Write-Host "      - `"mqtt.localtest.me:$MQTT_IP`"" -ForegroundColor White