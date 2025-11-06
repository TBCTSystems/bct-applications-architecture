#!/usr/bin/env bash
################################################################################
# PKI Volume Pre-Initialization Script
#
# Purpose: Initialize the step-ca Certificate Authority on the host machine
#          and prepare it for Docker volume usage
#
# This script works around step-ca's interactive TTY requirements by running
# the initialization on the host where TTY is available, then copying the
# initialized PKI data into the Docker volume.
#
# Prerequisites:
#   - step-ca CLI tools installed on host (https://smallstep.com/docs/step-ca/installation)
#   - Docker installed and running
#   - Sufficient permissions to create Docker volumes
#
# Usage:
#   ./init-pki-volume.sh
#
# Exit Codes:
#   0 - Success
#   1 - Error (prerequisites not met or initialization failed)
#
################################################################################

set -euo pipefail

################################################################################
# Configuration
################################################################################

readonly VOLUME_NAME="pki-data"
readonly TEMP_PKI_DIR="/tmp/eca-pki-init"
readonly CA_NAME="ECA-PoC-CA"
readonly CA_DNS="pki,localhost"
readonly CA_ADDRESS=":9000"
readonly CA_PROVISIONER="admin"
readonly DEFAULT_CA_PASSWORD="eca-poc-default-password"
# Note: CA_PASSWORD can be set via ECA_CA_PASSWORD environment variable or will use default

################################################################################
# Color Output
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

################################################################################
# Prerequisite Checks
################################################################################

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if step CLI is installed
    if ! command -v step &> /dev/null; then
        log_error "step CLI not found. Please install it first:"
        log_error "  https://smallstep.com/docs/step-cli/installation"
        log_error ""
        log_error "Quick install (Linux):"
        log_error "  wget https://dl.smallstep.com/cli/docs-ca-install/latest/step-cli_amd64.deb"
        log_error "  sudo dpkg -i step-cli_amd64.deb"
        return 1
    fi

    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker first."
        return 1
    fi

    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker."
        return 1
    fi

    log_success "All prerequisites met"
    return 0
}

################################################################################
# Initialization Logic
################################################################################

initialize_ca() {
    log_info "Initializing Certificate Authority..."

    # Clean up any existing temp directory
    if [ -d "${TEMP_PKI_DIR}" ]; then
        log_warn "Removing existing temporary PKI directory"
        rm -rf "${TEMP_PKI_DIR}"
    fi

    # Create temporary directory for initialization
    mkdir -p "${TEMP_PKI_DIR}"

    # Use password from environment variable if set, otherwise use default
    if [ -n "${ECA_CA_PASSWORD:-}" ]; then
        CA_PASSWORD="${ECA_CA_PASSWORD}"
        log_info "Using CA password from ECA_CA_PASSWORD environment variable"
    elif [ -t 0 ]; then
        # Interactive mode: prompt for password
        echo ""
        log_info "You will be asked to set a password for the CA keys."
        log_info "IMPORTANT: Remember this password - you'll need it for the Docker container!"
        echo ""
        read -s -p "Enter password for CA keys (or press Enter for default: ${DEFAULT_CA_PASSWORD}): " USER_PASSWORD
        echo ""
        CA_PASSWORD="${USER_PASSWORD:-$DEFAULT_CA_PASSWORD}"
    else
        # Non-interactive mode: use default password
        CA_PASSWORD="${DEFAULT_CA_PASSWORD}"
        log_info "Non-interactive mode: using default CA password"
        log_warn "Default password: ${DEFAULT_CA_PASSWORD}"
        log_warn "Set ECA_CA_PASSWORD environment variable to use a custom password"
    fi

    # Initialize CA using step ca init
    log_info "Running 'step ca init'..."

    export STEPPATH="${TEMP_PKI_DIR}"

    # Create password files (use printf to avoid adding newlines)
    printf '%s' "${CA_PASSWORD}" > "${TEMP_PKI_DIR}/password.txt"
    printf '%s' "${CA_PASSWORD}" > "${TEMP_PKI_DIR}/provisioner_password.txt"

    step ca init \
        --name="${CA_NAME}" \
        --dns="${CA_DNS}" \
        --address="${CA_ADDRESS}" \
        --provisioner="${CA_PROVISIONER}" \
        --password-file="${TEMP_PKI_DIR}/password.txt" \
        --provisioner-password-file="${TEMP_PKI_DIR}/provisioner_password.txt"

    # Clean up temporary password files
    rm -f "${TEMP_PKI_DIR}/password.txt" "${TEMP_PKI_DIR}/provisioner_password.txt"

    # Create the password file that step-ca will use at runtime
    # This MUST contain the same password used during initialization
    # Use printf to avoid adding newlines (important for empty passwords)
    mkdir -p "${TEMP_PKI_DIR}/secrets"
    printf '%s' "${CA_PASSWORD}" > "${TEMP_PKI_DIR}/secrets/password"
    chmod 600 "${TEMP_PKI_DIR}/secrets/password"

    log_info "Password saved to ${TEMP_PKI_DIR}/secrets/password"

    # Fix paths in configuration files to use container paths instead of host temp paths
    log_info "Fixing paths in configuration files for container environment..."
    sed -i "s|${TEMP_PKI_DIR}|/home/step|g" "${TEMP_PKI_DIR}/config/ca.json"
    sed -i "s|${TEMP_PKI_DIR}|/home/step|g" "${TEMP_PKI_DIR}/config/defaults.json"

    log_success "CA initialized successfully"
}

