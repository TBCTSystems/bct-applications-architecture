#!/usr/bin/env bash
################################################################################
# ECA PoC - Infrastructure Volume Initialization Script
#
# Purpose: Initialize ALL required Docker volumes for the ECA PoC project
#          - PKI (step-ca) Certificate Authority
#          - OpenXPKI EST server with shared trust chain
#
# This script handles the TTY requirements of step-ca initialization by running
# on the host where TTY is available, then sets up all dependent infrastructure.
#
# Prerequisites:
#   - step-ca CLI tools installed on host (https://smallstep.com/docs/step-ca/installation)
#   - Docker installed and running
#   - Sufficient permissions to create Docker volumes
#
# Usage:
#   ./init-volumes.sh
#
# Environment Variables:
#   ECA_CA_PASSWORD - Set CA password (default: eca-poc-default-password)
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

readonly VOLUME_PKI="pki-data"
readonly VOLUME_OPENXPKI_CONFIG="openxpki-config-data"
readonly TEMP_PKI_DIR="/tmp/eca-pki-init"
readonly CA_NAME="ECA-PoC-CA"
readonly CA_DNS="pki,localhost"
readonly CA_ADDRESS=":9000"
readonly CA_PROVISIONER="admin"
readonly DEFAULT_CA_PASSWORD="eca-poc-default-password"
readonly OPENXPKI_REALM="democa"
readonly OPENXPKI_CA_NAME="est-ca"

################################################################################
# Color Output
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_section() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
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
# PKI Initialization (step-ca)
################################################################################

initialize_pki() {
    log_section "Step 1: Initializing PKI (step-ca)"

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
    # Use printf to avoid adding newlines (important for empty passwords)
    mkdir -p "${TEMP_PKI_DIR}/secrets"
    printf '%s' "${CA_PASSWORD}" > "${TEMP_PKI_DIR}/secrets/password"
    chmod 600 "${TEMP_PKI_DIR}/secrets/password"

    log_info "Password saved to ${TEMP_PKI_DIR}/secrets/password"

    # Fix paths in configuration files to use container paths instead of host temp paths
    log_info "Fixing paths in configuration files for container environment..."
    sed -i "s|${TEMP_PKI_DIR}|/home/step|g" "${TEMP_PKI_DIR}/config/ca.json"
    sed -i "s|${TEMP_PKI_DIR}|/home/step|g" "${TEMP_PKI_DIR}/config/defaults.json"

    log_success "PKI CA initialized successfully"
}

create_pki_volume() {
    log_info "Creating PKI Docker volume: ${VOLUME_PKI}"

    # Check if volume already exists
    if docker volume inspect "${VOLUME_PKI}" &> /dev/null; then
        log_warn "Volume '${VOLUME_PKI}' already exists"
        read -p "Do you want to remove and recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Removing existing volume..."
            docker volume rm "${VOLUME_PKI}" || {
                log_error "Failed to remove volume. Is it in use?"
                log_error "Try: docker compose down"
                return 1
            }
        else
            log_info "Keeping existing volume"
            return 0
        fi
    fi

    # Create the volume
    docker volume create "${VOLUME_PKI}"
    log_success "PKI volume created successfully"
}

copy_pki_to_volume() {
    log_info "Copying initialized PKI data to Docker volume..."

    # Use a temporary container to copy files to the volume
    # This ensures correct permissions and ownership

    #files in TEMP_PKI_DIR not permissible to be copied from the container.
    # brute forced it to prove the fix.
    chmod -R 777 "${TEMP_PKI_DIR}"

    docker run --rm \
        -v "${VOLUME_PKI}:/home/step" \
        -v "${TEMP_PKI_DIR}:/source:ro" \
        smallstep/step-ca:latest \
        sh -c "cp -r /source/* /home/step/ && chown -R step:step /home/step"

    log_success "PKI data copied to volume"
}

start_pki_for_provisioning() {
    log_info "Starting PKI container temporarily to configure provisioners..."

    # Start just the PKI service
    docker compose up -d pki

    # Wait for PKI to be healthy
    log_info "Waiting for PKI to be ready..."
    for i in $(seq 1 30); do
        if docker compose ps pki | grep -q "healthy"; then
            log_success "PKI is healthy"
            return 0
        fi
        sleep 2
    done

    log_error "PKI failed to become healthy"
    return 1
}

