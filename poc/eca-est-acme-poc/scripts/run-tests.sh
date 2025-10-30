#!/bin/bash

# ============================================
# ECA Test Runner Script
# ============================================
# Runs all unit and integration tests for the ECA PoC project.
#
# Usage:
#   ./scripts/run-tests.sh [OPTIONS]
#
# Options:
#   -u, --unit-only       Run only unit tests
#   -i, --integration-only Run only integration tests
#   -c, --coverage        Generate code coverage report
#   -v, --verbose         Show verbose test output
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
VERBOSE=false
AUTO_START_INTEGRATION=false

INTEGRATION_SERVICES=(
    pki
    openxpki-db
    openxpki-server
    openxpki-client
    openxpki-web
)

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
ECA Test Runner Script

Usage: $0 [OPTIONS]

Options:
  -u, --unit-only       Run only unit tests
  -i, --integration-only Run only integration tests
  -c, --coverage        Generate code coverage report
  -v, --verbose         Show verbose test output
  -a, --auto-start-integration  Automatically run `docker compose up` for integration prerequisites
  -h, --help            Show this help message

Examples:
  $0                    # Run all tests
  $0 -u                 # Run only unit tests
  $0 -i                 # Run only integration tests
  $0 -c                 # Run all tests with coverage report
  $0 -u -v              # Run unit tests with verbose output

EOF
}

ensure_docker_available() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        echo "Please install Docker from https://docs.docker.com/engine/install/"
        exit 2
    fi

    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose v2 is not available"
        echo "Please install Docker Compose v2 (bundled with recent Docker Desktop/CLI)."
        exit 2
    fi
}

wait_for_service_ready() {
    local service=$1
    local timeout=${2:-180}
    local interval=5
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        local container_id
        container_id=$(docker compose ps -q "$service" 2>/dev/null)

        if [ -z "$container_id" ]; then
            sleep $interval
            elapsed=$((elapsed + interval))
            continue
        fi

        local status
        status=$(docker inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container_id" 2>/dev/null)

        case "$status" in
            *healthy*|running*)
                return 0
                ;;
        esac

        sleep $interval
        elapsed=$((elapsed + interval))
    done

    return 1
}

prepare_integration_stack() {
    print_header "Preparing Integration Stack"
    ensure_docker_available

    local running
    running=$(docker compose ps --services --filter "status=running" 2>/dev/null)

    local missing=()
    for svc in "${INTEGRATION_SERVICES[@]}"; do
        if ! grep -Fxq "$svc" <<< "$running"; then
            missing+=("$svc")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        print_success "Integration services already running"
        return 0
    fi

    if [ "$AUTO_START_INTEGRATION" = true ]; then
        print_info "Starting integration services via docker compose up -d ${INTEGRATION_SERVICES[*]}"
        if ! docker compose up -d "${INTEGRATION_SERVICES[@]}"; then
            print_error "Failed to start integration services"
            return 1
        fi

        print_info "Waiting for services to report running/healthy..."
        for svc in "${INTEGRATION_SERVICES[@]}"; do
            if wait_for_service_ready "$svc" 240; then
                print_info "  $svc ready"
            else
                print_error "  $svc did not become ready in time"
                return 1
            fi
        done

        print_success "Integration services ready"
        return 0
    fi

    print_error "Integration services are not running: ${missing[*]}"
    echo "Start them manually with: docker compose up -d ${INTEGRATION_SERVICES[*]}"
    echo "Or rerun this script with --auto-start-integration to manage them automatically."
    return 1
}

# ============================================
# Dependency Checks
# ============================================