configure_provisioners() {
    log_info "Provisioner configuration will be done after container starts"
    log_info "Run: docker exec eca-pki /usr/local/bin/configure-provisioners.sh"
}

note_est_certificate_generation() {
    log_info "EST server certificates will be generated after container starts"
    log_info "This will happen automatically when configure-provisioners.sh runs"
}

create_docker_volume() {
    log_info "Creating Docker volume: ${VOLUME_NAME}"

    # Check if volume already exists
    if docker volume inspect "${VOLUME_NAME}" &> /dev/null; then
        log_warn "Volume '${VOLUME_NAME}' already exists"
        read -p "Do you want to remove and recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Removing existing volume..."
            docker volume rm "${VOLUME_NAME}" || {
                log_error "Failed to remove volume. Is it in use?"
                log_error "Try: docker compose down -v"
                return 1
            }
        else
            log_info "Keeping existing volume"
            return 0
        fi
    fi

    # Create the volume
    docker volume create "${VOLUME_NAME}"
    log_success "Volume created successfully"
}

copy_to_volume() {
    log_info "Copying initialized PKI data to Docker volume..."

    # Use a temporary container to copy files to the volume
    # This ensures correct permissions and ownership
    docker run --rm \
        -v "${VOLUME_NAME}:/home/step" \
        -v "${TEMP_PKI_DIR}:/source:ro" \
        smallstep/step-ca:latest \
        sh -c "cp -r /source/* /home/step/ && chown -R step:step /home/step"

    log_success "PKI data copied to volume"
}

cleanup() {
    log_info "Cleaning up temporary files..."
    if [ -d "${TEMP_PKI_DIR}" ]; then
        rm -rf "${TEMP_PKI_DIR}"
    fi
    log_success "Cleanup complete"
}

################################################################################
# Main Execution
################################################################################

main() {
    echo ""
    echo "=========================================="
    echo "  ECA PoC - PKI Volume Initialization"
    echo "=========================================="
    echo ""

    # Run prerequisite checks
    if ! check_prerequisites; then
        exit 1
    fi

    echo ""
    log_info "This script will:"
    log_info "  1. Initialize a step-ca Certificate Authority on your host"
    log_info "  2. Create a Docker volume named '${VOLUME_NAME}'"
    log_info "  3. Copy the initialized PKI data to the volume"
    log_info "  4. Clean up temporary files"
    echo ""

    # Skip confirmation in non-interactive mode
    if [ -t 0 ]; then
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Aborted by user"
            exit 0
        fi
    else
        log_info "Non-interactive mode: proceeding automatically"
    fi

    echo ""

    # Execute initialization steps
    initialize_ca
    echo ""

    configure_provisioners
    echo ""

    note_est_certificate_generation
    echo ""

    create_docker_volume
    echo ""

    copy_to_volume
    echo ""

    cleanup
    echo ""

    log_success "PKI volume initialization complete!"
    echo ""
    echo "=========================================="
    echo "  Next Steps"
    echo "=========================================="
    echo ""
    echo "1. Start the PKI service:"
    echo "   ${GREEN}docker compose up -d pki${NC}"
    echo ""
    echo "2. Verify the CA is running:"
    echo "   ${GREEN}docker logs eca-pki${NC}"
    echo "   ${GREEN}curl -k https://localhost:9000/health${NC}"
    echo ""
    echo "3. Configure ACME and EST provisioners:"
    echo "   ${GREEN}docker exec eca-pki /usr/local/bin/configure-provisioners.sh${NC}"
    echo ""
    echo "4. Start the remaining services:"
    echo "   ${GREEN}docker compose up -d${NC}"
    echo ""
}

# Handle script interruption
trap 'log_error "Script interrupted"; cleanup; exit 1' INT TERM

# Run main function
main
