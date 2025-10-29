#!/bin/bash

# ============================================
# ECA Docker Test Runner Script
# ============================================
# Runs all tests inside Docker containers for consistent test environment.
# No local PowerShell installation required!
#
# Usage:
#   ./scripts/run-tests-docker.sh [OPTIONS]
#
# Options:
#   -u, --unit-only       Run only unit tests
#   -i, --integration-only Run only integration tests
#   -c, --coverage        Generate code coverage report
#   -b, --build           Rebuild test runner image
#   -h, --help            Show this help message
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
#   2 - Script error or missing dependencies

set -euo pipefail

# ============================================
# Configuration
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
RUN_UNIT_TESTS=true
RUN_INTEGRATION_TESTS=true
GENERATE_COVERAGE=false
BUILD_IMAGE=false

# ============================================
# Helper Functions
# ============================================

print_header() {
    echo -e "\n${BLUE}===========================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===========================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${NC}  $1${NC}"
}

print_usage() {
    cat << EOF
ECA Docker Test Runner Script

Usage: $0 [OPTIONS]

Options:
  -u, --unit-only       Run only unit tests
  -i, --integration-only Run only integration tests
  -c, --coverage        Generate code coverage report
  -b, --build           Rebuild test runner Docker image
  -h, --help            Show this help message

Examples:
  $0                    # Run all tests in Docker
  $0 -u                 # Run only unit tests
  $0 -b                 # Rebuild image and run all tests
  $0 -c                 # Run all tests with coverage report

Advantages of Docker test runner:
  - No local PowerShell installation needed
  - Consistent test environment across all machines
  - Isolated from host system
  - Works identically in CI/CD and locally

EOF
}

# ============================================
# Dependency Checks
# ============================================

check_dependencies() {
    print_header "Checking Dependencies"

    # Check for Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        echo "Please install Docker from https://docs.docker.com/engine/install/"
        exit 2
    fi
    print_info "Found: docker $(docker --version | grep -oP '(?<=version )\S+')"

    # Check for Docker Compose
    if ! docker compose version &> /dev/null 2>&1; then
        print_error "Docker Compose is not available"
        echo "Please install Docker Compose v2"
        exit 2
    fi
    print_info "Found: $(docker compose version)"

    print_success "All dependencies present"
}

# ============================================
# Docker Image Management
# ============================================

build_test_image() {
    print_header "Building Test Runner Image"

    cd "$PROJECT_DIR"

    if docker compose build test-runner; then
        print_success "Test runner image built successfully"
    else
        print_error "Failed to build test runner image"
        exit 1
    fi
}

ensure_test_image() {
    # Check if image exists
    if ! docker images | grep -q "eca-test-runner" && [ "$BUILD_IMAGE" = false ]; then
        print_info "Test runner image not found, building..."
        build_test_image
    elif [ "$BUILD_IMAGE" = true ]; then
        build_test_image
    else
        print_info "Using existing test runner image"
    fi
}

# ============================================
# Test Execution
# ============================================

run_unit_tests() {
    print_header "Running Unit Tests (Docker)"

    cd "$PROJECT_DIR"

    local coverage_flag=""
    if [ "$GENERATE_COVERAGE" = true ]; then
        coverage_flag="-e GENERATE_COVERAGE=true"
    fi

    # Run unit tests in Docker
    if docker compose run --rm $coverage_flag test-runner pwsh -Command "
        \$config = New-PesterConfiguration
        \$config.Run.Path = './tests/unit'
        \$config.Run.Exit = \$true
        \$config.Output.Verbosity = 'Normal'

        if (\$env:GENERATE_COVERAGE -eq 'true') {
            \$config.CodeCoverage.Enabled = \$true
            \$config.CodeCoverage.Path = @(
                './agents/acme/AcmeClient.psm1',
                './agents/est/EstClient.psm1',
                './agents/est/BootstrapTokenManager.psm1'
            )
            \$config.CodeCoverage.OutputFormat = 'JaCoCo'
            \$config.CodeCoverage.OutputPath = './tests/coverage.xml'
        }

        Invoke-Pester -Configuration \$config
    "; then
        print_success "Unit tests passed"
        return 0
    else
        print_error "Unit tests failed"
        return 1
    fi
}

