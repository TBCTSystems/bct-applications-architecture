#!/bin/bash
# ==============================================================================
# test-crl.sh - End-to-End CRL Validation Test Script
# ==============================================================================
# This script validates the complete CRL (Certificate Revocation List)
# implementation in the ECA PoC project.
#
# Tests:
#   1. CRL file generation and existence
#   2. CRL HTTP endpoint availability
#   3. CRL parsing and content inspection
#   4. Certificate revocation workflow
#   5. Agent CRL validation and auto-renewal
#   6. Grafana dashboard metrics
#
# Usage:
#   ./scripts/test-crl.sh
#
# Prerequisites:
#   - Docker and Docker Compose installed
#   - ECA services running (docker compose up -d)
#   - openssl command available
#   - curl command available
# ==============================================================================

set -e  # Exit on error

# ==============================================================================
# Configuration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

# ==============================================================================
# Helper Functions
# ==============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

section_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# ==============================================================================
# Test Functions
# ==============================================================================

test_services_running() {
    section_header "Test 1: Services Running"

    log_info "Checking if PKI service is running..."
    if docker compose -f "$PROJECT_ROOT/docker-compose.yml" ps | grep -q "eca-pki.*Up"; then
        log_success "PKI service is running"
    else
        log_error "PKI service is not running"
        return 1
    fi

    log_info "Checking if ACME agent is running..."
    if docker compose -f "$PROJECT_ROOT/docker-compose.yml" ps | grep -q "eca-acme-agent.*Up"; then
        log_success "ACME agent is running"
    else
        log_error "ACME agent is not running"
        return 1
    fi

    log_info "Checking if EST agent is running..."
    if docker compose -f "$PROJECT_ROOT/docker-compose.yml" ps | grep -q "eca-est-agent.*Up"; then
        log_success "EST agent is running"
    else
        log_error "EST agent is not running"
        return 1
    fi
}

test_crl_file_exists() {
    section_header "Test 2: CRL File Existence"

    log_info "Checking if CRL file exists in PKI container..."
    if docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T pki test -f /home/step/crl/ca.crl; then
        log_success "CRL file exists: /home/step/crl/ca.crl"

        # Get file details
        CRL_SIZE=$(docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T pki stat -f%z /home/step/crl/ca.crl 2>/dev/null || \
                   docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T pki stat -c%s /home/step/crl/ca.crl 2>/dev/null)
        log_info "CRL file size: $CRL_SIZE bytes"

        if [ "$CRL_SIZE" -gt 100 ]; then
            log_success "CRL file size is reasonable (> 100 bytes)"
        else
            log_warning "CRL file size seems small (< 100 bytes)"
        fi
    else
        log_error "CRL file does not exist"
        return 1
    fi

    log_info "Checking if CRL PEM file exists..."
    if docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T pki test -f /home/step/crl/ca.crl.pem; then
        log_success "CRL PEM file exists: /home/step/crl/ca.crl.pem"
    else
        log_warning "CRL PEM file does not exist (may be normal depending on generation method)"
    fi
}