check_dependencies() {
    print_header "Checking Dependencies"

    # Check for pwsh
    if ! command -v pwsh &> /dev/null; then
        print_error "PowerShell Core (pwsh) is not installed"
        echo "Please install PowerShell 7.0+ from https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell"
        exit 2
    fi
    print_info "Found: pwsh $(pwsh -Version 2>&1 | grep -oP '(?<=PowerShell )\S+')"

    # Check for Pester module
    if ! pwsh -Command "Get-Module -ListAvailable Pester | Select-Object -First 1" &> /dev/null; then
        print_error "Pester module is not installed"
        echo "Installing Pester module..."
        pwsh -Command "Install-Module -Name Pester -MinimumVersion 5.0 -Force -Scope CurrentUser"
    else
        local pester_version
        pester_version=$(pwsh -Command "Get-Module -ListAvailable Pester | Select-Object -First 1 -ExpandProperty Version")
        print_info "Found: Pester $pester_version"
    fi

    print_success "All dependencies present"
}

# ============================================
# Test Execution
# ============================================

run_unit_tests() {
    print_header "Running Unit Tests"

    cd "$PROJECT_DIR"

    local pester_args=""
    if [ "$VERBOSE" = true ]; then
        pester_args="-Output Detailed"
    else
        pester_args="-Output Normal"
    fi

    if [ "$GENERATE_COVERAGE" = true ]; then
        print_info "Generating code coverage report..."

        # Run with coverage
        pwsh -Command "
            \$config = New-PesterConfiguration
            \$config.Run.Path = './tests/unit'
            \$config.Run.Exit = \$true
            \$config.Output.Verbosity = '$( [ "$VERBOSE" = true ] && echo "Detailed" || echo "Normal" )'
            \$config.CodeCoverage.Enabled = \$true
            \$config.CodeCoverage.Path = @(
                './agents/acme/AcmeClient.psm1',
                './agents/est/EstClient.psm1',
                './agents/est/BootstrapTokenManager.psm1'
            )
            \$config.CodeCoverage.OutputFormat = 'JaCoCo'
            \$config.CodeCoverage.OutputPath = './tests/coverage.xml'

            Invoke-Pester -Configuration \$config
        "
    else
        # Run without coverage
        pwsh -Command "
            \$config = New-PesterConfiguration
            \$config.Run.Path = './tests/unit'
            \$config.Run.Exit = \$true
            \$config.Output.Verbosity = '$( [ "$VERBOSE" = true ] && echo "Detailed" || echo "Normal" )'

            Invoke-Pester -Configuration \$config
        "
    fi

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        print_success "Unit tests passed"
        return 0
    else
        print_error "Unit tests failed (exit code: $exit_code)"
        return 1
    fi
}

run_integration_tests() {
    print_header "Running Integration Tests"

    cd "$PROJECT_DIR"

    if ! prepare_integration_stack; then
        return 1
    fi

    # Check if integration tests exist
    if [ ! -d "./tests/integration" ] || [ -z "$(ls -A ./tests/integration/*.Tests.ps1 2>/dev/null)" ]; then
        print_info "No integration tests found (./tests/integration/*.Tests.ps1)"
        print_info "Skipping integration tests"
        return 0
    fi

    local pester_args=""
    if [ "$VERBOSE" = true ]; then
        pester_args="-Output Detailed"
    else
        pester_args="-Output Normal"
    fi

    local exit_code=0

    if docker compose run --rm test-runner pwsh -Command "
        \$config = New-PesterConfiguration
        \$config.Run.Path = './tests/integration'
        \$config.Run.Exit = \$true
        \$config.Output.Verbosity = '$( [ "$VERBOSE" = true ] && echo "Detailed" || echo "Normal" )'

        Invoke-Pester -Configuration \$config
    "; then
        exit_code=0
    else
        exit_code=$?
    fi

    if [ $exit_code -eq 0 ]; then
        print_success "Integration tests passed"
        return 0
    else
        print_error "Integration tests failed (exit code: $exit_code)"
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
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -a|--auto-start-integration)
                AUTO_START_INTEGRATION=true
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
    print_header "ECA Test Suite"
    echo -e "${NC}Testing PowerShell modules with Pester${NC}"

    # Check dependencies
    check_dependencies

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

    if [ "$GENERATE_COVERAGE" = true ] && [ -f "$PROJECT_DIR/tests/coverage.xml" ]; then
        echo ""
        print_info "Coverage report generated: tests/coverage.xml"
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
