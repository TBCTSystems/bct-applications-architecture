#!/bin/bash

# Camel Donor Middleware - Development Helper Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if Docker is running
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
}

# Function to check if ports are available
check_ports() {
    local ports=("3001" "8080")
    for port in "${ports[@]}"; do
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
            print_warning "Port $port is already in use. Please stop the service using this port."
            return 1
        fi
    done
    return 0
}

# Function to build and start services
start_services() {
    print_status "Starting Camel Donor Middleware services..."
    
    check_docker
    
    if ! check_ports; then
        print_error "Cannot start services due to port conflicts."
        exit 1
    fi
    
    print_status "Building and starting services with Docker Compose..."
    docker-compose up --build -d
    
    print_status "Waiting for services to be ready..."
    sleep 10
    
    # Check if services are healthy
    if docker-compose ps | grep -q "Up (healthy)"; then
        print_success "Services started successfully!"
        print_status "Available endpoints:"
        echo "  - Donor List HTML: http://localhost:8080/donors/donor/list"
        echo "  - Camel API: http://localhost:8080/donors"
        echo "  - Mock EHR API: http://localhost:3001"
    else
        print_warning "Services may still be starting. Check logs with: ./run.sh logs"
    fi
}

# Function to stop services
stop_services() {
    print_status "Stopping services..."
    docker-compose down
    print_success "Services stopped."
}

# Function to show logs
show_logs() {
    if [ -z "$2" ]; then
        print_status "Showing logs for all services..."
        docker-compose logs -f
    else
        print_status "Showing logs for $2..."
        docker-compose logs -f "$2"
    fi
}

# Function to restart services
restart_services() {
    print_status "Restarting services..."
    docker-compose restart
    print_success "Services restarted."
}

# Function to clean up
cleanup() {
    print_status "Cleaning up Docker resources..."
    docker-compose down -v --remove-orphans
    docker system prune -f
    print_success "Cleanup completed."
}

# Function to run tests
run_tests() {
    print_status "Running tests..."
    
    # Check if services are running
    if ! docker-compose ps | grep -q "Up"; then
        print_status "Starting services for testing..."
        start_services
        sleep 15
    fi
    
    print_status "Testing Mock EHR health..."
    if curl -f http://localhost:3001/health > /dev/null 2>&1; then
        print_success "Mock EHR is healthy"
    else
        print_error "Mock EHR health check failed"
        return 1
    fi
    
    print_status "Testing Camel Middleware health..."
    if curl -f http://localhost:8080/actuator/health > /dev/null 2>&1; then
        print_success "Camel Middleware is healthy"
    else
        print_error "Camel Middleware health check failed"
        return 1
    fi
    
    print_status "Testing donor list endpoint..."
    if curl -f http://localhost:8080/donors/donor/list > /dev/null 2>&1; then
        print_success "Donor list endpoint is working"
    else
        print_error "Donor list endpoint failed"
        return 1
    fi
    
    print_success "All tests passed!"
}

# Function to show status
show_status() {
    print_status "Service Status:"
    docker-compose ps
    
    print_status "Port Usage:"
    echo "Port 3001 (Mock EHR):"
    lsof -i :3001 || echo "  Not in use"
    echo "Port 8080 (Camel Middleware):"
    lsof -i :8080 || echo "  Not in use"
}

# Function to open browser
open_browser() {
    local url="http://localhost:8080/donors/donor/list"
    print_status "Opening browser to $url"
    
    if command -v xdg-open > /dev/null; then
        xdg-open "$url"
    elif command -v open > /dev/null; then
        open "$url"
    else
        print_warning "Cannot open browser automatically. Please visit: $url"
    fi
}

# Function to show help
show_help() {
    echo "Camel Donor Middleware - Development Helper"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  start     Start all services"
    echo "  stop      Stop all services"
    echo "  restart   Restart all services"
    echo "  logs      Show logs for all services"
    echo "  logs <service>  Show logs for specific service (camel-middleware or mock-ehr)"
    echo "  test      Run health checks and basic tests"
    echo "  status    Show service status and port usage"
    echo "  clean     Stop services and clean up Docker resources"
    echo "  open      Open the donor list in browser"
    echo "  help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 start"
    echo "  $0 logs camel-middleware"
    echo "  $0 test"
}

# Main script logic
case "${1:-help}" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        restart_services
        ;;
    logs)
        show_logs "$@"
        ;;
    test)
        run_tests
        ;;
    status)
        show_status
        ;;
    clean)
        cleanup
        ;;
    open)
        open_browser
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac