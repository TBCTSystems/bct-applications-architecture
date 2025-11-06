#!/bin/bash

# ============================================
# ECA Logging Verification Script
# ============================================
# This script verifies that the observability stack is working correctly
# by testing each component of the logging pipeline.
#
# Usage:
#   ./scripts/verify-logging.sh [OPTIONS]
#
# Options:
#   -v, --verbose    Show detailed output
#   -q, --quiet      Suppress non-error output
#   -h, --help       Show this help message
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
VERBOSE=false
QUIET=false
FAILED_TESTS=0
PASSED_TESTS=0

# ============================================
# Helper Functions
# ============================================

print_header() {
    if [ "$QUIET" = false ]; then
        echo -e "\n${BLUE}===========================================================${NC}"
        echo -e "${BLUE}$1${NC}"
        echo -e "${BLUE}===========================================================${NC}"
    fi
}

print_test() {
    if [ "$QUIET" = false ]; then
        echo -e "\n${YELLOW}▶ $1${NC}"
    fi
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
}

print_info() {
    if [ "$VERBOSE" = true ]; then
        echo -e "  ${NC}$1${NC}"
    fi
}

print_usage() {
    cat << EOF
ECA Logging Verification Script

Usage: $0 [OPTIONS]

Options:
  -v, --verbose    Show detailed output including API responses
  -q, --quiet      Suppress non-error output (only show results)
  -h, --help       Show this help message

Exit Codes:
  0 - All tests passed
  1 - One or more tests failed
  2 - Script error or missing dependencies

Examples:
  $0                # Run all tests with normal output
  $0 -v             # Run with verbose output
  $0 -q             # Run quietly, only show pass/fail

EOF
}

# ============================================
# Dependency Checks
# ============================================

check_dependencies() {
    print_header "Checking Dependencies"

    local deps=("docker" "curl" "jq")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
            print_error "Missing dependency: $dep"
        else
            print_info "Found: $dep ($(command -v "$dep"))"
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "\n${RED}Error: Missing required dependencies: ${missing[*]}${NC}"
        echo "Please install missing tools and try again."
        exit 2
    fi

    print_success "All dependencies present"
}

# ============================================
# Container Health Checks
# ============================================

check_container_running() {
    local container=$1
    local status

    status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "not found")

    if [ "$status" = "running" ]; then
        return 0
    else
        return 1
    fi
}

check_container_health() {
    local container=$1
    local health

    health=$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")

    if [ "$health" = "healthy" ] || [ "$health" = "none" ]; then
        return 0
    else
        return 1
    fi
}

test_fluentd_container() {
    print_test "Test 1: FluentD Container Status"

    if check_container_running "eca-fluentd"; then
        print_info "Container is running"

        # Check logs for worker started
        if docker logs eca-fluentd 2>&1 | grep -q "fluentd worker is now running"; then
            print_success "FluentD container is running and worker started"
        else
            print_error "FluentD container running but worker not started"
            if [ "$VERBOSE" = true ]; then
                echo "Recent logs:"
                docker logs --tail 20 eca-fluentd 2>&1 | sed 's/^/  /'
            fi
        fi
    else
        print_error "FluentD container is not running"
    fi
}

test_loki_container() {
    print_test "Test 2: Loki Container Status"

    if check_container_running "eca-loki"; then
        print_info "Container is running"

        if check_container_health "eca-loki"; then
            print_success "Loki container is running and healthy"
        else
            print_error "Loki container running but not healthy"
        fi
    else
        print_error "Loki container is not running"
    fi
}

test_grafana_container() {
    print_test "Test 3: Grafana Container Status"

    if check_container_running "eca-grafana"; then
        print_info "Container is running"

        if check_container_health "eca-grafana"; then
            print_success "Grafana container is running and healthy"
        else
            print_error "Grafana container running but not healthy"
        fi
    else
        print_error "Grafana container is not running"
    fi
}

# ============================================
# Service Health Checks
# ============================================