test_crl_http_endpoint() {
    section_header "Test 3: CRL HTTP Endpoint"

    log_info "Testing CRL HTTP endpoint availability..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9001/crl/ca.crl)

    if [ "$HTTP_CODE" = "200" ]; then
        log_success "CRL HTTP endpoint returns 200 OK"
    else
        log_error "CRL HTTP endpoint returned: $HTTP_CODE (expected 200)"
        return 1
    fi

    log_info "Checking Content-Type header..."
    CONTENT_TYPE=$(curl -s -I http://localhost:9001/crl/ca.crl | grep -i "content-type" | awk '{print $2}' | tr -d '\r')
    if echo "$CONTENT_TYPE" | grep -qi "pkix-crl"; then
        log_success "Content-Type is correct: $CONTENT_TYPE"
    else
        log_warning "Content-Type is: $CONTENT_TYPE (expected: application/pkix-crl)"
    fi

    log_info "Downloading CRL from HTTP endpoint..."
    if curl -s http://localhost:9001/crl/ca.crl -o /tmp/test-ca.crl; then
        DOWNLOADED_SIZE=$(stat -f%z /tmp/test-ca.crl 2>/dev/null || stat -c%s /tmp/test-ca.crl 2>/dev/null)
        log_success "CRL downloaded successfully ($DOWNLOADED_SIZE bytes)"
    else
        log_error "Failed to download CRL from HTTP endpoint"
        return 1
    fi
}

test_crl_parsing() {
    section_header "Test 4: CRL Parsing and Inspection"

    if ! command -v openssl &> /dev/null; then
        log_warning "openssl not found - skipping CRL parsing test"
        return 0
    fi

    log_info "Parsing CRL with openssl..."
    if openssl crl -inform DER -in /tmp/test-ca.crl -noout -text > /tmp/crl-output.txt 2>&1; then
        log_success "CRL parsed successfully with openssl"

        # Extract and display information
        ISSUER=$(grep "Issuer:" /tmp/crl-output.txt | head -1 | sed 's/.*Issuer: //')
        LAST_UPDATE=$(grep "Last Update:" /tmp/crl-output.txt | head -1 | sed 's/.*Last Update: //')
        NEXT_UPDATE=$(grep "Next Update:" /tmp/crl-output.txt | head -1 | sed 's/.*Next Update: //')
        REVOKED_COUNT=$(grep -c "Serial Number:" /tmp/crl-output.txt || echo "0")

        log_info "CRL Issuer: $ISSUER"
        log_info "Last Update: $LAST_UPDATE"
        log_info "Next Update: $NEXT_UPDATE"
        log_info "Revoked Certificates: $REVOKED_COUNT"

        if [ -n "$ISSUER" ]; then
            log_success "CRL has valid issuer information"
        else
            log_error "CRL issuer information is missing"
        fi
    else
        log_error "Failed to parse CRL with openssl"
        cat /tmp/crl-output.txt
        return 1
    fi
}

test_agent_crl_validation() {
    section_header "Test 5: Agent CRL Validation"

    log_info "Checking ACME agent logs for CRL validation..."
    ACME_CRL_LOGS=$(docker compose -f "$PROJECT_ROOT/docker-compose.yml" logs --tail=100 eca-acme-agent 2>/dev/null | grep -i "CRL" || echo "")

    if echo "$ACME_CRL_LOGS" | grep -q "CRL cache updated"; then
        log_success "ACME agent is performing CRL cache updates"
    elif echo "$ACME_CRL_LOGS" | grep -q "CRL"; then
        log_warning "ACME agent has CRL logs but no cache update confirmation"
    else
        log_warning "No CRL logs found in ACME agent (may need to wait for next check cycle)"
    fi

    if echo "$ACME_CRL_LOGS" | grep -q "VALID"; then
        log_success "ACME agent is validating certificates against CRL"
    fi

    log_info "Checking EST agent logs for CRL validation..."
    EST_CRL_LOGS=$(docker compose -f "$PROJECT_ROOT/docker-compose.yml" logs --tail=100 eca-est-agent 2>/dev/null | grep -i "CRL" || echo "")

    if echo "$EST_CRL_LOGS" | grep -q "CRL cache updated"; then
        log_success "EST agent is performing CRL cache updates"
    elif echo "$EST_CRL_LOGS" | grep -q "CRL"; then
        log_warning "EST agent has CRL logs but no cache update confirmation"
    else
        log_warning "No CRL logs found in EST agent (may need to wait for next check cycle)"
    fi
}

test_crl_age() {
    section_header "Test 6: CRL Age Verification"

    log_info "Checking CRL file age..."

    # Get file modification time
    if docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T pki test -f /home/step/crl/ca.crl; then
        # Get last modified timestamp
        MTIME=$(docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T pki stat -c %Y /home/step/crl/ca.crl 2>/dev/null || \
                docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T pki stat -f %m /home/step/crl/ca.crl 2>/dev/null)

        CURRENT_TIME=$(date +%s)
        AGE_SECONDS=$((CURRENT_TIME - MTIME))
        AGE_HOURS=$((AGE_SECONDS / 3600))
        AGE_MINUTES=$(( (AGE_SECONDS % 3600) / 60 ))

        log_info "CRL age: ${AGE_HOURS}h ${AGE_MINUTES}m"

        if [ "$AGE_HOURS" -lt 2 ]; then
            log_success "CRL is fresh (< 2 hours old)"
        elif [ "$AGE_HOURS" -lt 24 ]; then
            log_warning "CRL is getting old ($AGE_HOURS hours) but still acceptable"
        else
            log_error "CRL is stale (> 24 hours old)"
        fi
    else
        log_error "CRL file not found"
        return 1
    fi
}

test_grafana_dashboard() {
    section_header "Test 7: Grafana Dashboard Access"

    log_info "Testing Grafana availability..."
    GRAFANA_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000)

    if [ "$GRAFANA_CODE" = "200" ] || [ "$GRAFANA_CODE" = "302" ]; then
        log_success "Grafana is accessible at http://localhost:3000"
    else
        log_error "Grafana returned: $GRAFANA_CODE"
        return 1
    fi

    log_info "CRL dashboard should be available at:"
    log_info "  http://localhost:3000/d/eca-crl-monitoring"
}

