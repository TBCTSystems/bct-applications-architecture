#!/usr/bin/env bash
################################################################################
# ECA PoC System Bootstrap Script
#
# Purpose: Initialize and validate the complete ECA PoC system including:
#          - Docker environment validation
#          - EST bootstrap token generation
#          - Docker Compose service orchestration
#          - PKI health validation
#          - Root CA certificate extraction
#          - Provisioner configuration verification
#
# Features:
#   - Idempotent: Safe to run multiple times
#   - Comprehensive pre-flight checks
#   - Health check waiting with timeout
#   - Colored output for readability
#   - Detailed usage instructions on completion
#
# Prerequisites:
#   - Docker Engine 20.10+
#   - Docker Compose v1 or v2
#   - openssl (for token generation)
#   - curl (for health checks)
#
# Exit Codes:
#   0 - Success
#   1 - Initialization error
#
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

################################################################################
# Configuration Variables
################################################################################

# SC2155: Declare and assign separately to avoid masking return values
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT_ROOT
readonly ENV_FILE="${PROJECT_ROOT}/.env"
readonly ENV_EXAMPLE="${PROJECT_ROOT}/.env.example"
readonly ROOT_CA_OUTPUT="${PROJECT_ROOT}/pki/secrets/root_ca.crt"
readonly SECRETS_DIR="${PROJECT_ROOT}/pki/secrets"

readonly HEALTH_CHECK_TIMEOUT=120  # seconds
readonly HEALTH_CHECK_INTERVAL=5   # seconds

readonly ACME_PROVISIONER_NAME="acme"
readonly EST_PROVISIONER_NAME="est-provisioner"

################################################################################
# Color Output Configuration
################################################################################

# Only use colors if terminal supports it
if [[ -t 2 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    # shellcheck disable=SC2034  # BLUE reserved for future use
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    # shellcheck disable=SC2034  # BLUE reserved for future use
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

################################################################################
# Logging Functions
################################################################################

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $*" >&2
}

################################################################################
# Error Handling
################################################################################

error_exit() {
    log_error "$1"
    exit 1
}

################################################################################
# Pre-flight Checks
################################################################################

check_prerequisites() {
    log_step "Checking prerequisites..."

    # Check for Docker
    if ! command -v docker &> /dev/null; then
        error_exit "Docker is not installed. Please install Docker Engine 20.10+ from https://docs.docker.com/engine/install/"
    fi
    log_info "Docker found: $(docker --version)"

    # Check for Docker Compose (v1 or v2)
    local compose_cmd=""
    if command -v docker-compose &> /dev/null; then
        compose_cmd="docker-compose"
        log_info "Docker Compose v1 found: $(docker-compose --version)"
    elif docker compose version &> /dev/null 2>&1; then
        compose_cmd="docker compose"
        log_info "Docker Compose v2 found: $(docker compose version)"
    else
        error_exit "Docker Compose is not installed. Please install Docker Compose v1 or v2 from https://docs.docker.com/compose/install/"
    fi

    # Export the compose command for use in other functions
    COMPOSE_CMD="$compose_cmd"

    # Check for openssl (needed for token generation)
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is not installed. Required for generating cryptographic tokens."
    fi

    # Check for curl (needed for health checks)
    if ! command -v curl &> /dev/null; then
        error_exit "curl is not installed. Required for PKI health checks."
    fi

    log_success "All prerequisites satisfied"
}

################################################################################
# Environment Configuration
################################################################################

setup_environment() {
    log_step "Setting up environment configuration..."

    cd "${PROJECT_ROOT}" || error_exit "Failed to change to project root directory"

    # Check if .env file exists
    if [[ -f "${ENV_FILE}" ]]; then
        log_info ".env file already exists"

        # Check if EST_BOOTSTRAP_TOKEN is set to placeholder value
        if grep -q "EST_BOOTSTRAP_TOKEN=your-token-here" "${ENV_FILE}"; then
            log_warn "EST_BOOTSTRAP_TOKEN is set to placeholder value"
            log_info "Generating new cryptographically secure token..."

            # Generate new token
            local new_token
            new_token=$(openssl rand -base64 32)

            # Replace placeholder with new token
            sed -i.bak "s|EST_BOOTSTRAP_TOKEN=your-token-here|EST_BOOTSTRAP_TOKEN=${new_token}|g" "${ENV_FILE}"

            log_success "EST_BOOTSTRAP_TOKEN updated with new secure token"
        else
            log_info "EST_BOOTSTRAP_TOKEN appears to be configured"
        fi
    else
        log_info ".env file not found, creating from .env.example"

        if [[ ! -f "${ENV_EXAMPLE}" ]]; then
            error_exit ".env.example not found at ${ENV_EXAMPLE}"
        fi

        # Copy .env.example to .env
        cp "${ENV_EXAMPLE}" "${ENV_FILE}"
        log_info ".env file created from template"

        # Generate cryptographically secure token
        log_info "Generating cryptographically secure EST bootstrap token..."
        local new_token
        new_token=$(openssl rand -base64 32)

        # Replace placeholder token with generated token
        sed -i.bak "s|EST_BOOTSTRAP_TOKEN=your-token-here|EST_BOOTSTRAP_TOKEN=${new_token}|g" "${ENV_FILE}"

        log_success "EST_BOOTSTRAP_TOKEN generated and configured"
        log_info "Token: ${new_token}"
    fi

    # Ensure secrets directory exists
    mkdir -p "${SECRETS_DIR}"

    log_success "Environment configuration complete"
}

################################################################################
# Docker Compose Operations
################################################################################

start_services() {
    log_step "Starting Docker Compose services..."

    cd "${PROJECT_ROOT}" || error_exit "Failed to change to project root directory"

    # Start services in detached mode
    log_info "Running: ${COMPOSE_CMD} up -d"
    if ${COMPOSE_CMD} up -d; then
        log_success "Docker Compose services started"
    else
        error_exit "Failed to start Docker Compose services"
    fi
}

wait_for_pki_health() {
    log_step "Waiting for PKI service to become healthy..."

    local elapsed=0
    local health_check_passed=false

    while [ $elapsed -lt $HEALTH_CHECK_TIMEOUT ]; do
        log_info "Health check attempt (${elapsed}s/${HEALTH_CHECK_TIMEOUT}s)..."

        # Try to execute health check inside container
        if docker exec eca-pki curl -k -f -s https://localhost:9000/health > /dev/null 2>&1; then
            health_check_passed=true
            break
        fi

        sleep $HEALTH_CHECK_INTERVAL
        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
    done

    if [ "$health_check_passed" = true ]; then
        log_success "PKI service is healthy"
    else
        error_exit "PKI service health check timeout after ${HEALTH_CHECK_TIMEOUT} seconds"
    fi
}

################################################################################
# PKI Configuration
################################################################################

extract_root_ca() {
    log_step "Extracting root CA certificate..."

    # Execute step ca root command inside container and save output
    if docker exec eca-pki step ca root > "${ROOT_CA_OUTPUT}" 2>/dev/null; then
        log_success "Root CA certificate saved to ${ROOT_CA_OUTPUT}"

        # Display certificate info
        log_info "Root CA certificate details:"
        openssl x509 -in "${ROOT_CA_OUTPUT}" -noout -subject -issuer -dates 2>/dev/null || true
    else
        error_exit "Failed to extract root CA certificate from PKI container"
    fi
}

verify_provisioners() {
    log_step "Verifying provisioner configuration..."

    # Get provisioner list
    local provisioner_list
    if ! provisioner_list=$(docker exec eca-pki step ca provisioner list 2>/dev/null); then
        error_exit "Failed to retrieve provisioner list from PKI"
    fi

    # Check for ACME provisioner
    if echo "$provisioner_list" | grep -q "\"name\":\"${ACME_PROVISIONER_NAME}\""; then
        log_success "ACME provisioner '${ACME_PROVISIONER_NAME}' is configured"
    else
        log_warn "ACME provisioner '${ACME_PROVISIONER_NAME}' not found"
        log_info "This provisioner should be created by the PKI initialization script"
    fi

    # Check for EST provisioner
    if echo "$provisioner_list" | grep -q "\"name\":\"${EST_PROVISIONER_NAME}\""; then
        log_success "EST provisioner '${EST_PROVISIONER_NAME}' is configured"
    else
        log_warn "EST provisioner '${EST_PROVISIONER_NAME}' not found"
        log_info "This provisioner should be created by the PKI initialization script"
    fi
}

################################################################################
# Status Display
################################################################################

display_service_status() {
    log_step "Displaying service status..."

    cd "${PROJECT_ROOT}" || error_exit "Failed to change to project root directory"

    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}Docker Compose Service Status${NC}"
    echo -e "${BOLD}========================================${NC}"
    ${COMPOSE_CMD} ps
    echo ""
}

