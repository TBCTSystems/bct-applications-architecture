#!/usr/bin/env bash
################################################################################
# step-ca Provisioner Configuration Script
#
# Purpose: Configure ACME and EST provisioners AFTER step-ca is running
#
# This script is executed after step-ca has started and passed health checks.
# It adds the required provisioners for the ECA PoC project.
#
# Prerequisites:
#   - step-ca service running and healthy
#   - CA already initialized via init-pki.sh
#
# Exit Codes:
#   0 - Success (provisioners configured)
#   1 - Configuration error
#
################################################################################

set -euo pipefail

################################################################################
# Configuration Variables
################################################################################

readonly STEP_BASE="/home/step"
readonly SECRETS_DIR="${STEP_BASE}/secrets"
readonly EST_TOKEN_FILE="${SECRETS_DIR}/est-bootstrap-token.txt"
readonly ROOT_CA_CERT="${STEP_BASE}/certs/root_ca.crt"

readonly ACME_PROVISIONER_NAME="acme"
readonly EST_PROVISIONER_NAME="est-provisioner"

readonly MAX_RETRIES=30
readonly RETRY_INTERVAL=2

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

error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

# Wait for step-ca to be healthy
wait_for_step_ca() {
    log_info "Waiting for step-ca to be ready..."

    local retry_count=0
    while [ $retry_count -lt $MAX_RETRIES ]; do
        if curl -k -f https://localhost:9000/health > /dev/null 2>&1; then
            log_success "step-ca is healthy and ready"
            return 0
        fi

        retry_count=$((retry_count + 1))
        log_info "Attempt $retry_count/$MAX_RETRIES: step-ca not ready yet, waiting ${RETRY_INTERVAL}s..."
        sleep $RETRY_INTERVAL
    done

    error_exit "step-ca failed to become healthy after $MAX_RETRIES attempts"
}

# Check if a provisioner already exists
provisioner_exists() {
    local provisioner_name="$1"
    step ca provisioner list 2>/dev/null | grep -q "\"name\".*:.*\"${provisioner_name}\"" || return 1
    return 0
}

