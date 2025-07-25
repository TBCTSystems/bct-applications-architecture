#!/bin/bash
# setup.sh - Linux/macOS Setup Script for Certificate Management PoC

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_header() {
    echo ""
    print_status $BLUE "=================================================================="
    print_status $BLUE "$1"
    print_status $BLUE "=================================================================="
    echo ""
}

print_header "Certificate Management PoC - Setup Script (Linux/macOS)"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_status $RED "ERROR: This script should not be run as root."
    print_status $YELLOW "Please run as a regular user with sudo privileges."
    exit 1
fi

print_status $YELLOW "Step 1: Checking Prerequisites..."

# Check if Docker is installed
if ! command -v docker >/dev/null 2>&1; then
    print_status $RED "ERROR: Docker is not installed."
    print_status $YELLOW "Please install Docker from: https://docs.docker.com/get-docker/"
    exit 1
fi

# Check if Docker Compose is available
if ! docker compose version >/dev/null 2>&1; then
    if ! command -v docker-compose >/dev/null 2>&1; then
        print_status $RED "ERROR: Docker Compose is not available."
        print_status $YELLOW "Please install Docker Compose from: https://docs.docker.com/compose/install/"
        exit 1
    else
        print_status $YELLOW "WARNING: Using legacy docker-compose command. Consider upgrading to 'docker compose'."
        DOCKER_COMPOSE_CMD="docker-compose"
    fi
else
    DOCKER_COMPOSE_CMD="docker compose"
fi

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    print_status $RED "ERROR: Docker is not running."
    print_status $YELLOW "Please start Docker and try again."
    exit 1
fi

# Check if user is in docker group
if ! groups $USER | grep -q '\bdocker\b'; then
    print_status $RED "ERROR: User $USER is not in the docker group."
    print_status $YELLOW "Please add user to docker group:"
    echo "   sudo usermod -aG docker $USER"
    echo "   Then log out and back in."
    exit 1
fi

print_status $GREEN "Docker and Docker Compose are available and running."

# Get Docker versions
DOCKER_VERSION=$(docker --version)
COMPOSE_VERSION=$($DOCKER_COMPOSE_CMD version --short 2>/dev/null || echo "Unknown")

print_status $BLUE "Docker: $DOCKER_VERSION"
print_status $BLUE "Docker Compose: $COMPOSE_VERSION"

print_status $YELLOW "Step 2: Checking System Requirements..."

# Check available disk space (need at least 2GB)
AVAILABLE_SPACE=$(df . | awk 'NR==2 {print $4}')
REQUIRED_SPACE=2097152  # 2GB in KB

if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
    print_status $RED "ERROR: Insufficient disk space."
    print_status $YELLOW "Required: 2GB, Available: $(($AVAILABLE_SPACE / 1024 / 1024))GB"
    exit 1
fi

print_status $GREEN "Sufficient disk space available."

print_status $YELLOW "Step 3: Configuring Hosts File..."

# Check if hosts file entries exist
HOSTS_FILE="/etc/hosts"
REQUIRED_ENTRIES=(
    "ca.localtest.me"
    "device.localtest.me"
    "app.localtest.me"
    "mqtt.localtest.me"
)

MISSING_ENTRIES=()
for entry in "${REQUIRED_ENTRIES[@]}"; do
    if ! grep -q "$entry" "$HOSTS_FILE"; then
        MISSING_ENTRIES+=("$entry")
    fi
done

