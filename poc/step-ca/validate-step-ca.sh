#!/bin/bash

echo "🔍 Step-CA Validation Script"
echo "============================"

# Check if step-ca is running
echo "1. Checking step-ca service status..."
if curl -k https://localhost:9000/health > /dev/null 2>&1; then
    echo "   ✅ step-ca is running and responding"
else
    echo "   ❌ step-ca is not responding"
    exit 1
fi

# Check step-ca version and info
echo ""
echo "2. Getting step-ca information..."
curl -k https://localhost:9000/health 2>/dev/null | jq . 2>/dev/null || echo "   Health endpoint response received"

# Check ACME directory
echo ""
echo "3. Checking ACME provisioner..."
curl -k https://localhost:9000/acme/acme/directory 2>/dev/null | jq . 2>/dev/null || echo "   ACME directory endpoint accessible"

# List provisioners
echo ""
echo "4. Listing available provisioners..."
docker exec enterprise-step-ca step ca provisioner list 2>/dev/null || echo "   Could not list provisioners (container may not be running)"

# Check root certificate
echo ""
echo "5. Validating root certificate..."
if [ -f "certificates/root_ca.crt" ]; then
    echo "   Root certificate details:"
    openssl x509 -in certificates/root_ca.crt -text -noout | grep -E "(Subject:|Issuer:|Not Before:|Not After:)"
else
    echo "   ❌ Root certificate not found"
fi

# Test certificate request
echo ""
echo "6. Testing certificate request capability..."
docker run --rm --network host \
    -v $(pwd)/certificates:/certs \
    smallstep/step-cli:latest \
    step ca health \
    --ca-url https://localhost:9000 \
    --root /certs/root_ca.crt \
    --insecure 2>/dev/null && echo "   ✅ Certificate authority is healthy" || echo "   ⚠️  CA health check failed"

echo ""
echo "7. Checking step-ca configuration..."
if [ -f "step-ca-config/ca.json" ]; then
    echo "   ✅ CA configuration file exists"
    echo "   Configured provisioners:"
    cat step-ca-config/ca.json | jq -r '.authority.provisioners[].name' 2>/dev/null || echo "   Could not parse provisioners"
else
    echo "   ❌ CA configuration file missing"
fi

echo ""
echo "🎯 Validation Summary:"
echo "   - step-ca service: $(curl -k https://localhost:9000/health > /dev/null 2>&1 && echo "✅ Running" || echo "❌ Not running")"
echo "   - Root certificate: $([ -f "certificates/root_ca.crt" ] && echo "✅ Present" || echo "❌ Missing")"
echo "   - ACME endpoint: $(curl -k https://localhost:9000/acme/acme/directory > /dev/null 2>&1 && echo "✅ Accessible" || echo "❌ Not accessible")"
echo "   - Configuration: $([ -f "step-ca-config/ca.json" ] && echo "✅ Present" || echo "❌ Missing")"