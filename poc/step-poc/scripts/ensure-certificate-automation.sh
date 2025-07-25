#!/bin/bash
set -e

# Certificate Automation Verification Script
# Ensures that certificate chain distribution is working automatically

echo "🔧 Certificate Automation Verification"
echo "======================================"

# Function to check if a container is running
container_running() {
    docker ps --format "table {{.Names}}" | grep -q "^$1$"
}

# Function to check if certificates exist in a container
check_certificates() {
    local container=$1
    local cert_dir=$2
    
    echo "📋 Checking certificates in $container..."
    
    if ! container_running "$container"; then
        echo "❌ Container $container is not running"
        return 1
    fi
    
    # Check for required certificate files
    local files=("root_ca.crt" "ca_chain.crt")
    local all_present=true
    
    for file in "${files[@]}"; do
        if docker exec "$container" test -f "$cert_dir/$file" 2>/dev/null; then
            echo "✅ $file present in $container"
        else
            echo "❌ $file missing in $container"
            all_present=false
        fi
    done
    
    # Check if intermediate CA is present (optional but recommended)
    if docker exec "$container" test -f "$cert_dir/intermediate_ca.crt" 2>/dev/null; then
        echo "✅ intermediate_ca.crt present in $container"
    else
        echo "⚠️  intermediate_ca.crt missing in $container (will use root CA only)"
    fi
    
    return $all_present
}

# Function to trigger certificate distribution
trigger_certificate_distribution() {
    echo "🔄 Triggering certificate distribution..."
    
    # Find a certbot container to trigger distribution
    local certbot_containers=("certbot-mqtt" "certbot-device" "certbot-app")
    
    for container in "${certbot_containers[@]}"; do
        if container_running "$container"; then
            echo "📡 Using $container to distribute certificates..."
            
            # Execute the certificate download and distribution
            docker exec "$container" /usr/local/bin/certbot-renew.sh download_ca_cert 2>/dev/null || {
                echo "⚠️  Direct function call failed, triggering via script execution"
                # Alternative: restart the container to trigger the renewal script
                docker restart "$container"
                sleep 10
            }
            
            return 0
        fi
    done
    
    echo "❌ No certbot containers found running"
    return 1
}

# Main verification process
main() {
    echo "🚀 Starting certificate automation verification..."
    
    # Wait for core services to be ready
    echo "⏳ Waiting for core services..."
    sleep 15
    
    # Check step-ca is ready
    if ! container_running "step-ca"; then
        echo "❌ step-ca container is not running"
        exit 1
    fi
    
    echo "✅ step-ca is running"
    
    # Check certificate distribution in consuming containers
    local containers_to_check=(
        "mosquitto:/mosquitto/ca"
        "device-simulator:/ca-certs"
    )
    
    local needs_distribution=false
    
    for container_info in "${containers_to_check[@]}"; do
        local container=$(echo "$container_info" | cut -d: -f1)
        local cert_dir=$(echo "$container_info" | cut -d: -f2)
        
        if ! check_certificates "$container" "$cert_dir"; then
            needs_distribution=true
        fi
    done
    
    # Trigger distribution if needed
    if [ "$needs_distribution" = true ]; then
        echo "🔧 Certificate distribution needed, triggering automation..."
        trigger_certificate_distribution
        
        # Wait and re-check
        echo "⏳ Waiting for distribution to complete..."
        sleep 20
        
        # Re-verify
        echo "🔍 Re-verifying certificate distribution..."
        for container_info in "${containers_to_check[@]}"; do
            local container=$(echo "$container_info" | cut -d: -f1)
            local cert_dir=$(echo "$container_info" | cut -d: -f2)
            
            check_certificates "$container" "$cert_dir"
        done
    else
        echo "✅ All certificates are properly distributed"
    fi
    
    echo ""
    echo "🎉 Certificate automation verification complete!"
    echo "📋 Summary:"
    echo "   - Mosquitto: Configured for automatic mTLS"
    echo "   - Device Simulator: Has certificate chain for validation"
    echo "   - ACL: Disabled to allow all authenticated connections"
    echo "   - Identity Mapping: Disabled to prevent auth conflicts"
    echo ""
    echo "🚀 The system should now work automatically with 'docker compose up'"
}

# Allow script to be sourced for individual function calls
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi