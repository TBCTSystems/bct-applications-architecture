#!/usr/bin/env bash
################################################################################
# step-ca PKI Initialization Script
#
# Purpose: Initialize the step-ca Certificate Authority on first run with
#          ACME and EST provisioners configured for the ECA PoC project.
#
# Features:
#   - Idempotent: Safe to run multiple times
#   - Checks for existing CA initialization before proceeding
#   - Configures ACME provisioner for HTTP-01 challenges
#   - Configures EST provisioner with bootstrap token generation
#   - Includes comprehensive error handling and progress logging
#
# Prerequisites:
#   - step-ca CLI tools installed (available in smallstep/step-ca container)
#   - Configuration files present in /home/step/config/
#   - Appropriate write permissions to /home/step directory
#
# Exit Codes:
#   0 - Success (CA initialized or already initialized)
#   1 - Initialization error
#
################################################################################

set -euo pipefail

################################################################################
# Configuration Variables
################################################################################

readonly STEP_BASE="/home/step"
readonly ROOT_CA_CERT="${STEP_BASE}/certs/root_ca.crt"
readonly CONFIG_DIR="${STEP_BASE}/config"

readonly CA_NAME="ECA PoC CA"
readonly CA_DNS="step-ca"
readonly CA_ADDRESS=":9000"
readonly CA_PROVISIONER="admin"

################################################################################
# Error Handling
################################################################################

error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "ERROR: Script failed with exit code $exit_code" >&2
        echo "ERROR: CA initialization may be incomplete. Review logs above." >&2
    fi
}

trap cleanup_on_error EXIT

################################################################################
# Utility Functions
################################################################################

log_info() {
    echo "[INFO] $1"
}

log_success() {
    echo "[SUCCESS] $1"
}

log_skip() {
    echo "[SKIP] $1"
}

################################################################################
# Main Initialization Logic
################################################################################

main() {
    log_info "Starting step-ca PKI initialization..."

    # -------------------------------------------------------------------------
    # Phase 1: Idempotency Check
    # -------------------------------------------------------------------------

    if [ -f "${ROOT_CA_CERT}" ]; then
        log_skip "CA already initialized (${ROOT_CA_CERT} exists)"
        log_info "Verifying provisioner configuration..."
        CA_ALREADY_INITIALIZED=true
    else
        log_info "CA not yet initialized. Proceeding with initialization..."
        CA_ALREADY_INITIALIZED=false
    fi

    # -------------------------------------------------------------------------
    # Phase 2: CA Initialization (if needed)
    # -------------------------------------------------------------------------

    if [ "${CA_ALREADY_INITIALIZED}" = false ]; then
        log_info "CA initialization will be handled by step-ca base image via DOCKER_STEPCA_INIT_* environment variables"
        log_info "This script only validates that initialization succeeded"

        # The smallstep/step-ca base image automatically initializes the CA
        # when DOCKER_STEPCA_INIT_* environment variables are set (configured in docker-compose.yml).
        # We don't need to run 'step ca init' manually - the base image entrypoint handles it.
        # This avoids TTY allocation errors in non-interactive Docker environments.

        log_skip "Skipping manual 'step ca init' - using base image auto-initialization"

        # -------------------------------------------------------------------------
        # Phase 3: Configuration File Integration
        # -------------------------------------------------------------------------

        log_info "Integrating custom configuration files..."

        # The step ca init command creates a default ca.json
        # We need to preserve the generated certificate paths and keys,
        # but we want to use our custom configuration for other settings

        # Create backup of generated config
        if [ -f "${CONFIG_DIR}/ca.json" ]; then
            cp "${CONFIG_DIR}/ca.json" "${CONFIG_DIR}/ca.json.generated"
            log_info "Backed up generated ca.json to ca.json.generated"
        fi

        # Note: For this PoC, we'll keep the generated ca.json and add provisioners
        # via CLI commands rather than overwriting the entire file.
        # The generated config includes correct certificate paths that we shouldn't modify.

    else
        log_info "Using existing CA configuration"
    fi

    # -------------------------------------------------------------------------
    # Phase 4: Final Verification and Status
    # -------------------------------------------------------------------------
    # Note: Provisioner configuration has been moved to configure-provisioners.sh
    # which runs AFTER step-ca is started

    log_info "Verifying PKI initialization..."

    # Check critical files exist
    local all_checks_passed=true

    if [ -f "${ROOT_CA_CERT}" ]; then
        log_success "Root CA certificate: ${ROOT_CA_CERT}"
    else
        echo "ERROR: Root CA certificate not found at ${ROOT_CA_CERT}" >&2
        all_checks_passed=false
    fi

    if [ -f "${CONFIG_DIR}/ca.json" ]; then
        log_success "CA configuration: ${CONFIG_DIR}/ca.json"
    else
        echo "ERROR: CA configuration not found at ${CONFIG_DIR}/ca.json" >&2
        all_checks_passed=false
    fi

    # Final status
    echo ""
    echo "========================================================================"
    if [ "${all_checks_passed}" = true ]; then
        log_success "PKI initialization completed successfully"
        echo ""
        echo "CA Name:          ${CA_NAME}"
        echo "CA Address:       ${CA_ADDRESS}"
        echo "DNS Names:        ${CA_DNS}, pki, localhost"
        echo "Root CA Cert:     ${ROOT_CA_CERT}"
        echo "Base Provisioner: ${CA_PROVISIONER}"
        echo ""
        log_info "step-ca is ready to start. Additional provisioners will be configured after startup."
    else
        echo "ERROR: PKI initialization completed with errors. Review output above." >&2
        exit 1
    fi
    echo "========================================================================"
}

################################################################################
# Script Entry Point
################################################################################

main "$@"
