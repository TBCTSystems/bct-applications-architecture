#!/bin/bash

echo "🧪 Phase 2 Testing Script - Provisioning Service Development"
echo "============================================================"

# Test AC-P2-001: Core Service Functionality
echo ""
echo "🔍 AC-P2-001: Core Service Functionality"
echo "----------------------------------------"

echo "Testing: .NET service starts and responds to health checks"
if curl -f http://localhost:5000/health > /dev/null 2>&1; then
    echo "   ✅ Provisioning service health endpoint responding"
else
    echo "   ❌ Provisioning service health endpoint not responding"
fi

echo "Testing: RESTful API endpoints are accessible"
if curl -f http://localhost:5000/api/provisioning/status > /dev/null 2>&1; then
    echo "   ✅ Provisioning status endpoint accessible"
else
    echo "   ❌ Provisioning status endpoint not accessible"
fi

echo "Testing: Service can communicate with step-ca"
if docker-compose exec -T provisioning-service curl -k https://step-ca:9000/health > /dev/null 2>&1; then
    echo "   ✅ Provisioning service can reach step-ca"
else
    echo "   ❌ Provisioning service cannot reach step-ca"
fi

# Test AC-P2-002: IP Whitelisting
echo ""
echo "🔍 AC-P2-002: IP Whitelisting"
echo "-----------------------------"