wait_for_est_certificates() {
    log_info "Waiting for EST certificates to be generated..."

    for i in $(seq 1 30); do
        if docker run --rm -v pki-data:/pki:ro alpine test -f /pki/est-certs/est-ca.pem 2>/dev/null; then
            log_success "EST certificates found"
            return 0
        fi
        log_info "Attempt $i/30: EST certificates not ready yet..."
        sleep 2
    done

    log_error "EST certificates were not generated"
    return 1
}

################################################################################
# OpenXPKI Initialization
################################################################################

initialize_openxpki() {
    log_section "Step 2: Initializing OpenXPKI EST Server"

    # Create OpenXPKI config volume
    log_info "Creating OpenXPKI config volume: ${VOLUME_OPENXPKI_CONFIG}"

    if docker volume inspect "${VOLUME_OPENXPKI_CONFIG}" &> /dev/null; then
        log_warn "Volume '${VOLUME_OPENXPKI_CONFIG}' already exists - will reuse"
    else
        docker volume create "${VOLUME_OPENXPKI_CONFIG}"
        log_success "OpenXPKI config volume created"
    fi

    # Copy base OpenXPKI configuration
    log_info "Copying OpenXPKI base configuration..."
    docker run --rm \
        -v "${VOLUME_OPENXPKI_CONFIG}:/config" \
        -v "$(pwd)/est-server/openxpki-setup/openxpki-config:/source:ro" \
        alpine \
        sh -c "cp -r /source/* /config/"

    log_success "OpenXPKI base configuration copied"

    # Copy EST certificates from PKI volume to OpenXPKI volume
    log_info "Copying EST certificates to OpenXPKI..."
    docker run --rm \
        -v "${VOLUME_PKI}:/pki:ro" \
        -v "${VOLUME_OPENXPKI_CONFIG}:/config" \
        alpine \
        sh -c "
            mkdir -p /config/local/secrets && \
            cp /pki/est-certs/est-ca.pem /config/local/secrets/est-ca.crt && \
            cp /pki/est-certs/est-ca.key /config/local/secrets/est-ca.key && \
            cp /pki/certs/intermediate_ca.crt /config/local/secrets/step-intermediate.crt && \
            cp /pki/certs/root_ca.crt /config/local/secrets/root-ca.crt && \
            chmod 644 /config/local/secrets/*.crt && \
            chmod 600 /config/local/secrets/*.key
        "

    log_success "EST certificates copied to OpenXPKI"

    # Setup OpenXPKI CA directories
    log_info "Setting up OpenXPKI CA directories..."
    # UID/GID 100:102 map to openxpki:openxpki inside the OpenXPKI container
    docker run --rm \
        -v "${VOLUME_OPENXPKI_CONFIG}:/config" \
        alpine \
        sh -c "
            mkdir -p /config/local/keys/${OPENXPKI_REALM} && \
            mkdir -p /config/ca/${OPENXPKI_REALM} && \
            cp /config/local/secrets/est-ca.crt /config/ca/${OPENXPKI_REALM}/${OPENXPKI_CA_NAME}.crt && \
            chmod 644 /config/ca/${OPENXPKI_REALM}/${OPENXPKI_CA_NAME}.crt && \
            cp /config/local/secrets/est-ca.key /config/local/keys/${OPENXPKI_REALM}/${OPENXPKI_CA_NAME}.pem && \
            chmod 600 /config/local/keys/${OPENXPKI_REALM}/${OPENXPKI_CA_NAME}.pem && \
            chown -R 100:102 /config/local/keys/${OPENXPKI_REALM} && \
            cp /config/local/secrets/root-ca.crt /config/ca/${OPENXPKI_REALM}/root.crt && \
            chmod 644 /config/ca/${OPENXPKI_REALM}/root.crt
        "

    log_success "OpenXPKI CA directories configured"
}

provision_openxpki_web_tls() {
    log_info "Provisioning OpenXPKI web TLS materials..."

    docker exec -i eca-pki bash -c "
        set -euo pipefail
        mkdir -p /home/step/tmp
        STEPPATH=/home/step step ca certificate openxpki-web \
            /home/step/tmp/openxpki-web.crt \
            /home/step/tmp/openxpki-web.key \
            --provisioner ${CA_PROVISIONER} \
            --provisioner-password-file /home/step/secrets/password \
            --ca-url https://localhost:9000 \
            --root /home/step/certs/root_ca.crt \
            --san openxpki-web \
            --san localhost \
            --force
    "

    docker run --rm \
        -v "${VOLUME_PKI}:/pki:ro" \
        -v "${VOLUME_OPENXPKI_CONFIG}:/config" \
        alpine \
        sh -c "
            set -e
            mkdir -p /config/tls/private /config/tls/endentity /config/tls/chain && \
            cat /pki/tmp/openxpki-web.crt /pki/certs/intermediate_ca.crt > /config/tls/endentity/openxpki.crt && \
            cp /pki/tmp/openxpki-web.key /config/tls/private/openxpki.pem && \
            cp /pki/certs/intermediate_ca.crt /config/tls/chain/intermediate-ca.crt && \
            cp /pki/certs/root_ca.crt /config/tls/chain/root-ca.crt && \
            chmod 600 /config/tls/private/openxpki.pem && \
            chmod 644 /config/tls/endentity/openxpki.crt /config/tls/chain/root-ca.crt /config/tls/chain/intermediate-ca.crt
        "

    docker exec eca-pki rm -f /home/step/tmp/openxpki-web.crt /home/step/tmp/openxpki-web.key >/dev/null 2>&1 || true

    log_success "OpenXPKI web TLS certificate generated"
}

initialize_openxpki_database() {
    log_info "Initializing OpenXPKI database schema..."

    # Start OpenXPKI database
    log_info "Starting OpenXPKI database..."
    docker compose up -d openxpki-db

    # Wait for database to be healthy
    log_info "Waiting for database to be ready..."
    for i in $(seq 1 30); do
        if docker compose ps openxpki-db | grep -q "healthy"; then
            log_success "Database is healthy"
            break
        fi
        sleep 2
    done

    # Determine whether schema already exists (check for core table)
    if docker exec eca-openxpki-db mariadb -N -uopenxpki -popenxpki \
        -e "SHOW TABLES LIKE 'aliases'" openxpki | grep -q aliases; then
        log_info "Existing OpenXPKI schema detected – skipping import"
        return
    fi

    # Copy schema file and import it
    log_info "Importing database schema..."

    # Extract schema from a temporary container
    docker run --rm \
        -v "${VOLUME_OPENXPKI_CONFIG}:/config:ro" \
        alpine \
        cat /config/contrib/sql/schema-mariadb.sql > /tmp/openxpki-schema.sql

    # Import schema
    docker exec -i eca-openxpki-db mariadb -uopenxpki -popenxpki openxpki < /tmp/openxpki-schema.sql

    # Cleanup
    rm -f /tmp/openxpki-schema.sql

    log_success "OpenXPKI database schema initialized"
}

import_certificates_to_openxpki() {
    log_info "Importing certificates into OpenXPKI database..."

    # Start OpenXPKI server
    log_info "Starting OpenXPKI server..."
    docker compose up -d openxpki-server

    # Wait for server to be healthy
    log_info "Waiting for OpenXPKI server to be ready..."
    for i in $(seq 1 30); do
        if docker compose ps openxpki-server | grep -q "healthy"; then
            log_success "OpenXPKI server is healthy"
            break
        fi
        sleep 2
    done

    # Import root CA (without chain validation)
    log_info "Importing step-ca root CA certificate..."
    docker exec eca-openxpki-server openxpkiadm certificate import \
        --file /etc/openxpki/local/secrets/root-ca.crt \
        --realm ${OPENXPKI_REALM} \
        --force-no-chain

    # Import step-ca intermediate for bootstrap certificate chain
    log_info "Importing step-ca intermediate certificate..."
    docker exec eca-openxpki-server openxpkiadm certificate import \
        --file /etc/openxpki/local/secrets/step-intermediate.crt \
        --realm ${OPENXPKI_REALM}

    # Import EST CA and create ca-signer alias
    log_info "Importing EST CA certificate and creating ca-signer alias..."
    docker exec -u root eca-openxpki-server sh -c "cp /etc/openxpki/local/secrets/est-ca.key /tmp/est-ca.key && chown openxpki:openxpki /tmp/est-ca.key && chmod 600 /tmp/est-ca.key"
    docker exec eca-openxpki-server openxpkiadm alias \
        --realm ${OPENXPKI_REALM} \
        --token certsign \
        --file /etc/openxpki/local/secrets/est-ca.crt \
        --key /tmp/est-ca.key || {
        # If alias creation fails due to key permissions, copy key manually
        log_warn "Alias creation failed, copying key manually..."
        docker exec -u root eca-openxpki-server sh -c "cp /etc/openxpki/local/secrets/est-ca.key /etc/openxpki/local/keys/${OPENXPKI_REALM}/ca-signer-1.pem && chown openxpki:openxpki /etc/openxpki/local/keys/${OPENXPKI_REALM}/ca-signer-1.pem && chmod 600 /etc/openxpki/local/keys/${OPENXPKI_REALM}/ca-signer-1.pem"
    }
    docker exec eca-openxpki-server rm -f /tmp/est-ca.key >/dev/null 2>&1 || true

    # Generate long-lived bootstrap certificate
    log_info "Generating bootstrap certificate..."
    docker exec -i eca-pki bash -c "
        STEPPATH=/home/step step ca certificate bootstrap-client \
            /home/step/bootstrap-certs/bootstrap-client.pem \
            /home/step/bootstrap-certs/bootstrap-client.key \
            --provisioner admin \
            --provisioner-password-file /home/step/secrets/password \
            --ca-url https://localhost:9000 \
            --root /home/step/certs/root_ca.crt \
            --not-before 1m \
            --not-after 23h \
            --san bootstrap-client \
            --force
    "
    sleep 5

    # Import bootstrap certificate (extract first cert from chain)
    log_info "Importing bootstrap certificate..."
    docker exec eca-openxpki-server sh -c "
        sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p;/END CERTIFICATE/q' \
            /pki/bootstrap-certs/bootstrap-client.pem > /tmp/bootstrap-only.pem
    "
    docker exec eca-openxpki-server openxpkiadm certificate import \
        --file /tmp/bootstrap-only.pem \
        --realm ${OPENXPKI_REALM}

    docker exec eca-openxpki-server rm -f /tmp/bootstrap-only.pem >/dev/null 2>&1 || true

    log_success "Certificates imported into OpenXPKI database"
}

################################################################################
# Cleanup
################################################################################

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
    log_section "ECA PoC - Infrastructure Volume Initialization"

    # Run prerequisite checks
    if ! check_prerequisites; then
        exit 1
    fi

    echo ""
    log_info "This script will initialize:"
    log_info "  1. PKI (step-ca) Certificate Authority"
    log_info "  2. OpenXPKI EST server with shared trust chain"
    log_info "  3. All required Docker volumes"
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

    # Execute initialization steps
    initialize_pki
    create_pki_volume
    copy_pki_to_volume

    # Start PKI to trigger provisioner configuration and EST cert generation
    start_pki_for_provisioning
    wait_for_est_certificates

    # Now initialize OpenXPKI with the EST certificates
    initialize_openxpki
    provision_openxpki_web_tls
    initialize_openxpki_database
    import_certificates_to_openxpki

    cleanup

    log_section "🎉 Infrastructure Initialization Complete!"

    echo "Next steps:"
    printf "  1. Start all services:        %s docker compose up -d %s\n" "${GREEN}" "${NC}"
    printf "  2. Verify PKI health:         %s curl -k https://localhost:9000/health %s (expect {\"status\":\"ok\"})\n" "${GREEN}" "${NC}"
    printf "  3. Open OpenXPKI Web UI:      %s http://localhost:8080 %s  (or https://localhost:8443)\n" "${GREEN}" "${NC}"
    printf "  4. Open Grafana:              %s http://localhost:3000 %s  (admin/eca-admin)\n" "${GREEN}" "${NC}"
    printf "  5. Run automated checks:      %s ./scripts/run-tests.sh %s\n" "${GREEN}" "${NC}"
    echo ""
}

# Handle script interruption
trap 'log_error "Script interrupted"; cleanup; exit 1' INT TERM

# Run main function
main