run_integration_tests() {
    print_header "Running Integration Tests (Docker)"

    cd "$PROJECT_DIR"

    # Ensure PKI services are running
    print_info "Starting PKI infrastructure..."
    docker compose up -d pki openxpki-web openxpki-client openxpki-server target-server

    # Wait for services to be healthy
    print_info "Waiting for PKI services to be healthy..."
    local max_wait=60
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if docker compose ps | grep -q "eca-pki.*healthy"; then
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        print_info "Waiting... (${elapsed}s/${max_wait}s)"
    done

    # Check if integration tests exist
    if [ ! -d "./tests/integration" ] || [ -z "$(ls -A ./tests/integration/*.Tests.ps1 2>/dev/null)" ]; then
        print_info "No integration tests found (./tests/integration/*.Tests.ps1)"
        print_info "Skipping integration tests"
        return 0
    fi

    # Run integration tests in Docker (connected to same network as PKI)
    if docker compose run --rm test-runner pwsh -Command "
        \$config = New-PesterConfiguration
        \$config.Run.Path = './tests/integration'
        \$config.Run.Exit = \$true
        \$config.Output.Verbosity = 'Normal'

        Invoke-Pester -Configuration \$config
    "; then
        print_success "Integration tests passed"
        return 0
    else
        print_error "Integration tests failed"
        return 1
    fi
}

# ============================================
# Main Execution
# ============================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--unit-only)
                RUN_UNIT_TESTS=true
                RUN_INTEGRATION_TESTS=false
                shift
                ;;
            -i|--integration-only)
                RUN_UNIT_TESTS=false
                RUN_INTEGRATION_TESTS=true
                shift
                ;;
            -c|--coverage)
                GENERATE_COVERAGE=true
                shift
                ;;
            -b|--build)
                BUILD_IMAGE=true
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                print_usage
                exit 2
                ;;
        esac
    done

    # Start tests
    print_header "ECA Docker Test Suite"
    echo -e "${NC}Running tests in isolated Docker containers${NC}"

    # Check dependencies
    check_dependencies

    # Ensure test image exists
    ensure_test_image

    local unit_result=0
    local integration_result=0

    # Run unit tests
    if [ "$RUN_UNIT_TESTS" = true ]; then
        run_unit_tests || unit_result=$?
    fi

    # Run integration tests
    if [ "$RUN_INTEGRATION_TESTS" = true ]; then
        run_integration_tests || integration_result=$?
    fi

    # Summary
    print_header "Test Summary"

    if [ "$RUN_UNIT_TESTS" = true ]; then
        if [ $unit_result -eq 0 ]; then
            print_success "Unit Tests: PASSED"
        else
            print_error "Unit Tests: FAILED"
        fi
    fi

    if [ "$RUN_INTEGRATION_TESTS" = true ]; then
        if [ $integration_result -eq 0 ]; then
            print_success "Integration Tests: PASSED"
        else
            print_error "Integration Tests: FAILED"
        fi
    fi

    if [ "$GENERATE_COVERAGE" = true ]; then
        if [ -f "$PROJECT_DIR/tests/coverage.xml" ]; then
            echo ""
            print_info "Coverage report generated: tests/coverage.xml"
        else
            echo ""
            print_info "Coverage report not found (may need to extract from container)"
        fi
    fi

    # Exit with appropriate code
    if [ $unit_result -ne 0 ] || [ $integration_result -ne 0 ]; then
        echo ""
        print_error "Some tests failed. Please review output above."
        exit 1
    else
        echo ""
        print_success "All tests passed!"
        exit 0
    fi
}

# Run main function
main "$@"