test_fluentd_health() {
    print_test "Test 4: FluentD Health Endpoint"

    local response
    response=$(curl -s -w "\n%{http_code}" http://localhost:24220/api/plugins.json 2>/dev/null || echo "000")
    local body=$(echo "$response" | head -n -1)
    local http_code=$(echo "$response" | tail -n 1)

    if [ "$http_code" = "200" ]; then
        local plugin_count=$(echo "$body" | jq '. | length' 2>/dev/null || echo 0)
        print_info "HTTP $http_code - Found $plugin_count plugins"
        print_success "FluentD monitoring endpoint is responding"

        if [ "$VERBOSE" = true ]; then
            echo "  Plugins:"
            echo "$body" | jq -r '.plugins[] | "    - \(.type): \(.plugin_id)"' 2>/dev/null || true
        fi
    else
        print_error "FluentD monitoring endpoint not responding (HTTP $http_code)"
    fi
}

test_loki_health() {
    print_test "Test 5: Loki Health Endpoint"

    local response
    response=$(curl -s http://localhost:3100/ready 2>/dev/null || echo "")

    if [ "$response" = "ready" ]; then
        print_success "Loki is ready and accepting queries"
    else
        print_error "Loki is not ready (response: '$response')"
    fi
}

test_grafana_health() {
    print_test "Test 6: Grafana Health API"

    local response
    response=$(curl -s http://localhost:3000/api/health 2>/dev/null || echo "{}")

    local database=$(echo "$response" | jq -r '.database' 2>/dev/null || echo "")

    if [ "$database" = "ok" ]; then
        local version=$(echo "$response" | jq -r '.version' 2>/dev/null || echo "unknown")
        print_info "Version: $version, Database: $database"
        print_success "Grafana is healthy and database is connected"
    else
        print_error "Grafana health check failed"
        if [ "$VERBOSE" = true ]; then
            echo "  Response: $response"
        fi
    fi
}

# ============================================
# Log Flow Tests
# ============================================

test_agent_containers() {
    print_test "Test 7: Agent Containers Running"

    local agents=("eca-acme-agent" "eca-est-agent")
    local all_running=true

    for agent in "${agents[@]}"; do
        if check_container_running "$agent"; then
            print_info "$agent is running"
        else
            print_info "$agent is NOT running"
            all_running=false
        fi
    done

    if [ "$all_running" = true ]; then
        print_success "All agent containers are running"
    else
        print_error "One or more agent containers are not running"
    fi
}

test_loki_has_logs() {
    print_test "Test 8: Loki Contains Logs"

    # Ensure fresh log events exist before querying
    print_info "Restarting agents to generate fresh log traffic..."
    docker restart eca-acme-agent > /dev/null 2>&1 || true
    docker restart eca-est-agent > /dev/null 2>&1 || true
    sleep 10

    # Query for any logs from ACME agent
    local response
    response=$(curl -s -G http://localhost:3100/loki/api/v1/query \
        --data-urlencode 'query={agent_type="acme"}' \
        --data-urlencode 'limit=10' 2>/dev/null || echo '{"data":{"result":[]}}')

    local acme_count=$(echo "$response" | jq '.data.result | length' 2>/dev/null || echo 0)

    # Query for any logs from EST agent
    response=$(curl -s -G http://localhost:3100/loki/api/v1/query \
        --data-urlencode 'query={agent_type="est"}' \
        --data-urlencode 'limit=10' 2>/dev/null || echo '{"data":{"result":[]}}')

    local est_count=$(echo "$response" | jq '.data.result | length' 2>/dev/null || echo 0)

    print_info "ACME logs found: $acme_count stream(s)"
    print_info "EST logs found: $est_count stream(s)"

    if [ "$acme_count" -gt 0 ] && [ "$est_count" -gt 0 ]; then
        print_success "Loki contains logs from both agents"
    elif [ "$acme_count" -gt 0 ] || [ "$est_count" -gt 0 ]; then
        print_error "Loki contains logs from only one agent (ACME: $acme_count, EST: $est_count)"
    else
        print_error "Loki contains no logs from agents"
    fi
}

test_log_labels() {
    print_test "Test 9: Log Labels and Structure"

    # Query recent logs and check for expected labels
    local response
    response=$(curl -s -G http://localhost:3100/loki/api/v1/query \
        --data-urlencode 'query={agent_type=~"acme|est"}' \
        --data-urlencode 'limit=1' 2>/dev/null || echo '{"data":{"result":[]}}')

    local result_count=$(echo "$response" | jq '.data.result | length' 2>/dev/null || echo 0)

    if [ "$result_count" -gt 0 ]; then
        local labels=$(echo "$response" | jq -r '.data.result[0].stream' 2>/dev/null)

        print_info "Sample log labels:"
        if [ "$VERBOSE" = true ]; then
            echo "$labels" | jq '.' | sed 's/^/    /'
        fi

        # Check for required labels
        local has_agent_type=$(echo "$labels" | jq -r '.agent_type' 2>/dev/null)
        local has_severity=$(echo "$labels" | jq -r '.severity' 2>/dev/null)
        local source_context=$(echo "$labels" | jq -r '.container_name // .job // .environment // empty' 2>/dev/null)

        if [ "$has_agent_type" != "null" ] && [ "$has_severity" != "null" ] && [ -n "$source_context" ]; then
            print_success "Logs have proper labels (agent_type: $has_agent_type, context: $source_context, severity: $has_severity)"
        else
            print_error "Logs missing expected labels"
        fi
    else
        print_error "No logs found to verify labels"
    fi
}

# ============================================
# End-to-End Test
# ============================================

test_log_generation() {
    print_test "Test 10: End-to-End Log Flow (Generate & Verify)"

    print_info "Restarting ACME agent to generate logs..."
    docker restart eca-acme-agent > /dev/null 2>&1

    print_info "Waiting 15 seconds for logs to propagate..."
    sleep 15

    # Query for "Agent started" or similar startup log
    local response
    response=$(curl -s -G http://localhost:3100/loki/api/v1/query \
        --data-urlencode 'query={agent_type="acme"} |= "started"' \
        --data-urlencode 'limit=5' 2>/dev/null || echo '{"data":{"result":[]}}')

    local result_count=$(echo "$response" | jq '.data.result | length' 2>/dev/null || echo 0)

    if [ "$result_count" -gt 0 ]; then
        local latest_log=$(echo "$response" | jq -r '.data.result[0].values[-1][1]' 2>/dev/null)
        print_info "Latest log: ${latest_log:0:100}..."
        print_success "End-to-end log flow verified (logs generated and retrieved)"
    else
        print_error "No startup logs found after agent restart"

        # Debugging info
        print_info "Checking if agent is logging at all..."
        response=$(curl -s -G http://localhost:3100/loki/api/v1/query \
            --data-urlencode 'query={agent_type="acme"}' \
            --data-urlencode 'limit=1' 2>/dev/null || echo '{"data":{"result":[]}}')

        result_count=$(echo "$response" | jq '.data.result | length' 2>/dev/null || echo 0)
        if [ "$result_count" -gt 0 ]; then
            print_info "Agent is logging, but no recent startup logs found"
        else
            print_info "No logs from ACME agent at all - check FluentD configuration"
        fi
    fi
}

# ============================================
# Grafana Integration Tests
# ============================================

test_grafana_datasource() {
    print_test "Test 11: Grafana Loki Datasource"

    # Note: This requires authentication, using default credentials
    local response
    response=$(curl -s -u admin:eca-admin \
        http://localhost:3000/api/datasources/name/Loki 2>/dev/null || echo '{}')

    local ds_type=$(echo "$response" | jq -r '.type' 2>/dev/null)
    local ds_url=$(echo "$response" | jq -r '.url' 2>/dev/null)

    if [ "$ds_type" = "loki" ]; then
        print_info "Datasource URL: $ds_url"
        print_success "Grafana Loki datasource is configured"
    else
        print_error "Grafana Loki datasource not found or misconfigured"
        if [ "$VERBOSE" = true ]; then
            echo "  Response: $response"
        fi
    fi
}

test_grafana_dashboards() {
    print_test "Test 12: Grafana Dashboards Loaded"

    local response
    response=$(curl -s -u admin:eca-admin \
        http://localhost:3000/api/search?type=dash-db 2>/dev/null || echo '[]')

    local dashboard_count=$(echo "$response" | jq '. | length' 2>/dev/null || echo 0)

    if [ "$dashboard_count" -ge 3 ]; then
        print_info "Found $dashboard_count dashboards"

        if [ "$VERBOSE" = true ]; then
            echo "  Dashboards:"
            echo "$response" | jq -r '.[] | "    - \(.title)"' 2>/dev/null || true
        fi

        # Check for ECA-specific dashboards
        local eca_count=$(echo "$response" | jq '[.[] | select(.title | contains("ECA"))] | length' 2>/dev/null || echo 0)

        if [ "$eca_count" -ge 3 ]; then
            print_success "All expected ECA dashboards are loaded"
        else
            print_error "Expected at least 3 ECA dashboards, found $eca_count"
        fi
    else
        print_error "Expected at least 3 dashboards, found $dashboard_count"
    fi
}

# ============================================
# Performance Tests
# ============================================

test_resource_usage() {
    print_test "Test 13: Resource Usage Check"

    local containers=("eca-fluentd" "eca-loki" "eca-grafana")
    local total_mem=0
    local warning=false

    for container in "${containers[@]}"; do
        if check_container_running "$container"; then
            local stats
            stats=$(docker stats --no-stream --format "{{.MemUsage}}" "$container" 2>/dev/null || echo "0B / 0B")
            local mem=$(echo "$stats" | awk '{print $1}')

            print_info "$container: $mem"

            # Check if memory usage is concerning (>1GB for any single service)
            local mem_mb=$(echo "$mem" | sed 's/MiB//' | sed 's/GiB/000/' | sed 's/KiB/0.001/' | awk '{print int($1)}')
            if [ "$mem_mb" -gt 1000 ]; then
                warning=true
            fi
        fi
    done

    if [ "$warning" = true ]; then
        print_error "One or more services using >1GB memory (may be normal, check thresholds)"
    else
        print_success "All observability services within expected memory usage"
    fi
}

# ============================================
# Buffer and Reliability Tests
# ============================================

test_fluentd_buffer() {
    print_test "Test 14: FluentD Buffer Configuration"

    # Check if buffer directory exists in container
    if docker exec eca-fluentd ls /var/log/fluentd/buffer > /dev/null 2>&1; then
        local buffer_files
        buffer_files=$(docker exec eca-fluentd find /var/log/fluentd/buffer -type f 2>/dev/null | wc -l)

        print_info "Buffer directory exists, $buffer_files file(s) currently buffered"
        print_success "FluentD buffer is configured and accessible"

        if [ "$buffer_files" -gt 100 ]; then
            print_info "Warning: Large number of buffer files may indicate Loki connectivity issues"
        fi
    else
        print_error "FluentD buffer directory not accessible"
    fi
}

# ============================================
# Main Execution
# ============================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
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
    print_header "ECA Observability Stack Verification"
    echo -e "${NC}Testing logging infrastructure: FluentD → Loki → Grafana${NC}"

    # Run all tests
    check_dependencies

    print_header "Container Health Checks"
    test_fluentd_container
    test_loki_container
    test_grafana_container

    print_header "Service Health Endpoints"
    test_fluentd_health
    test_loki_health
    test_grafana_health

    print_header "Log Flow Verification"
    test_agent_containers
    test_loki_has_logs
    test_log_labels
    test_log_generation

    print_header "Grafana Integration"
    test_grafana_datasource
    test_grafana_dashboards

    print_header "Performance & Reliability"
    test_resource_usage
    test_fluentd_buffer

    # Summary
    print_header "Test Summary"
    local total_tests=$((PASSED_TESTS + FAILED_TESTS))

    echo -e "Total Tests: $total_tests"
    echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "${RED}Failed: $FAILED_TESTS${NC}"

    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "\n${GREEN}✓ All tests passed! Logging system is fully operational.${NC}"
        echo -e "${NC}Access Grafana at: ${BLUE}http://localhost:3000${NC} (admin/eca-admin)"
        exit 0
    else
        echo -e "\n${RED}✗ Some tests failed. Please review the output above.${NC}"
        echo -e "${NC}For troubleshooting, see: ${BLUE}OBSERVABILITY_QUICKSTART.md${NC}"
        exit 1
    fi
}

# Run main function
main "$@"
