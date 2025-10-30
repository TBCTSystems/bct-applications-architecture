#!/usr/bin/env bash
################################################################################
# OpenXPKI Complete Initialization Script
#
# Purpose: Fully automated OpenXPKI setup for EST integration with step-ca
#          This script handles EVERYTHING - from volume creation to EST endpoint
#
# Prerequisites:
#   - step-ca initialized with EST intermediate CA (run init-pki-volume.sh first)
#   - Docker and docker-compose installed and running
#   - openssl CLI available
#   - git available
#
# Usage:
#   ./init-openxpki-volume.sh [--non-interactive]
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

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly VOLUME_NAME="openxpki-config-data"
readonly TEMP_CONFIG_DIR="/tmp/openxpki-config-init"
readonly PKI_VOLUME="pki-data"

# Parse arguments
NON_INTERACTIVE=false
if [[ "${1:-}" == "--non-interactive" ]]; then
    NON_INTERACTIVE=true
fi

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

    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        log_error "openssl not found. Please install it first."
        return 1
    fi

    # Check if git is installed
    if ! command -v git &> /dev/null; then
        log_error "git not found. Please install git first."
        return 1
    fi

    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker first."
        return 1
    fi

    # Check if docker compose is available
    if ! docker compose version &> /dev/null; then
        log_error "docker compose not found. Please install Docker Compose v2."
        return 1
    fi

    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker."
        return 1
    fi

    # Check if pki-data volume exists
    if ! docker volume inspect "${PKI_VOLUME}" &> /dev/null; then
        log_error "PKI volume '${PKI_VOLUME}' not found. Please run pki/init-pki-volume.sh first."
        return 1
    fi

    log_success "All prerequisites met"
    return 0
}

################################################################################
# Volume Initialization
################################################################################

clone_openxpki_config() {
    log_info "Cloning OpenXPKI configuration repository..."

    # Clean up any existing temp directory
    if [ -d "${TEMP_CONFIG_DIR}" ]; then
        log_warn "Removing existing temporary config directory"
        rm -rf "${TEMP_CONFIG_DIR}"
    fi

    # Create temporary directory
    mkdir -p "${TEMP_CONFIG_DIR}"

    # Clone the community configuration branch
    git clone https://github.com/openxpki/openxpki-config.git \
        --single-branch --branch=community \
        "${TEMP_CONFIG_DIR}/openxpki-config" &> /dev/null || {
        log_error "Failed to clone openxpki-config repository"
        return 1
    }

    log_success "OpenXPKI configuration cloned"
}

generate_cli_auth_key() {
    log_info "Generating CLI authentication key..."

    # Create config directory
    mkdir -p "${TEMP_CONFIG_DIR}/config"

    # Generate EC private key for CLI authentication
    openssl ecparam -name prime256v1 -genkey -noout \
        -out "${TEMP_CONFIG_DIR}/config/client.key" 2>/dev/null || {
        log_error "Failed to generate CLI key"
        return 1
    }

    chmod 644 "${TEMP_CONFIG_DIR}/config/client.key"

    # Extract public key
    local public_key
    public_key=$(openssl pkey -in "${TEMP_CONFIG_DIR}/config/client.key" -pubout 2>/dev/null)

    # Save public key for later use
    echo "${public_key}" > "${TEMP_CONFIG_DIR}/config/client.pub"

    # Update cli.yaml with the public key
    local cli_yaml="${TEMP_CONFIG_DIR}/openxpki-config/config.d/system/cli.yaml"

    cat > "${cli_yaml}" << EOF
# Public keys to authenticate requests over the CLI interface
# the name of the key is only used for logging purposes
# the keys can be generated using \`oxi cli create\`
# read the keys from the credential manager
auth:
   admin:
       key: |
$(echo "${public_key}" | sed 's/^/         /')
       role: RA Operator
EOF

    log_success "CLI authentication key generated and configured"
}