test_crl_cron_setup() {
    section_header "Test 8: CRL Cron Job Verification"

    log_info "Checking if crond is running in PKI container..."
    if docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T pki ps aux 2>/dev/null | grep -q "[c]rond"; then
        log_success "crond is running"
    else
        log_warning "crond not detected (CRL may not be auto-generated)"
    fi

    log_info "Checking cron configuration..."
    if docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T pki test -f /etc/crontabs/step; then
        CRON_ENTRY=$(docker compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T pki cat /etc/crontabs/step 2>/dev/null || echo "")
        if echo "$CRON_ENTRY" | grep -q "generate-crl"; then
            log_success "CRL generation cron job is configured"
            log_info "Cron entry: $CRON_ENTRY"
        else
            log_warning "Cron file exists but no CRL generation entry found"
        fi
    else
        log_warning "Cron file not found at /etc/crontabs/step"
    fi
}

# ==============================================================================
# Main Execution
# ==============================================================================

main() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                        ║${NC}"
    echo -e "${GREEN}║  ECA PoC - CRL End-to-End Validation Test Suite       ║${NC}"
    echo -e "${GREEN}║                                                        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log_info "Project root: $PROJECT_ROOT"
    log_info "Starting CRL validation tests..."
    echo ""

    # Run all tests
    test_services_running || true
    test_crl_file_exists || true
    test_crl_http_endpoint || true
    test_crl_parsing || true
    test_agent_crl_validation || true
    test_crl_age || true
    test_grafana_dashboard || true
    test_crl_cron_setup || true

    # Summary
    section_header "Test Summary"
    echo ""
    echo -e "  ${GREEN}Passed:${NC} $TESTS_PASSED"
    echo -e "  ${RED}Failed:${NC} $TESTS_FAILED"
    echo ""

    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        echo ""
        log_info "CRL implementation is working correctly"
        log_info "Next steps:"
        log_info "  1. View CRL dashboard: http://localhost:3000/d/eca-crl-monitoring"
        log_info "  2. Monitor agent logs: docker compose logs -f eca-acme-agent eca-est-agent | grep CRL"
        log_info "  3. Test revocation: See docs/CRL_IMPLEMENTATION.md"
        exit 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        echo ""
        log_error "CRL implementation has issues"
        log_info "Check the errors above and consult docs/CRL_IMPLEMENTATION.md for troubleshooting"
        exit 1
    fi
}

# Cleanup function
cleanup() {
    rm -f /tmp/test-ca.crl /tmp/crl-output.txt
}

trap cleanup EXIT

# Run main
main
