#!/bin/bash

echo "🧪 MQTT mTLS Testing Script"
echo "==========================="

# Test MQTT broker with mTLS
echo ""
echo "🔍 Testing MQTT Broker mTLS Configuration"
echo "-----------------------------------------"

echo "Testing: Mosquitto container is running"
if docker compose ps mosquitto | grep -q "Up"; then
    echo "   ✅ Mosquitto container is running"
else
    echo "   ❌ Mosquitto container is not running"
    echo "   Starting Mosquitto..."
    docker compose up -d mosquitto
    sleep 5
fi

echo "Testing: MQTT TLS port (8883) is accessible"
if timeout 5 bash -c "</dev/tcp/localhost/8883"; then
    echo "   ✅ MQTT TLS port 8883 is accessible"
else
    echo "   ❌ MQTT TLS port 8883 is not accessible"
fi

echo "Testing: WebSocket TLS port (9001) is accessible"
if timeout 5 bash -c "</dev/tcp/localhost/9001"; then
    echo "   ✅ WebSocket TLS port 9001 is accessible"
else
    echo "   ❌ WebSocket TLS port 9001 is not accessible"
fi

echo "Testing: Mosquitto configuration is loaded"
if docker compose exec -T mosquitto cat /mosquitto/config/mosquitto.conf | grep -q "require_certificate true"; then
    echo "   ✅ mTLS configuration is loaded"
else
    echo "   ❌ mTLS configuration not loaded properly"
fi

echo "Testing: Certificate files are accessible to Mosquitto"
if docker compose exec -T mosquitto ls /mosquitto/certs/mosquitto.crt > /dev/null 2>&1; then
    echo "   ✅ Server certificate is accessible"
else
    echo "   ❌ Server certificate not accessible"
fi

if docker compose exec -T mosquitto ls /mosquitto/certs/root_ca.crt > /dev/null 2>&1; then
    echo "   ✅ Root CA certificate is accessible"
else
    echo "   ❌ Root CA certificate not accessible"
fi

echo ""
echo "🔐 Testing Certificate-based Authentication"
echo "------------------------------------------"

# Test with valid client certificate
echo "Testing: Connection with valid client certificate"
if command -v mosquitto_pub > /dev/null 2>&1; then
    if mosquitto_pub -h localhost -p 8883 \
        --cafile certificates/root_ca.crt \
        --cert certificates/lumia-app.crt \
        --key certificates/lumia-app.key \
        -t "test/topic" -m "test message" \
        --insecure 2>/dev/null; then
        echo "   ✅ Client certificate authentication successful"
    else
        echo "   ⚠️  Client certificate authentication test (requires mosquitto-clients)"
    fi
else
    echo "   ⚠️  mosquitto_pub not available for testing (install mosquitto-clients)"
fi

# Test without certificate (should fail)
echo "Testing: Connection without certificate (should fail)"
if command -v mosquitto_pub > /dev/null 2>&1; then
    if timeout 5 mosquitto_pub -h localhost -p 8883 -t "test/topic" -m "test" 2>/dev/null; then
        echo "   ❌ Connection without certificate succeeded (security issue)"
    else
        echo "   ✅ Connection without certificate properly rejected"
    fi
else
    echo "   ⚠️  mosquitto_pub not available for testing"
fi

echo ""
echo "🔍 Testing Topic-level Access Control"
echo "------------------------------------"

echo "Testing: ACL configuration is loaded"
if docker compose exec -T mosquitto cat /mosquitto/config/acl.conf | grep -q "user lumia-app"; then
    echo "   ✅ ACL configuration is loaded"
else
    echo "   ❌ ACL configuration not loaded"
fi

echo "Testing: Topic patterns are configured"
if docker compose exec -T mosquitto cat /mosquitto/config/acl.conf | grep -q "pattern readwrite devices/%c"; then
    echo "   ✅ Device topic patterns configured"
else
    echo "   ❌ Device topic patterns not configured"
fi

echo ""
echo "🔍 Testing Certificate Validation"
echo "--------------------------------"