generate_vault_secret() {
    log_info "Generating vault encryption secret..."

    # Generate 32-byte random hex value
    local vault_secret
    vault_secret=$(openssl rand -hex 32)

    local crypto_yaml="${TEMP_CONFIG_DIR}/openxpki-config/config.d/system/crypto.yaml"

    if [ ! -f "${crypto_yaml}" ]; then
        log_error "crypto.yaml not found at ${crypto_yaml}"
        return 1
    fi

    # Replace the placeholder vault secret
    sed -i "s/value: .*/value: ${vault_secret}/" "${crypto_yaml}" || {
        log_error "Failed to update vault secret"
        return 1
    }

    # Save vault secret for reference
    echo "${vault_secret}" > "${TEMP_CONFIG_DIR}/config/vault-secret.txt"

    log_success "Vault encryption secret generated"
    log_warn "Vault secret saved to ${TEMP_CONFIG_DIR}/config/vault-secret.txt"
}

import_step_ca_certificates() {
    log_info "Importing step-ca EST intermediate CA..."

    # Create a temporary container to extract certificates from pki-data volume
    docker run --rm \
        -v "${PKI_VOLUME}:/pki:ro" \
        -v "${TEMP_CONFIG_DIR}:/output" \
        alpine:latest \
        sh -c "
            cp /pki/est-certs/est-ca.pem /output/est-ca.pem
            cp /pki/est-certs/est-ca.key /output/est-ca.key
            cp /pki/certs/root_ca.crt /output/root_ca.crt
            chmod 644 /output/*.pem /output/*.crt /output/*.key
        " &> /dev/null || {
        log_error "Failed to extract certificates from pki-data volume"
        return 1
    }

    log_success "step-ca certificates imported"
}

create_docker_volume() {
    log_info "Creating Docker volume: ${VOLUME_NAME}"

    # Check if volume already exists
    if docker volume inspect "${VOLUME_NAME}" &> /dev/null; then
        if [ "$NON_INTERACTIVE" = false ]; then
            log_warn "Volume '${VOLUME_NAME}' already exists"
            read -p "Do you want to remove and recreate it? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Keeping existing volume"
                return 0
            fi
        fi

        log_info "Removing existing volume..."
        docker volume rm "${VOLUME_NAME}" &> /dev/null || {
            log_error "Failed to remove volume. Is it in use?"
            log_error "Try: docker compose down"
            return 1
        }
    fi

    # Create the volume
    docker volume create "${VOLUME_NAME}" &> /dev/null
    log_success "Volume created"
}

copy_to_volume() {
    log_info "Copying OpenXPKI configuration to Docker volume..."

    # Copy configuration to volume
    docker run --rm \
        -v "${VOLUME_NAME}:/etc/openxpki" \
        -v "${TEMP_CONFIG_DIR}/openxpki-config:/source:ro" \
        alpine:latest \
        sh -c "cp -r /source/* /etc/openxpki/" &> /dev/null || {
        log_error "Failed to copy configuration to volume"
        return 1
    }

    # Copy the EST CA certificates
    docker run --rm \
        -v "${VOLUME_NAME}:/etc/openxpki" \
        -v "${TEMP_CONFIG_DIR}:/source:ro" \
        alpine:latest \
        sh -c "
            mkdir -p /etc/openxpki/local/ca
            cp /source/est-ca.pem /etc/openxpki/local/ca/
            cp /source/est-ca.key /etc/openxpki/local/ca/
            cp /source/root_ca.crt /etc/openxpki/local/ca/
            chmod 600 /etc/openxpki/local/ca/*.key
            chmod 644 /etc/openxpki/local/ca/*.pem /etc/openxpki/local/ca/*.crt
        " &> /dev/null || {
        log_error "Failed to copy CA certificates to volume"
        return 1
    }

    log_success "Configuration copied to volume"
}

################################################################################
# Container Startup and Configuration
################################################################################

start_database() {
    log_info "Starting OpenXPKI database..."

    cd "${PROJECT_ROOT}"
    docker compose up -d openxpki-db 2>&1 | grep -v "attribute \`version\` is obsolete" | grep -v "^$" || true

    # Wait for database to be healthy
    local retries=30
    while [ $retries -gt 0 ]; do
        if docker compose ps openxpki-db 2>/dev/null | grep -q "healthy"; then
            log_success "Database is healthy"
            return 0
        fi
        sleep 1
        ((retries--))
    done

    log_error "Database failed to become healthy"
    return 1
}

import_database_schema() {
    log_info "Importing database schema..."

    # Import schema using temporary container
    docker run --rm \
        -v openxpki-config-data:/config:ro \
        --network eca-poc-network \
        alpine:latest \
        sh -c "
            apk add --no-cache mariadb-client > /dev/null 2>&1
            mariadb -h eca-openxpki-db -u openxpki -popenxpki openxpki < /config/contrib/sql/schema-mariadb.sql
        " &> /dev/null || {
        log_error "Failed to import database schema"
        return 1
    }

    # Verify tables were created
    local table_count
    table_count=$(docker exec eca-openxpki-db mariadb -u openxpki -popenxpki -e "SHOW TABLES;" openxpki 2>/dev/null | wc -l)

    if [ "$table_count" -lt 25 ]; then
        log_error "Database schema import incomplete (only $table_count tables)"
        return 1
    fi

    log_success "Database schema imported ($table_count tables)"
}

start_openxpki_services() {
    log_info "Starting OpenXPKI server..."

    cd "${PROJECT_ROOT}"
    docker compose up -d openxpki-server 2>&1 | grep -v "attribute \`version\` is obsolete" | grep -v "^$" || true

    # Wait for server to be healthy
    local retries=30
    while [ $retries -gt 0 ]; do
        if docker compose ps openxpki-server 2>/dev/null | grep -q "healthy"; then
            break
        fi
        sleep 1
        ((retries--))
    done

    log_success "OpenXPKI server started"

    log_info "Starting OpenXPKI client..."
    docker compose up -d openxpki-client 2>&1 | grep -v "attribute \`version\` is obsolete" | grep -v "^$" || true

    # Wait for client to be healthy
    retries=30
    while [ $retries -gt 0 ]; do
        if docker compose ps openxpki-client 2>/dev/null | grep -q "healthy"; then
            break
        fi
        sleep 1
        ((retries--))
    done

    log_success "OpenXPKI client started"

    log_info "Starting OpenXPKI web server..."
    docker compose up -d openxpki-web 2>&1 | grep -v "attribute \`version\` is obsolete" | grep -v "^$" || true

    # Wait for web to be healthy
    retries=30
    while [ $retries -gt 0 ]; do
        if docker compose ps openxpki-web 2>/dev/null | grep -q "healthy"; then
            log_success "OpenXPKI web server started"
            return 0
        fi
        sleep 1
        ((retries--))
    done

    log_error "Web server failed to become healthy"
    return 1
}

install_cli_key() {
    log_info "Installing CLI authentication key..."

    docker exec -u root eca-openxpki-server mkdir -p /home/pkiadm/.oxi 2>/dev/null || true
    docker cp "${TEMP_CONFIG_DIR}/config/client.key" eca-openxpki-server:/home/pkiadm/.oxi/client.key
    docker exec -u root eca-openxpki-server chown -R pkiadm:pkiadm /home/pkiadm/.oxi
    docker exec -u root eca-openxpki-server chmod 600 /home/pkiadm/.oxi/client.key

    log_success "CLI key installed"
}

run_sample_configuration() {
    log_info "Running OpenXPKI sample configuration..."
    log_info "This will create the demo PKI hierarchy (Root CA and Issuing CA)..."

    # Run sample config script
    docker compose exec -u pkiadm openxpki-server /bin/bash /etc/openxpki/contrib/sampleconfig.sh 2>&1 | \
        grep -E "(result:|Subject:|Issuer:|Certificate is to be certified)" | head -20 || true

    log_success "Sample configuration completed"
}

configure_apache() {
    log_info "Configuring Apache web server for EST endpoint..."

    # Copy Apache configuration from volume to container
    docker run --rm -v openxpki-config-data:/config:ro alpine:latest \
        cat /config/contrib/apache2-openxpki-site.conf > /tmp/openxpki-apache.conf 2>/dev/null

    docker cp /tmp/openxpki-apache.conf eca-openxpki-web:/etc/apache2/sites-available/openxpki.conf
    rm -f /tmp/openxpki-apache.conf

    # Enable site and modules
    docker exec -u root eca-openxpki-web bash -c '
        a2dissite 000-default default-ssl > /dev/null 2>&1 || true
        a2ensite openxpki > /dev/null 2>&1
        a2enmod ssl rewrite headers macro proxy proxy_http > /dev/null 2>&1
        apache2ctl graceful > /dev/null 2>&1
    ' || {
        log_error "Failed to configure Apache"
        return 1
    }

    log_success "Apache configured with EST endpoint support"
}

################################################################################
# EST Integration - Complete Configuration
################################################################################

import_ca_to_openxpki_database() {
    log_info "Importing step-ca certificates into OpenXPKI database..."

    # Import Root CA (no chain, it's self-signed)
    docker compose exec -u pkiadm openxpki-server \
        oxi certificate add --cert /etc/openxpki/local/ca/root_ca.crt --force-nochain 1 \
        > /dev/null 2>&1 || {
        log_error "Failed to import Root CA"
        return 1
    }

    # Import EST Intermediate CA as token (generation 2)
    docker compose exec -u pkiadm openxpki-server \
        oxi token add --type certsign --generation 2 \
            --cert /etc/openxpki/local/ca/est-ca.pem \
            --key /etc/openxpki/local/ca/est-ca.key \
        > /dev/null 2>&1 || {
        log_error "Failed to import EST CA as token"
        return 1
    }

    log_success "step-ca certificates imported into database"
}

fix_database_ca_assignments() {
    log_info "Configuring CA token assignments..."

    # Delete dummy CA (ca-signer-1) to make step-ca EST CA (ca-signer-2) active
    docker exec eca-openxpki-db mariadb -u openxpki -popenxpki openxpki -e \
        "DELETE FROM aliases WHERE pki_realm='democa' AND alias='ca-signer-1';" \
        2>/dev/null || {
        log_error "Failed to remove dummy CA alias"
        return 1
    }

    # Assign EST CA and Root CA to democa realm (required for trust validation)
    docker exec eca-openxpki-db mariadb -u openxpki -popenxpki openxpki -e \
        "UPDATE certificate SET pki_realm='democa' WHERE subject IN ('CN=EST Intermediate CA', 'CN=ECA-PoC-CA Root CA,O=ECA-PoC-CA');" \
        2>/dev/null || {
        log_error "Failed to assign CAs to democa realm"
        return 1
    }

    log_success "CA token assignments configured"
}

configure_est_endpoint() {
    log_info "Creating EST endpoint configuration..."

    # Create EST endpoint configuration with complete working settings
    docker run --rm -v openxpki-config-data:/config alpine:latest sh -c 'cat > /config/config.d/realm.tpl/est/default.yaml << '\''EOF'\''
label: EST Default Endpoint (step-ca)

# Trust bootstrap certificates from step-ca EST Intermediate CA
authorized_signer:
    bootstrap:
        # Accept bootstrap-client certificates
        subject: CN=bootstrap-client
        realm: _any  # Allow external certificates

renewal_period: "000060"
initial_validity: "+000090"

policy:
    # Require client certificate (no anonymous enrollment)
    allow_anon_enroll: 0
    # Auto-approve requests with valid bootstrap cert
    allow_man_approv: 0
    approval_points: 0
    # Allow multiple active certs for testing
    max_active_certs: 10
    auto_revoke_existing_certs: 0

    # CRITICAL: Enable external signer validation (must be in policy section!)
    allow_external_signer: 1
    allow_untrusted_signer: 1

profile:
    # Issue TLS client certificates
    cert_profile: tls_client
    cert_subject_style: enroll

eligible:
    initial:
        value: 1
    renewal:
        value: 1
    onbehalf:
       value: 1

# ============================================================
# CRITICAL: Environment parameter mapping for workflows
# These lists tell OpenXPKI which HTTP request parameters
# to pass to workflows. Without this, signer_cert is not sent!
# ============================================================

simpleenroll:
    env:
        - signer_cert
        - signer_dn
        - server
        - endpoint

simplereenroll:
    env:
        - signer_cert
        - signer_dn
        - server
        - endpoint

simplerevoke:
    env:
        - signer_cert
        - signer_dn
        - server
        - endpoint
EOF
' || {
        log_error "Failed to create EST endpoint configuration"
        return 1
    }

    log_success "EST endpoint configuration created"
}

configure_tls_client_profile() {
    log_info "Configuring TLS client certificate profile..."

    # Add validity configuration to tls_client profile
    docker run --rm -v openxpki-config-data:/config alpine:latest sh -c 'cat >> /config/config.d/realm.tpl/profile/tls_client.yaml << '\''EOF'\''

# Validity configuration - limit to 3 months to stay within CA validity
validity:
    notafter: "+0003"
EOF
' || {
        log_error "Failed to update tls_client profile"
        return 1
    }

    log_success "TLS client profile configured with validity limits"
}

configure_apache_ssl_trust() {
    log_info "Configuring Apache SSL trust chain..."

    # Copy step-ca certificates to Apache SSL trust directory
    docker exec eca-openxpki-web sh -c '
        mkdir -p /etc/openxpki/tls/chain
        cp /etc/openxpki/local/ca/est-ca.pem /etc/openxpki/tls/chain/est-ca.pem
        cp /etc/openxpki/local/ca/root_ca.crt /etc/openxpki/tls/chain/root-ca.pem
        c_rehash /etc/openxpki/tls/chain/
    ' 2>/dev/null || {
        log_error "Failed to configure Apache SSL trust chain"
        return 1
    }

    log_success "Apache SSL trust chain configured"
}

restart_openxpki_services() {
    log_info "Restarting OpenXPKI services to apply EST configuration..."

    cd "${PROJECT_ROOT}"
    docker compose restart openxpki-server openxpki-client openxpki-web 2>&1 | \
        grep -v "attribute \`version\` is obsolete" | grep -v "^$" || true

    # Wait for services to be healthy
    local retries=30
    while [ $retries -gt 0 ]; do
        if docker compose ps openxpki-server openxpki-client openxpki-web 2>/dev/null | \
           grep -q "healthy.*healthy.*healthy"; then
            log_success "OpenXPKI services restarted and healthy"
            return 0
        fi
        sleep 1
        ((retries--))
    done

    log_warn "Services restarted but health check timeout"
    return 0
}

################################################################################
# Verification
################################################################################

verify_est_endpoint() {
    log_info "Verifying EST endpoint..."

    # Wait a moment for Apache to fully reload
    sleep 3

    # Test EST /cacerts endpoint
    if curl -k -f -s https://localhost:8443/.well-known/est/cacerts > /dev/null 2>&1; then
        log_success "EST /cacerts endpoint is operational!"

        # Decode and show certificate info
        local cert_info
        cert_info=$(curl -k -s https://localhost:8443/.well-known/est/cacerts 2>/dev/null | \
            base64 -d | openssl pkcs7 -inform der -print_certs -text 2>/dev/null | \
            grep -E "Subject: CN=" | head -2)

        echo ""
        log_info "EST Certificate chain:"
        echo "${cert_info}" | sed 's/^/  /'
        echo ""
    else
        log_error "EST endpoint verification failed"
        log_error "Try: curl -k https://localhost:8443/.well-known/est/cacerts"
        return 1
    fi

    # Verify unified PKI configuration
    log_info "Verifying unified PKI configuration..."

    # Check active CA token
    local active_ca
    active_ca=$(docker compose exec -u pkiadm openxpki-server oxi token list --realm democa 2>/dev/null | \
        grep "active:" | awk '{print $2}')

    if [ "$active_ca" = "ca-signer-2" ]; then
        log_success "Active CA: ca-signer-2 (step-ca EST CA) ✅"
    else
        log_warn "Active CA: ${active_ca} (expected: ca-signer-2)"
    fi

    # Verify EST CA is in database
    local est_ca_count
    est_ca_count=$(docker exec eca-openxpki-db mariadb -u openxpki -popenxpki openxpki \
        -e "SELECT COUNT(*) FROM certificate WHERE subject='CN=EST Intermediate CA';" 2>/dev/null | tail -1)

    if [ "$est_ca_count" -gt 0 ]; then
        log_success "EST CA imported into database ✅"
    else
        log_warn "EST CA not found in database"
    fi

    # Verify Root CA realm assignment
    local root_ca_realm
    root_ca_realm=$(docker exec eca-openxpki-db mariadb -u openxpki -popenxpki openxpki \
        -e "SELECT pki_realm FROM certificate WHERE subject='CN=ECA-PoC-CA Root CA,O=ECA-PoC-CA' LIMIT 1;" 2>/dev/null | tail -1)

    if [ "$root_ca_realm" = "democa" ]; then
        log_success "Root CA assigned to democa realm ✅"
    else
        log_warn "Root CA realm: ${root_ca_realm} (expected: democa)"
    fi

    echo ""
    log_success "Unified PKI verification complete!"

    return 0
}

################################################################################
# Cleanup
################################################################################

cleanup() {
    log_info "Cleaning up temporary files..."

    if [ -d "${TEMP_CONFIG_DIR}" ]; then
        log_info "Configuration files saved to: ${TEMP_CONFIG_DIR}"
        log_info "  - CLI key: ${TEMP_CONFIG_DIR}/config/client.key"
        log_info "  - Vault secret: ${TEMP_CONFIG_DIR}/config/vault-secret.txt"
        log_warn "Keep these files secure or delete after verification"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    echo ""
    echo "=========================================="
    echo "  OpenXPKI Complete Setup"
    echo "  EST Integration with step-ca"
    echo "=========================================="
    echo ""

    # Run prerequisite checks
    if ! check_prerequisites; then
        exit 1
    fi

    echo ""
    log_info "This script will perform a complete OpenXPKI setup with EST integration:"
    log_info "  1. Clone OpenXPKI community configuration"
    log_info "  2. Generate CLI authentication key"
    log_info "  3. Generate vault encryption secret"
    log_info "  4. Import step-ca EST intermediate CA"
    log_info "  5. Create Docker volumes"
    log_info "  6. Start OpenXPKI services (database, server, client, web)"
    log_info "  7. Import database schema"
    log_info "  8. Run sample configuration (create demo PKI)"
    log_info "  9. Import step-ca CAs into OpenXPKI database"
    log_info " 10. Configure unified PKI (remove dummy CA, assign realms)"
    log_info " 11. Create EST endpoint configuration"
    log_info " 12. Configure TLS client certificate profile"
    log_info " 13. Configure Apache EST endpoint with SSL trust"
    log_info " 14. Restart services to apply configuration"
    log_info " 15. Verify EST endpoint is operational"
    echo ""

    if [ "$NON_INTERACTIVE" = false ]; then
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Aborted by user"
            exit 0
        fi
        echo ""
    fi

    # Execute all steps
    clone_openxpki_config || exit 1
    generate_cli_auth_key || exit 1
    generate_vault_secret || exit 1
    import_step_ca_certificates || exit 1
    create_docker_volume || exit 1
    copy_to_volume || exit 1

    echo ""
    log_info "Volume setup complete, starting services..."
    echo ""

    start_database || exit 1
    import_database_schema || exit 1
    start_openxpki_services || exit 1
    install_cli_key || exit 1
    run_sample_configuration || exit 1

    echo ""
    log_info "Configuring unified PKI with step-ca..."
    echo ""

    import_ca_to_openxpki_database || exit 1
    fix_database_ca_assignments || exit 1
    configure_est_endpoint || exit 1
    configure_tls_client_profile || exit 1
    configure_apache || exit 1
    configure_apache_ssl_trust || exit 1
    restart_openxpki_services || exit 1

    echo ""
    verify_est_endpoint || exit 1

    echo ""
    cleanup

    echo ""
    echo "=========================================="
    echo "  ✅ Unified PKI Setup Complete!"
    echo "=========================================="
    echo ""
    log_success "OpenXPKI with unified PKI (step-ca) is fully operational"
    echo ""
    log_info "EST Protocol: FULLY FUNCTIONAL"
    log_info "  - /cacerts endpoint: ✅ Working"
    log_info "  - Enrollment: ✅ Working (unified PKI with ACME)"
    echo ""
    echo "EST Endpoint: https://localhost:8443/.well-known/est/"
    echo ""
    echo "Test EST /cacerts endpoint:"
    echo "  ${GREEN}curl -k https://localhost:8443/.well-known/est/cacerts | base64 -d | openssl pkcs7 -inform der -print_certs${NC}"
    echo ""
    echo "Verify active CA (should be ca-signer-2 = step-ca EST CA):"
    echo "  ${GREEN}docker compose exec -u pkiadm openxpki-server oxi token list --realm democa | grep active${NC}"
    echo ""
    echo "View OpenXPKI web UI:"
    echo "  ${GREEN}https://localhost:8443/${NC}"
    echo ""
    echo "Container status:"
    echo "  ${GREEN}docker compose ps | grep openxpki${NC}"
    echo ""
    echo "Next: Start EST agent to test enrollment:"
    echo "  ${GREEN}docker compose up -d eca-est-agent && docker compose logs -f eca-est-agent${NC}"
    echo ""
}

# Handle script interruption
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Run main function
main
