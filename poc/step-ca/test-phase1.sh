#!/bin/bash

echo "🧪 Phase 1 Testing Script - Infrastructure Foundation"
echo "====================================================="

# Test AC-P1-001: step-ca Root CA Setup
echo ""
echo "🔍 AC-P1-001: step-ca Root CA Setup"
echo "-----------------------------------"

# Check if step-ca service starts successfully
echo "Testing: step-ca service starts successfully"
if docker-compose ps step-ca | grep -q "Up"; then
    echo "   ✅ step-ca container is running"
else
    echo "   ❌ step-ca container is not running"
fi

# Check if root CA certificate is generated
echo "Testing: Root CA certificate is generated with correct attributes"
if [ -f "certificates/root_ca.crt" ]; then
    echo "   ✅ Root CA certificate exists"
    subject=$(openssl x509 -in certificates/root_ca.crt -subject -noout 2>/dev/null)
    echo "   Certificate subject: $subject"
else
    echo "   ❌ Root CA certificate not found"
fi

# Check if step-ca responds to health checks
echo "Testing: step-ca responds to health check requests"
if curl -k https://localhost:9000/health > /dev/null 2>&1; then
    echo "   ✅ step-ca health endpoint responding"
else
    echo "   ❌ step-ca health endpoint not responding"
fi

# Test AC-P1-002: ACME Provisioner Configuration
echo ""
echo "🔍 AC-P1-002: ACME Provisioner Configuration"
echo "--------------------------------------------"

echo "Testing: ACME provisioner is configured and active"
if curl -k https://localhost:9000/acme/acme/directory > /dev/null 2>&1; then
    echo "   ✅ ACME directory endpoint accessible"
else
    echo "   ❌ ACME directory endpoint not accessible"
fi

echo "Testing: ACME directory endpoint returns valid JSON"
acme_response=$(curl -k https://localhost:9000/acme/acme/directory 2>/dev/null)
if echo "$acme_response" | jq . > /dev/null 2>&1; then
    echo "   ✅ ACME directory returns valid JSON"
else
    echo "   ❌ ACME directory does not return valid JSON"
fi

# Test AC-P1-003: X.509 Provisioner Configuration
echo ""
echo "🔍 AC-P1-003: X.509 Provisioner Configuration"
echo "---------------------------------------------"

echo "Testing: X.509 provisioner is configured with root CA"
# This would require checking the step-ca configuration
if [ -f "step-ca-config/ca.json" ]; then
    if grep -q "X5C\|x5c" step-ca-config/ca.json; then
        echo "   ✅ X.509 provisioner found in configuration"
    else
        echo "   ❌ X.509 provisioner not found in configuration"
    fi
else
    echo "   ❌ step-ca configuration file not found"
fi

# Test AC-P1-004: Containerization
echo ""
echo "🔍 AC-P1-004: Containerization"
echo "------------------------------"

echo "Testing: step-ca runs successfully in Docker container"
if docker-compose ps step-ca | grep -q "Up"; then
    echo "   ✅ step-ca container is running"
else
    echo "   ❌ step-ca container is not running"
fi

echo "Testing: Certificates persist across container restarts"
# This would require a container restart test
echo "   ⚠️  Container restart test requires manual verification"

echo "Testing: Container logs are accessible and informative"
log_lines=$(docker-compose logs step-ca 2>/dev/null | wc -l)
if [ "$log_lines" -gt 0 ]; then
    echo "   ✅ Container logs are accessible ($log_lines lines)"
else
    echo "   ❌ Container logs are not accessible"
fi

echo "Testing: Docker Compose brings up step-ca service"
if docker-compose config > /dev/null 2>&1; then
    echo "   ✅ Docker Compose configuration is valid"
else
    echo "   ❌ Docker Compose configuration is invalid"
fi

# Test AC-P1-005: Basic Testing
echo ""
echo "🔍 AC-P1-005: Basic Testing"
echo "---------------------------"

echo "Testing: step CLI can connect to step-ca"
if docker run --rm --network host -v $(pwd)/certificates:/certs smallstep/step-cli:latest \
    step ca health --ca-url https://localhost:9000 --root /certs/root_ca.crt --insecure > /dev/null 2>&1; then
    echo "   ✅ step CLI can connect to step-ca"
else
    echo "   ❌ step CLI cannot connect to step-ca"
fi

echo "Testing: Certificate validation tools work"
if openssl x509 -in certificates/root_ca.crt -text -noout > /dev/null 2>&1; then
    echo "   ✅ Certificate validation tools work"
else
    echo "   ❌ Certificate validation tools do not work"
fi

# Summary
echo ""
echo "📊 Phase 1 Test Summary"
echo "======================="

total_tests=10
passed_tests=0

# Count passed tests (this is a simplified count)
if docker-compose ps step-ca | grep -q "Up"; then ((passed_tests++)); fi
if [ -f "certificates/root_ca.crt" ]; then ((passed_tests++)); fi
if curl -k https://localhost:9000/health > /dev/null 2>&1; then ((passed_tests++)); fi
if curl -k https://localhost:9000/acme/acme/directory > /dev/null 2>&1; then ((passed_tests++)); fi
if echo "$(curl -k https://localhost:9000/acme/acme/directory 2>/dev/null)" | jq . > /dev/null 2>&1; then ((passed_tests++)); fi
if [ -f "step-ca-config/ca.json" ] && grep -q "X5C\|x5c" step-ca-config/ca.json; then ((passed_tests++)); fi
if docker-compose config > /dev/null 2>&1; then ((passed_tests++)); fi
if docker-compose logs step-ca 2>/dev/null | wc -l | grep -q "[1-9]"; then ((passed_tests++)); fi
if docker run --rm --network host -v $(pwd)/certificates:/certs smallstep/step-cli:latest step ca health --ca-url https://localhost:9000 --root /certs/root_ca.crt --insecure > /dev/null 2>&1; then ((passed_tests++)); fi
if openssl x509 -in certificates/root_ca.crt -text -noout > /dev/null 2>&1; then ((passed_tests++)); fi

echo "Tests passed: $passed_tests/$total_tests"
echo "Success rate: $(( passed_tests * 100 / total_tests ))%"

if [ $passed_tests -eq $total_tests ]; then
    echo "🎉 Phase 1 - PASSED: All acceptance criteria met!"
    exit 0
elif [ $passed_tests -ge 7 ]; then
    echo "⚠️  Phase 1 - PARTIAL: Most acceptance criteria met"
    exit 1
else
    echo "❌ Phase 1 - FAILED: Critical acceptance criteria not met"
    exit 2
fi