#!/bin/bash
# fix-permissions.sh - Linux/macOS permission fix script for Certificate Management PoC

set -e

echo "🔧 Certificate Management PoC - Permission Fix Script (Linux/macOS)"
echo "=================================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_status $RED "❌ This script should not be run as root. Please run as a regular user."
    exit 1
fi

# Check if user is in docker group
if ! groups $USER | grep -q '\bdocker\b'; then
    print_status $RED "❌ User $USER is not in the docker group. Please add user to docker group:"
    echo "   sudo usermod -aG docker $USER"
    echo "   Then log out and back in."
    exit 1
fi

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    print_status $RED "❌ Docker is not running or not accessible. Please start Docker."
    exit 1
fi

print_status $YELLOW "🔍 Checking Docker Compose project..."

# Get the project name (directory name)
PROJECT_NAME=$(basename "$(pwd)")

# Check if volumes exist
VOLUMES=$(docker volume ls --format "{{.Name}}" | grep "^${PROJECT_NAME}_" || true)

if [ -z "$VOLUMES" ]; then
    print_status $YELLOW "⚠️  No Docker volumes found for project '$PROJECT_NAME'. Creating volumes by starting services..."
    docker compose up --no-start
fi

print_status $YELLOW "🔍 Identifying step-ca container user ID..."

# Get the step-ca container user ID
STEP_UID=$(docker run --rm smallstep/step-ca:latest id -u 2>/dev/null || echo "1000")
STEP_GID=$(docker run --rm smallstep/step-ca:latest id -g 2>/dev/null || echo "1000")

print_status $GREEN "📋 step-ca container runs as UID:GID = $STEP_UID:$STEP_GID"

print_status $YELLOW "🔧 Fixing permissions for Docker volumes..."

# Function to fix volume permissions
fix_volume_permissions() {
    local volume_name=$1
    local description=$2
    
    print_status $YELLOW "   Fixing $description..."
    
    # Get volume mount point
    local mount_point=$(docker volume inspect "$volume_name" --format '{{.Mountpoint}}' 2>/dev/null)
    
    if [ -z "$mount_point" ]; then
        print_status $RED "   ❌ Volume $volume_name not found"
        return 1
    fi
    
    # Fix permissions
    if sudo chown -R "$STEP_UID:$STEP_GID" "$mount_point" 2>/dev/null; then
        print_status $GREEN "   ✅ Fixed permissions for $description"
    else
        print_status $RED "   ❌ Failed to fix permissions for $description"
        return 1
    fi
}

# Fix permissions for step-ca volumes
fix_volume_permissions "${PROJECT_NAME}_step-ca-data" "step-ca data volume"

# Fix permissions for certificate volumes (if they exist)
for cert_volume in "certs-ca" "certs-device" "certs-app" "certs-mqtt"; do
    if docker volume ls --format "{{.Name}}" | grep -q "^${PROJECT_NAME}_${cert_volume}$"; then
        fix_volume_permissions "${PROJECT_NAME}_${cert_volume}" "$cert_volume volume"
    fi
done

print_status $GREEN "✅ Permission fixes completed successfully!"

print_status $YELLOW "🧪 Testing step-ca startup..."

# Test step-ca startup
if docker compose up -d step-ca; then
    print_status $GREEN "✅ step-ca started successfully"
    
    # Wait for health check
    print_status $YELLOW "⏳ Waiting for step-ca to become healthy (up to 60 seconds)..."
    
    for i in {1..12}; do
        if docker compose ps step-ca | grep -q "healthy"; then
            print_status $GREEN "✅ step-ca is healthy!"
            break
        elif [ $i -eq 12 ]; then
            print_status $RED "❌ step-ca failed to become healthy within 60 seconds"
            print_status $YELLOW "📋 step-ca logs:"
            docker compose logs --tail=10 step-ca
            exit 1
        else
            echo -n "."
            sleep 5
        fi
    done
    
    # Test health endpoint
    if docker exec step-ca curl -k https://localhost:9000/health >/dev/null 2>&1; then
        print_status $GREEN "✅ step-ca health endpoint is responding"
    else
        print_status $RED "❌ step-ca health endpoint is not responding"
        exit 1
    fi
    
else
    print_status $RED "❌ Failed to start step-ca"
    exit 1
fi

print_status $GREEN "🎉 All permission fixes completed successfully!"
print_status $GREEN "🚀 You can now run: docker compose up -d"

echo ""
echo "📋 Summary of fixes applied:"
echo "   • Fixed ownership of step-ca data volume to UID:GID $STEP_UID:$STEP_GID"
echo "   • Fixed ownership of certificate volumes"
echo "   • Verified step-ca startup and health"
echo ""
echo "🔗 Next steps:"
echo "   • Run 'docker compose up -d' to start all services"
echo "   • Access Grafana at http://localhost:3000 (admin/admin)"
echo "   • Check step-ca at https://ca.localtest.me:9000/health"