if [ ${#MISSING_ENTRIES[@]} -gt 0 ]; then
    print_status $YELLOW "Adding missing hosts file entries..."
    
    # Create backup
    sudo cp "$HOSTS_FILE" "${HOSTS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    print_status $BLUE "Backup created: ${HOSTS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Add entries
    echo "" | sudo tee -a "$HOSTS_FILE" >/dev/null
    echo "# Certificate Management PoC - Local Domain Resolution" | sudo tee -a "$HOSTS_FILE" >/dev/null
    for entry in "${MISSING_ENTRIES[@]}"; do
        echo "127.0.0.1 $entry" | sudo tee -a "$HOSTS_FILE" >/dev/null
        print_status $GREEN "Added: 127.0.0.1 $entry"
    done
else
    print_status $GREEN "All required hosts file entries are present."
fi

# Verify hosts file entries
print_status $YELLOW "Verifying domain resolution..."
for entry in "${REQUIRED_ENTRIES[@]}"; do
    if ping -c 1 -W 1 "$entry" >/dev/null 2>&1; then
        print_status $GREEN "✓ $entry resolves correctly"
    else
        print_status $RED "✗ $entry does not resolve"
    fi
done

print_status $YELLOW "Step 4: Preparing Project Environment..."

# Check if we're in the correct directory
if [ ! -f "docker-compose.yml" ]; then
    print_status $RED "ERROR: docker-compose.yml not found in current directory."
    print_status $YELLOW "Please run this script from the project root directory."
    exit 1
fi

# Create required directories
print_status $BLUE "Creating required directories..."
mkdir -p logs/{step-ca,mosquitto,loki,grafana,certbot-device,certbot-app,certbot-mqtt}
mkdir -p config/grafana/dev

print_status $GREEN "Project directories created."

print_status $YELLOW "Step 5: Fixing Docker Volume Permissions..."

# Run the permission fix script
if [ -f "scripts/fix-permissions.sh" ]; then
    chmod +x scripts/fix-permissions.sh
    print_status $BLUE "Running permission fix script..."
    ./scripts/fix-permissions.sh
else
    print_status $RED "ERROR: Permission fix script not found at scripts/fix-permissions.sh"
    exit 1
fi

print_status $YELLOW "Step 6: Starting Infrastructure Services..."

# Start services
print_status $BLUE "Starting all services with $DOCKER_COMPOSE_CMD..."
$DOCKER_COMPOSE_CMD up -d

print_status $YELLOW "Waiting for services to initialize (60 seconds)..."
sleep 60

print_status $YELLOW "Step 7: Verifying Service Health..."

# Check service status
print_status $BLUE "Service Status:"
$DOCKER_COMPOSE_CMD ps

# Test individual services
print_status $YELLOW "Testing service endpoints..."

# Test step-ca
if docker exec step-ca curl -k -s https://localhost:9000/health >/dev/null 2>&1; then
    print_status $GREEN "✓ step-ca health endpoint responding"
else
    print_status $RED "✗ step-ca health endpoint not responding"
fi

# Test Grafana
if curl -s http://localhost:3000/api/health >/dev/null 2>&1; then
    print_status $GREEN "✓ Grafana accessible"
else
    print_status $RED "✗ Grafana not accessible"
fi

# Test Loki
if docker exec loki wget -qO- http://localhost:3100/ready >/dev/null 2>&1; then
    print_status $GREEN "✓ Loki ready"
else
    print_status $RED "✗ Loki not ready"
fi

print_header "Setup Complete!"

print_status $GREEN "Certificate Management PoC is now running!"
echo ""
print_status $BLUE "Access Points:"
print_status $BLUE "• Grafana Dashboard: http://localhost:3000 (admin/admin)"
print_status $BLUE "• step-ca Health: https://ca.localtest.me:9000/health"
print_status $BLUE "• Loki API: http://localhost:3100"
echo ""
print_status $BLUE "Useful Commands:"
print_status $BLUE "• Check service status: $DOCKER_COMPOSE_CMD ps"
print_status $BLUE "• View logs: $DOCKER_COMPOSE_CMD logs -f <service-name>"
print_status $BLUE "• Stop services: $DOCKER_COMPOSE_CMD down"
print_status $BLUE "• Complete reset: $DOCKER_COMPOSE_CMD down -v"
echo ""
print_status $YELLOW "Next Steps:"
print_status $YELLOW "1. Open Grafana at http://localhost:3000"
print_status $YELLOW "2. Explore the Loki datasource"
print_status $YELLOW "3. Monitor certificate lifecycle events"
print_status $YELLOW "4. Check the documentation in docs/ directory"
echo ""

# Check for any failed services
FAILED_SERVICES=$($DOCKER_COMPOSE_CMD ps --filter "status=exited" --format "{{.Service}}" 2>/dev/null || true)
if [ -n "$FAILED_SERVICES" ]; then
    print_status $RED "WARNING: Some services failed to start:"
    echo "$FAILED_SERVICES"
    print_status $YELLOW "Check logs with: $DOCKER_COMPOSE_CMD logs <service-name>"
fi

print_status $GREEN "Setup script completed successfully!"