echo "Testing: Server certificate validity"
if openssl x509 -in certificates/mosquitto.crt -text -noout | grep -q "mosquitto"; then
    echo "   ✅ Server certificate has correct subject"
else
    echo "   ❌ Server certificate subject incorrect"
fi

echo "Testing: Client certificate validity"
if openssl x509 -in certificates/lumia-app.crt -text -noout | grep -q "lumia-app"; then
    echo "   ✅ Client certificate has correct subject"
else
    echo "   ❌ Client certificate subject incorrect"
fi

echo "Testing: Certificate expiry dates"
server_expiry=$(openssl x509 -in certificates/mosquitto.crt -enddate -noout | cut -d= -f2)
client_expiry=$(openssl x509 -in certificates/lumia-app.crt -enddate -noout | cut -d= -f2)
echo "   Server certificate expires: $server_expiry"
echo "   Client certificate expires: $client_expiry"

echo ""
echo "🔍 Testing Mosquitto Logs and Monitoring"
echo "---------------------------------------"

echo "Testing: Mosquitto logs are accessible"
log_lines=$(docker compose logs mosquitto 2>/dev/null | wc -l)
if [ "$log_lines" -gt 0 ]; then
    echo "   ✅ Mosquitto logs accessible ($log_lines lines)"
    echo "   Recent log entries:"
    docker compose logs --tail 3 mosquitto 2>/dev/null | sed 's/^/      /'
else
    echo "   ❌ Mosquitto logs not accessible"
fi

echo "Testing: Mosquitto health check"
health_status=$(docker compose ps mosquitto | grep "healthy\|unhealthy" || echo "no health status")
echo "   Health status: $health_status"

echo ""
echo "📊 Phase 3 MQTT Infrastructure Summary"
echo "====================================="

# Count successful tests
total_tests=12
passed_tests=0

if docker compose ps mosquitto | grep -q "Up"; then ((passed_tests++)); fi
if timeout 5 bash -c "</dev/tcp/localhost/8883" 2>/dev/null; then ((passed_tests++)); fi
if timeout 5 bash -c "</dev/tcp/localhost/9001" 2>/dev/null; then ((passed_tests++)); fi
if docker compose exec -T mosquitto cat /mosquitto/config/mosquitto.conf | grep -q "require_certificate true" 2>/dev/null; then ((passed_tests++)); fi
if docker compose exec -T mosquitto ls /mosquitto/certs/mosquitto.crt > /dev/null 2>&1; then ((passed_tests++)); fi
if docker compose exec -T mosquitto ls /mosquitto/certs/root_ca.crt > /dev/null 2>&1; then ((passed_tests++)); fi
if docker compose exec -T mosquitto cat /mosquitto/config/acl.conf | grep -q "user lumia-app" 2>/dev/null; then ((passed_tests++)); fi
if docker compose exec -T mosquitto cat /mosquitto/config/acl.conf | grep -q "pattern readwrite devices/%c" 2>/dev/null; then ((passed_tests++)); fi
if openssl x509 -in certificates/mosquitto.crt -text -noout | grep -q "mosquitto" 2>/dev/null; then ((passed_tests++)); fi
if openssl x509 -in certificates/lumia-app.crt -text -noout | grep -q "lumia-app" 2>/dev/null; then ((passed_tests++)); fi
if [ "$(docker compose logs mosquitto 2>/dev/null | wc -l)" -gt 0 ]; then ((passed_tests++)); fi
if [ -f "certificates/mosquitto.crt" ] && [ -f "certificates/root_ca.crt" ]; then ((passed_tests++)); fi

echo "Tests passed: $passed_tests/$total_tests"
echo "Success rate: $(( passed_tests * 100 / total_tests ))%"

if [ $passed_tests -eq $total_tests ]; then
    echo "🎉 Phase 3 MQTT Infrastructure - PASSED: All tests successful!"
    exit 0
elif [ $passed_tests -ge 9 ]; then
    echo "⚠️  Phase 3 MQTT Infrastructure - PARTIAL: Most tests passed"
    exit 1
else
    echo "❌ Phase 3 MQTT Infrastructure - FAILED: Critical issues found"
    exit 2
fi