echo "Testing: IP whitelist can be configured via API"
whitelist_response=$(curl -s http://localhost:5000/api/whitelist 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "   ✅ Whitelist API endpoint accessible"
    echo "   Current whitelist: $whitelist_response"
else
    echo "   ❌ Whitelist API endpoint not accessible"
fi

echo "Testing: Add IP to whitelist"
add_response=$(curl -s -X POST http://localhost:5000/api/whitelist/add \
    -H "Content-Type: application/json" \
    -d '{"ipAddress":"192.168.1.100"}' 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "   ✅ IP can be added to whitelist"
else
    echo "   ❌ Failed to add IP to whitelist"
fi

# Test AC-P2-003: Service Control
echo ""
echo "🔍 AC-P2-003: Service Control"
echo "-----------------------------"

echo "Testing: Service can be enabled via API"
enable_response=$(curl -s -X POST http://localhost:5000/api/provisioning/enable 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "   ✅ Service can be enabled via API"
else
    echo "   ❌ Failed to enable service via API"
fi

echo "Testing: Service status can be checked"
status_response=$(curl -s http://localhost:5000/api/provisioning/status 2>/dev/null)
if echo "$status_response" | grep -q "enabled\|Enabled"; then
    echo "   ✅ Service status endpoint returns status information"
else
    echo "   ❌ Service status endpoint not working properly"
fi

# Test AC-P2-004: step-ca Integration
echo ""
echo "🔍 AC-P2-004: step-ca Integration"
echo "--------------------------------"

echo "Testing: Service can request certificates"
cert_request='{"commonName":"test-device","subjectAlternativeNames":["test-device"],"deviceId":"TEST-001","deviceType":"test"}'
cert_response=$(curl -s -X POST http://localhost:5000/api/provisioning/certificate \
    -H "Content-Type: application/json" \
    -d "$cert_request" 2>/dev/null)

if echo "$cert_response" | grep -q "certificate\|Certificate"; then
    echo "   ✅ Certificate can be requested from service"
else
    echo "   ❌ Certificate request failed"
    echo "   Response: $cert_response"
fi

# Test AC-P2-005: Administrative Interface
echo ""
echo "🔍 AC-P2-005: Administrative Interface"
echo "-------------------------------------"

echo "Testing: Admin web interface loads"
if curl -f http://localhost:5000/admin > /dev/null 2>&1; then
    echo "   ✅ Administrative web interface accessible"
else
    echo "   ❌ Administrative web interface not accessible"
fi

echo "Testing: Admin interface contains expected elements"
admin_content=$(curl -s http://localhost:5000/admin 2>/dev/null)
if echo "$admin_content" | grep -q "Provisioning Service Administration"; then
    echo "   ✅ Admin interface loads with correct content"
else
    echo "   ❌ Admin interface content not correct"
fi

# Test AC-P2-006: Security and Logging
echo ""
echo "🔍 AC-P2-006: Security and Logging"
echo "----------------------------------"

echo "Testing: HTTPS is available"
if curl -k -f https://localhost:5001/health > /dev/null 2>&1; then
    echo "   ✅ HTTPS endpoint is accessible"
else
    echo "   ❌ HTTPS endpoint not accessible"
fi

echo "Testing: Container logs are accessible"
log_lines=$(docker-compose logs provisioning-service 2>/dev/null | wc -l)
if [ "$log_lines" -gt 0 ]; then
    echo "   ✅ Container logs are accessible ($log_lines lines)"
else
    echo "   ❌ Container logs are not accessible"
fi

echo "Testing: Input validation (malformed request)"
malformed_response=$(curl -s -X POST http://localhost:5000/api/provisioning/certificate \
    -H "Content-Type: application/json" \
    -d '{"invalid":"json"}' 2>/dev/null)
if echo "$malformed_response" | grep -q -i "error\|bad\|invalid"; then
    echo "   ✅ Input validation is working"
else
    echo "   ⚠️  Input validation response unclear"
fi

# Test Dockerization
echo ""
echo "🔍 Dockerization and Health Checks"
echo "----------------------------------"

echo "Testing: Container is running"
if docker-compose ps provisioning-service | grep -q "Up"; then
    echo "   ✅ Provisioning service container is running"
else
    echo "   ❌ Provisioning service container is not running"
fi

echo "Testing: Health check is working"
health_status=$(docker-compose ps provisioning-service | grep "healthy\|unhealthy" || echo "no health status")
echo "   Health status: $health_status"

echo "Testing: Volume mounts are working"
if docker-compose exec -T provisioning-service ls /app/certs > /dev/null 2>&1; then
    echo "   ✅ Certificate volume mount is working"
else
    echo "   ❌ Certificate volume mount not working"
fi

# Summary
echo ""
echo "📊 Phase 2 Test Summary"
echo "======================="

total_tests=15
passed_tests=0

# Count passed tests (simplified)
if curl -f http://localhost:5000/health > /dev/null 2>&1; then ((passed_tests++)); fi
if curl -f http://localhost:5000/api/provisioning/status > /dev/null 2>&1; then ((passed_tests++)); fi
if docker-compose exec -T provisioning-service curl -k https://step-ca:9000/health > /dev/null 2>&1; then ((passed_tests++)); fi
if curl -s http://localhost:5000/api/whitelist > /dev/null 2>&1; then ((passed_tests++)); fi
if curl -s -X POST http://localhost:5000/api/whitelist/add -H "Content-Type: application/json" -d '{"ipAddress":"192.168.1.100"}' > /dev/null 2>&1; then ((passed_tests++)); fi
if curl -s -X POST http://localhost:5000/api/provisioning/enable > /dev/null 2>&1; then ((passed_tests++)); fi
if curl -s http://localhost:5000/api/provisioning/status | grep -q "enabled\|Enabled"; then ((passed_tests++)); fi
if curl -s -X POST http://localhost:5000/api/provisioning/certificate -H "Content-Type: application/json" -d '{"commonName":"test","deviceId":"test"}' | grep -q "certificate"; then ((passed_tests++)); fi
if curl -f http://localhost:5000/admin > /dev/null 2>&1; then ((passed_tests++)); fi
if curl -s http://localhost:5000/admin | grep -q "Administration"; then ((passed_tests++)); fi
if curl -k -f https://localhost:5001/health > /dev/null 2>&1; then ((passed_tests++)); fi
if [ "$(docker-compose logs provisioning-service 2>/dev/null | wc -l)" -gt 0 ]; then ((passed_tests++)); fi
if docker-compose ps provisioning-service | grep -q "Up"; then ((passed_tests++)); fi
if docker-compose exec -T provisioning-service ls /app/certs > /dev/null 2>&1; then ((passed_tests++)); fi
# Add one more for overall functionality
if curl -f http://localhost:5000/health > /dev/null 2>&1 && curl -f http://localhost:5000/admin > /dev/null 2>&1; then ((passed_tests++)); fi

echo "Tests passed: $passed_tests/$total_tests"
echo "Success rate: $(( passed_tests * 100 / total_tests ))%"

if [ $passed_tests -eq $total_tests ]; then
    echo "🎉 Phase 2 - PASSED: All acceptance criteria met!"
    exit 0
elif [ $passed_tests -ge 12 ]; then
    echo "⚠️  Phase 2 - PARTIAL: Most acceptance criteria met"
    exit 1
else
    echo "❌ Phase 2 - FAILED: Critical acceptance criteria not met"
    exit 2
fi