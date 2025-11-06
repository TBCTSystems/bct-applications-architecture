#!/usr/bin/env bash
################################################################################
# mTLS Connection Test Script
#
# Purpose: Test mutual TLS connectivity from target-client to target-server
#          using client certificates issued by EST agent and server certificates
#          issued by ACME agent.
#
# Features:
#   - Validates client certificate and key files exist
#   - Performs mTLS handshake using curl
#   - Verifies TLS handshake success
#   - Validates HTTP 200 response from target-server
#   - Includes comprehensive error handling and colored output
#
# Prerequisites:
#   - Client certificate at /certs/client/client.crt
#   - Client private key at /certs/client/client.key
#   - CA root certificate at /certs/ca-root.crt
#   - curl CLI tool installed
#   - Network connectivity to target-server
#
# Exit Codes:
#   0 - Success (mTLS connection established, HTTP 200 OK)
#   1 - Failure (certificate missing, TLS error, or HTTP error)
#
################################################################################

set -euo pipefail

################################################################################
# Configuration Variables
################################################################################

readonly CERT_FILE="/certs/client/client.crt"
readonly KEY_FILE="/certs/client/client.key"
readonly CA_FILE="/certs/ca-root.crt"
readonly TARGET_URL="https://target-server/"
readonly TEMP_RESPONSE="/tmp/mtls-response-$$.txt"
readonly TEMP_STDERR="/tmp/mtls-stderr-$$.txt"

################################################################################
# Color Output Setup
################################################################################

# Color output for better readability (only if terminal supports it)
if [[ -t 2 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    NC=''
fi

################################################################################
# Logging Functions
################################################################################

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

################################################################################
# Error Handling
################################################################################

error_exit() {
    log_error "$1"
    cleanup
    exit 1
}

cleanup() {
    # Clean up temporary files
    rm -f "${TEMP_RESPONSE}" "${TEMP_STDERR}" 2>/dev/null || true
}

trap cleanup EXIT

################################################################################
# Certificate Validation
################################################################################

validate_certificates() {
    log_info "Validating certificate files..."

    if [[ ! -f "${CERT_FILE}" ]]; then
        error_exit "Client certificate not found at ${CERT_FILE}"
    fi

    if [[ ! -f "${KEY_FILE}" ]]; then
        error_exit "Client key not found at ${KEY_FILE}"
    fi

    if [[ ! -f "${CA_FILE}" ]]; then
        error_exit "CA root certificate not found at ${CA_FILE}"
    fi

    log_success "All certificate files found"
}

################################################################################
# mTLS Connection Test
################################################################################

test_mtls_connection() {
    log_info "Testing mTLS connection to target-server..."
    log_info "Certificate: ${CERT_FILE}"

    # Execute curl with mTLS configuration
    # -s: silent mode (no progress bar)
    # -S: show errors even in silent mode
    # -v: verbose (TLS handshake details)
    # --cert: client certificate
    # --key: client private key
    # --cacert: CA certificate for server validation
    # -w: write out HTTP status code
    # -o: output response body to file
    local http_code
    local curl_exit_code=0

    # Run curl and capture both output and errors
    http_code=$(curl -sSv \
        --cert "${CERT_FILE}" \
        --key "${KEY_FILE}" \
        --cacert "${CA_FILE}" \
        -w "%{http_code}" \
        -o "${TEMP_RESPONSE}" \
        "${TARGET_URL}" 2>"${TEMP_STDERR}") || curl_exit_code=$?

    # Check if curl command succeeded
    if [[ ${curl_exit_code} -ne 0 ]]; then
        log_error "TLS connection failed"

        # Extract and display relevant error information
        if [[ -f "${TEMP_STDERR}" ]]; then
            # Look for specific TLS errors
            if grep -qi "SSL certificate problem" "${TEMP_STDERR}"; then
                log_error "SSL certificate validation failed"
            elif grep -qi "SSL peer handshake failed" "${TEMP_STDERR}"; then
                log_error "TLS peer handshake failed"
            elif grep -qi "Could not resolve host" "${TEMP_STDERR}"; then
                log_error "Could not resolve host: target-server"
            fi

            # Show curl error output
            log_error "curl error details:"
            cat "${TEMP_STDERR}" >&2
        fi

        error_exit "Failed to establish mTLS connection (curl exit code: ${curl_exit_code})"
    fi

    # Verify TLS handshake was successful by checking stderr for handshake indicators
    if [[ -f "${TEMP_STDERR}" ]]; then
        if grep -qi "SSL connection using\|TLSv1\.\|Server certificate:" "${TEMP_STDERR}"; then
            log_success "TLS handshake successful"
        else
            log_error "TLS handshake verification failed - no handshake indicators found"
        fi
    fi

    # Validate HTTP status code
    if [[ "${http_code}" == "200" ]]; then
        log_success "HTTP 200 OK - mTLS connection established"

        # Display response body if available
        if [[ -f "${TEMP_RESPONSE}" ]] && [[ -s "${TEMP_RESPONSE}" ]]; then
            echo ""
            log_info "Response from target-server:"
            echo "----------------------------------------"
            cat "${TEMP_RESPONSE}"
            echo ""
            echo "----------------------------------------"
        fi

        return 0
    else
        log_error "HTTP error: Status code ${http_code}"

        # Show response body if available for debugging
        if [[ -f "${TEMP_RESPONSE}" ]] && [[ -s "${TEMP_RESPONSE}" ]]; then
            log_error "Response body:"
            cat "${TEMP_RESPONSE}" >&2
        fi

        error_exit "mTLS connection failed: HTTP ${http_code}"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    echo ""
    log_info "========================================="
    log_info "mTLS Connection Test"
    log_info "========================================="
    echo ""

    # Phase 1: Validate certificates exist
    validate_certificates
    echo ""

    # Phase 2: Test mTLS connection
    test_mtls_connection
    echo ""

    # Success
    log_info "========================================="
    log_success "mTLS test completed successfully"
    log_info "========================================="
    echo ""

    exit 0
}

################################################################################
# Script Entry Point
################################################################################

main "$@"