resolve_password_file() {
    for candidate in "$@"; do
        if [ -f "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

certificate_valid_for_hours() {
    local cert_path="$1"
    local min_hours="$2"

    if [ ! -f "$cert_path" ]; then
        return 1
    fi

    local min_seconds=$(( min_hours * 3600 ))
    if openssl x509 -in "$cert_path" -checkend "$min_seconds" -noout >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

################################################################################
# Main Configuration Logic
################################################################################

main() {
    log_info "Starting step-ca provisioner configuration..."

    local ca_password_file

    ca_password_file="$(resolve_password_file "${SECRETS_DIR}/password" "${STEP_BASE}/password")" \
        || error_exit "CA password file not found in ${SECRETS_DIR}/password or ${STEP_BASE}/password"

    # -------------------------------------------------------------------------
    # Phase 1: Wait for step-ca Health
    # -------------------------------------------------------------------------

    wait_for_step_ca

    # -------------------------------------------------------------------------
    # Phase 2: ACME Provisioner Configuration
    # -------------------------------------------------------------------------

    log_info "Configuring ACME provisioner..."

    # Debug: check provisioner existence
    if step ca provisioner list 2>/dev/null | grep -q "\"name\".*:.*\"${ACME_PROVISIONER_NAME}\""; then
        log_skip "ACME provisioner '${ACME_PROVISIONER_NAME}' already exists"
    else
        # Add ACME provisioner with claims matching provisioners.json
        # Temporarily disable exit on error for this command
        set +e
        step ca provisioner add "${ACME_PROVISIONER_NAME}" \
            --type ACME \
            --challenge http-01 \
            --x509-min-dur 5m \
            --x509-max-dur 24h \
            --x509-default-dur 10m 2>&1 | grep -v "already exists"
        local result=$?
        set -e

        if [ $result -eq 0 ]; then
            log_success "ACME provisioner '${ACME_PROVISIONER_NAME}' added successfully"
        else
            # Check again if it exists (in case of race condition)
            if provisioner_exists "${ACME_PROVISIONER_NAME}"; then
                log_skip "ACME provisioner '${ACME_PROVISIONER_NAME}' already exists"
            else
                error_exit "Failed to add ACME provisioner"
            fi
        fi
    fi

    # -------------------------------------------------------------------------
    # Phase 5: Generate EST Server Certificates
    # -------------------------------------------------------------------------

    log_info "Generating certificates for EST server..."

    # Create EST certs directory
    mkdir -p "${STEP_BASE}/est-certs"

    local regenerate_est_ca=false
    local regenerate_est_tls=false
    local regenerate_bootstrap=false

    if certificate_valid_for_hours "${STEP_BASE}/est-certs/est-ca.pem" 87600; then
        log_skip "EST intermediate CA certificate still valid"
    else
        regenerate_est_ca=true
    fi

    if certificate_valid_for_hours "${STEP_BASE}/est-certs/est-tls.pem" 6; then
        log_skip "EST TLS certificate still within validity window"
    else
        regenerate_est_tls=true
    fi

    if certificate_valid_for_hours "${STEP_BASE}/bootstrap-certs/bootstrap-client.pem" 24; then
        log_skip "Bootstrap certificate still within validity window"
    else
        regenerate_bootstrap=true
    fi

    if [ "$regenerate_est_ca" = true ]; then
        rm -f "${STEP_BASE}/est-certs/est-ca.pem" "${STEP_BASE}/est-certs/est-ca.key"
        rm -f "${STEP_BASE}/est-certs/est-ca.key.pkcs8"
    fi

    if [ "$regenerate_est_tls" = true ]; then
        rm -f "${STEP_BASE}/est-certs/est-tls.pem" "${STEP_BASE}/est-certs/est-tls.key"
    fi

    if [ "$regenerate_est_ca" = true ] || [ "$regenerate_est_tls" = true ]; then
        # Create empty password file for output certificates (unencrypted for PoC)
        touch "${SECRETS_DIR}/cert-password"
        chmod 600 "${SECRETS_DIR}/cert-password"
    fi

    if [ "$regenerate_est_ca" = true ]; then
        # Generate intermediate CA for EST server using offline certificate creation
        # This creates a proper CA certificate (not a leaf) that can sign client certs
        # Set validity to 10 years to allow issuing certificates throughout the CA's lifetime
        log_info "Generating EST intermediate CA certificate..."
        step certificate create "EST Intermediate CA" \
            "${STEP_BASE}/est-certs/est-ca.pem" \
            "${STEP_BASE}/est-certs/est-ca.key" \
            --profile intermediate-ca \
            --ca "${STEP_BASE}/certs/root_ca.crt" \
            --ca-key "${STEP_BASE}/secrets/root_ca_key" \
            --ca-password-file "${ca_password_file}" \
            --password-file "${SECRETS_DIR}/cert-password" \
            --not-after 87600h \
            --force \
            || error_exit "Failed to generate EST intermediate CA certificate"

        # Convert key from PKCS#1 to PKCS#8 format (required by foundries.io EST server)
        log_info "Converting EST CA key to PKCS#8 format..."
        openssl pkcs8 -topk8 -nocrypt \
            -in "${STEP_BASE}/est-certs/est-ca.key" \
            -out "${STEP_BASE}/est-certs/est-ca.key.pkcs8" \
            || error_exit "Failed to convert key to PKCS#8"
        mv "${STEP_BASE}/est-certs/est-ca.key.pkcs8" "${STEP_BASE}/est-certs/est-ca.key"
        chmod 600 "${STEP_BASE}/est-certs/est-ca.key"
    fi

    if [ "$regenerate_est_tls" = true ]; then
        # Generate TLS certificate for EST server (24h max for admin provisioner)
        log_info "Generating EST server TLS certificate..."
        step ca certificate "est-server" \
            "${STEP_BASE}/est-certs/est-tls.pem" \
            "${STEP_BASE}/est-certs/est-tls.key" \
            --provisioner admin \
            --provisioner-password-file "${ca_password_file}" \
            --password-file "${SECRETS_DIR}/cert-password" \
            --san est-server \
            --san localhost \
            --not-after 24h \
            --force \
            || error_exit "Failed to generate EST server TLS certificate"
    fi

    if [ "$regenerate_est_ca" = true ] || [ "$regenerate_est_tls" = true ]; then
        # Clean up temp password file
        rm -f "${SECRETS_DIR}/cert-password"

        chmod 600 "${STEP_BASE}/est-certs/"*.key
        log_success "EST server certificates generated/updated"
    fi

    # -------------------------------------------------------------------------
    # Phase 6: Generate Bootstrap Certificate for EST Agent Initial Enrollment
    # -------------------------------------------------------------------------

    log_info "Generating bootstrap certificate for EST agent..."

    # Create bootstrap certs directory
    mkdir -p "${STEP_BASE}/bootstrap-certs"

    if [ "$regenerate_bootstrap" = true ]; then
        rm -f "${STEP_BASE}/bootstrap-certs/bootstrap-client.pem" "${STEP_BASE}/bootstrap-certs/bootstrap-client.key"
        # Create empty password file for output certificates (unencrypted for PoC)
        touch "${SECRETS_DIR}/cert-password"
        chmod 600 "${SECRETS_DIR}/cert-password"

        # Generate bootstrap client certificate using the EST intermediate CA
        # This is a short-lived certificate (1 hour) that the EST agent will use for initial enrollment
        # Real-world: This would be a factory-provisioned certificate
        log_info "Generating bootstrap client certificate (1-hour validity)..."

        # Create temporary CSR for bootstrap certificate
        step certificate create "bootstrap-client" \
            "${STEP_BASE}/bootstrap-certs/bootstrap-client.pem" \
            "${STEP_BASE}/bootstrap-certs/bootstrap-client.key" \
            --profile leaf \
            --ca "${STEP_BASE}/est-certs/est-ca.pem" \
            --ca-key "${STEP_BASE}/est-certs/est-ca.key" \
            --ca-password-file "${SECRETS_DIR}/cert-password" \
            --password-file "${SECRETS_DIR}/cert-password" \
            --not-after 168h \
            --san bootstrap-client \
            --san eca-est-agent \
            --force \
            || error_exit "Failed to generate bootstrap client certificate"

        # Clean up temp password file
        rm -f "${SECRETS_DIR}/cert-password"

        chmod 644 "${STEP_BASE}/bootstrap-certs/bootstrap-client.pem"
        chmod 600 "${STEP_BASE}/bootstrap-certs/bootstrap-client.key"
        log_success "Bootstrap client certificate generated"
    else
        log_skip "Bootstrap certificate still valid"
    fi

    # -------------------------------------------------------------------------
    # Phase 7: Final Verification
    # -------------------------------------------------------------------------

    log_info "Verifying provisioner configuration..."

    echo ""
    echo "========================================================================"
    log_success "Provisioner configuration completed successfully"
    echo ""
    echo "Configured Provisioners:"
    step ca provisioner list | grep -E "(name|type)" | head -n 10 || echo "  (unable to list provisioners)"
    echo ""
    echo "EST Token File: ${EST_TOKEN_FILE}"
    echo "========================================================================"
}

################################################################################
# Script Entry Point
################################################################################

main "$@"