display_completion_instructions() {
    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${GREEN}${BOLD}System Ready! Next Steps:${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""
    echo -e "${BOLD}Test HTTPS Access:${NC}"
    echo "  curl -k https://localhost:443"
    echo ""
    echo -e "${BOLD}Test mTLS Connection:${NC}"
    echo "  docker exec eca-target-client /usr/local/bin/test-mtls.sh"
    echo ""
    echo -e "${BOLD}View ACME Agent Logs:${NC}"
    echo "  ${COMPOSE_CMD} logs -f eca-acme-agent"
    echo ""
    echo -e "${BOLD}View EST Agent Logs:${NC}"
    echo "  ${COMPOSE_CMD} logs -f eca-est-agent"
    echo ""
    echo -e "${BOLD}View All Logs:${NC}"
    echo "  ${COMPOSE_CMD} logs -f"
    echo ""
    echo -e "${BOLD}View PKI Service Logs:${NC}"
    echo "  ${COMPOSE_CMD} logs -f pki"
    echo ""
    echo -e "${BOLD}Stop System:${NC}"
    echo "  ${COMPOSE_CMD} down"
    echo ""
    echo -e "${BOLD}Root CA Certificate:${NC}"
    echo "  ${ROOT_CA_OUTPUT}"
    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo ""
}

################################################################################
# Main Execution
################################################################################

main() {
    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}ECA PoC System Bootstrap${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""

    # Phase 1: Pre-flight checks
    check_prerequisites

    # Phase 2: Environment setup
    setup_environment

    # Phase 3: Start Docker Compose services
    start_services

    # Phase 4: Wait for PKI health check
    wait_for_pki_health

    # Phase 5: Extract root CA certificate
    extract_root_ca

    # Phase 6: Verify provisioners
    verify_provisioners

    # Phase 7: Display service status
    display_service_status

    # Phase 8: Display completion instructions
    display_completion_instructions

    log_success "Bootstrap completed successfully!"
}

################################################################################
# Script Entry Point
################################################################################

main "$@"
