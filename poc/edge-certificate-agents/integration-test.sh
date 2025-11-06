#!/usr/bin/env bash
################################################################################
# ECA PoC - Comprehensive Integration Test Orchestration Script
################################################################################
#
# Purpose: End-to-end automated testing and validation of the ECA PoC stack
#          This script provides a reproducible, automated way to:
#          - Initialize PKI infrastructure (step-ca root + ACME/EST intermediates)
#          - Configure OpenXPKI EST server with shared trust chain
#          - Spin up complete docker-compose stack
#          - Validate all endpoints (PKI, ACME, EST, CRL)
#          - Run integration tests
#          - Clean teardown
#
# Usage:
#   ./integration-test.sh [OPTIONS]
#
# Options:
#   --init-only         Only initialize volumes, don't start stack
#   --start-only        Only start stack (assumes volumes initialized)
#   --validate-only     Only validate endpoints (assumes stack running)
#   --test-only         Only run tests (assumes stack running)
#   --no-cleanup        Don't tear down stack after tests
#   --skip-init         Skip volume initialization if already done
#   --quick             Quick mode: skip init if volumes exist
#   --clean             Clean all volumes and restart from scratch
#   --help              Show this help message
#
# Exit Codes:
#   0 - All tests passed
#   1 - Initialization failed
#   2 - Stack startup failed
#   3 - Validation failed
#   4 - Tests failed
#
################################################################################

set -euo pipefail

################################################################################
# Configuration
################################################################################

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_NAME="eca-poc"
readonly LOG_DIR="${SCRIPT_DIR}/logs"
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Volume initialization constants
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

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'

# Flags
INIT_ONLY=false
START_ONLY=false
VALIDATE_ONLY=false
TEST_ONLY=false
NO_CLEANUP=false
SKIP_INIT=false
QUICK_MODE=false
CLEAN_MODE=false

# Timeout settings (seconds)
readonly PKI_STARTUP_TIMEOUT=60
readonly OPENXPKI_STARTUP_TIMEOUT=120
readonly SERVICE_READY_TIMEOUT=30
readonly ENDPOINT_TIMEOUT=10

# Services to validate
readonly CORE_SERVICES=(
    "pki"
    "openxpki-db"
    "openxpki-server"
    "openxpki-client"
    "openxpki-web"
)

readonly AGENT_SERVICES=(
    "eca-acme-agent"
    "eca-est-agent"
)

readonly TARGET_SERVICES=(
    "target-server"
    "target-client"
)

################################################################################
# Helper Functions
################################################################################

log_section() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" >&2
}

log_step() {
    echo -e "${MAGENTA}[STEP]${NC} $1"
}

################################################################################
# Error Handling & Command Execution
################################################################################

setup_logging() {
    # Create logs directory if it doesn't exist
    mkdir -p "${LOG_DIR}"
    log_info "Log directory: ${LOG_DIR}"
}

execute_command() {
    local description="$1"
    shift
    local log_file="${LOG_DIR}/${TIMESTAMP}_$(echo "$description" | tr ' ' '_' | tr -cd '[:alnum:]_').log"

    echo -n -e "${BLUE}⏳${NC} $description"

    # Execute command and capture output
    if "$@" > "$log_file" 2>&1; then
        echo -e "\r${GREEN}✅${NC} $description"
        return 0
    else
        local exit_code=$?
        echo -e "\r${RED}❌${NC} $description"
        echo ""
        log_error "Command failed with exit code: $exit_code"
        log_error "Command: $*"
        log_error "📝 Full error log saved to:"
        log_error "  ${RED}${log_file}${NC}"
        echo ""
        echo -e "${RED}▼▼▼ ERROR LOG (last 20 lines) ▼▼▼${NC}"
        tail -20 "$log_file" | sed "s/^/  ${RED}|${NC} /"
        echo -e "${RED}▲▲▲ ERROR LOG ▲▲▲${NC}"
        echo ""
        log_error "📄 For full error details, see: ${log_file}"
        return $exit_code
    fi
}

check_prerequisites() {
    log_info "🔍 Checking prerequisites..."

    local failed=false

    # Check for step CLI
    if ! command -v step &> /dev/null; then
        log_error "🔐 step CLI not found!"
        log_error "   Install from: https://smallstep.com/docs/step-cli/installation"
        failed=true
    else
        log_info "  ✓ step CLI found"
    fi

    # Check for docker
    if ! command -v docker &> /dev/null; then
        log_error "🐳 Docker not found!"
        log_error "   Install from: https://docs.docker.com/get-docker/"
        failed=true
    else
        log_info "  ✓ Docker found"

        # Check if Docker daemon is running
        if ! docker info &> /dev/null; then
            log_error "🐳 Docker daemon is not running. Please start Docker."
            failed=true
        else
            log_info "  ✓ Docker daemon running"
        fi
    fi

    # Check for docker compose
    if ! docker compose version &> /dev/null 2>&1; then
        log_error "🐳 Docker Compose v2 not found!"
        log_error "   Ensure Docker Compose is installed and available"
        failed=true
    else
        log_info "  ✓ Docker Compose found"
    fi

    # Check for pwsh if tests will be run
    if [ "$TEST_ONLY" = false ] && [ "$VALIDATE_ONLY" = false ]; then
        if ! command -v pwsh &> /dev/null; then
            log_warn "⚠️  PowerShell (pwsh) not found - tests may fail"
            log_warn "   Install from: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell"
        else
            log_info "  ✓ PowerShell found"
        fi
    fi

    if [ "$failed" = true ]; then
        log_error "❌ Prerequisite checks failed. Please install missing dependencies."
        return 1
    fi

    log_success "✅ All prerequisites met"
    return 0
}

print_usage() {
    cat << EOF
ECA PoC - Comprehensive Integration Test Orchestration Script

Usage: $0 [OPTIONS]

Options:
  --init-only         Only initialize volumes, don't start stack
  --start-only        Only start stack (assumes volumes initialized)
  --validate-only     Only validate endpoints (assumes stack running)
  --test-only         Only run tests (assumes stack running)
  --no-cleanup        Don't tear down stack after tests
  --skip-init         Skip volume initialization if already done
  --quick             Quick mode: skip init if volumes exist
  --clean             Clean all volumes and restart from scratch
  --help              Show this help message

Examples:
  $0                  # Full end-to-end test (init + start + validate + test)
  $0 --quick          # Quick run (skip init if volumes exist)
  $0 --clean          # Clean everything and start fresh
  $0 --validate-only  # Only validate endpoints (for debugging)
  $0 --no-cleanup     # Keep stack running after tests

EOF
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

        # In non-interactive mode, keep existing volume
        if [ ! -t 0 ]; then
            log_info "Non-interactive mode: keeping existing volume"
            return 0
        fi

        read -p "Do you want to remove and recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Removing existing volume..."

            # Try to remove the volume
            if ! docker volume rm "${VOLUME_PKI}" 2>/dev/null; then
                log_error "❌ Volume is in use by running containers"
                echo ""
                read -p "Stop all containers and remove volumes? (y/N): " -n 1 -r
                echo

                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Stopping all containers and removing volumes..."
                    docker compose down -v || {
                        log_error "Failed to stop containers"
                        return 1
                    }
                    log_success "Containers stopped"

                    # Now create the volume
                    docker volume create "${VOLUME_PKI}"
                    log_success "PKI volume created successfully"
                    return 0
                else
                    log_info "Aborted by user"
                    log_error "Please run: docker compose down"
                    return 1
                fi
            fi
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

    # Fix permissions for docker access
    chmod -R 777 "${TEMP_PKI_DIR}"

    # Copy using /source/. pattern to avoid glob expansion issues
    # The dot notation copies all contents including hidden files
    execute_command "Copying PKI data to volume" \
        docker run --rm \
            --entrypoint sh \
            -v "${VOLUME_PKI}:/home/step" \
            -v "${TEMP_PKI_DIR}:/source:ro" \
            smallstep/step-ca:latest \
            -c "cp -r /source/. /home/step/ && chown -R step:step /home/step" || return 1

    # Overlay project-managed helper scripts to ensure latest versions are present
    execute_command "Syncing PKI helper scripts" \
        docker run --rm \
            --entrypoint sh \
            -v "${VOLUME_PKI}:/home/step" \
            -v "${SCRIPT_DIR}/pki/scripts:/project-scripts:ro" \
            alpine \
            -c "mkdir -p /home/step/scripts && cp -f /project-scripts/*.sh /home/step/scripts/ && chown -R 1000:1000 /home/step/scripts && chmod 755 /home/step/scripts/*.sh" || return 1

    log_success "PKI data copied to volume"
}

ensure_crl_volume_permissions() {
    log_info "Ensuring CRL volume permissions..."

    if ! docker volume inspect crl-data > /dev/null 2>&1; then
        log_info "CRL volume 'crl-data' not found – creating"
        docker volume create crl-data > /dev/null
    fi

    execute_command "Aligning crl-data ownership" \
        docker run --rm \
            --entrypoint sh \
            -v crl-data:/data \
            alpine \
            -c "chown -R 1000:1000 /data && chmod -R 755 /data" || return 1

    log_success "CRL volume ownership updated"
}

start_pki_for_provisioning() {
    log_info "Starting PKI container temporarily to configure provisioners..."

    # Start just the PKI service
    execute_command "Starting PKI service" docker compose up -d pki || return 1

    # Wait for PKI to be healthy
    log_info "Waiting for PKI to be ready..."
    for i in $(seq 1 30); do
        if docker compose ps pki 2>/dev/null | grep -q "healthy"; then
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
    execute_command "Copying OpenXPKI base configuration" \
        docker run --rm \
            -v "${VOLUME_OPENXPKI_CONFIG}:/config" \
            -v "$(pwd)/est-server/openxpki-setup/openxpki-config:/source:ro" \
            alpine \
            sh -c "cp -r /source/. /config/" || return 1

    log_success "OpenXPKI base configuration copied"

    # Copy EST certificates from PKI volume to OpenXPKI volume
    execute_command "Copying EST certificates to OpenXPKI" \
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
            " || return 1

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
    execute_command "Starting OpenXPKI database" docker compose up -d openxpki-db || return 1

    # Wait for database to be healthy
    log_info "Waiting for database to be ready..."
    for i in $(seq 1 30); do
        if docker compose ps openxpki-db 2>/dev/null | grep -q "healthy"; then
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
    execute_command "Starting OpenXPKI server" docker compose up -d openxpki-server || return 1

    # Wait for server to be healthy
    log_info "Waiting for OpenXPKI server to be ready..."
    for i in $(seq 1 30); do
        if docker compose ps openxpki-server 2>/dev/null | grep -q "healthy"; then
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
# Volume Management
################################################################################

check_volumes_exist() {
    log_info "Checking if PKI volumes exist..."

    local volumes=("pki-data" "openxpki-config-data" "openxpki-db")
    local all_exist=true

    for vol in "${volumes[@]}"; do
        if ! docker volume inspect "$vol" &> /dev/null; then
            log_warn "Volume '$vol' does not exist"
            all_exist=false
        else
            log_info "Volume '$vol' exists"
        fi
    done

    if [ "$all_exist" = true ]; then
        log_success "All PKI volumes exist"
        return 0
    else
        log_warn "Some PKI volumes are missing"
        return 1
    fi
}

clean_volumes() {
    log_section "🧹 Cleaning All Volumes"

    log_warn "⚠️  This will delete ALL ECA PoC volumes and data!"
    read -p "Are you sure? (yes/NO): " -r
    echo

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Aborted by user"
        return 0
    fi

    execute_command "Stopping all services" docker compose down -v || true

    log_step "🗑️  Removing all volumes..."
    local volumes=(
        "pki-data"
        "server-certs"
        "client-certs"
        "challenge"
        "posh-acme-state"
        "est-data"
        "est-secrets"
        "openxpki-config-data"
        "openxpki-db"
        "openxpki-socket"
        "openxpki-client-socket"
        "openxpki-db-socket"
        "openxpki-log"
        "openxpki-log-ui"
        "openxpki-download"
        "loki-data"
        "grafana-data"
        "fluentd-buffer"
        "crl-data"
    )

    for vol in "${volumes[@]}"; do
        if docker volume inspect "$vol" &> /dev/null; then
            log_info "Removing volume: $vol"
            docker volume rm "$vol" || log_warn "Failed to remove $vol"
        fi
    done

    log_success "All volumes cleaned"
}

initialize_volumes() {
    log_section "🔐 Initializing PKI Volumes"

    if [ "$SKIP_INIT" = true ] && check_volumes_exist; then
        log_info "⏭️  Skipping initialization (volumes already exist)"
        return 0
    fi

    # Set non-interactive mode and default password
    export ECA_CA_PASSWORD="${ECA_CA_PASSWORD:-password}"

    # Execute all initialization steps directly
    initialize_pki || return 1
    create_pki_volume || return 1
    copy_pki_to_volume || return 1
    ensure_crl_volume_permissions || return 1

    # Start PKI to trigger provisioner configuration and EST cert generation
    start_pki_for_provisioning || return 1
    wait_for_est_certificates || return 1

    # Now initialize OpenXPKI with the EST certificates
    initialize_openxpki || return 1
    provision_openxpki_web_tls || return 1
    initialize_openxpki_database || return 1
    import_certificates_to_openxpki || return 1

    # Cleanup temporary files
    log_info "Cleaning up temporary files..."
    if [ -d "${TEMP_PKI_DIR}" ]; then
        rm -rf "${TEMP_PKI_DIR}"
    fi
    log_success "Cleanup complete"

    log_success "✅ Volume initialization complete"
}

################################################################################
# Stack Management
################################################################################

start_stack() {
    log_section "🚀 Starting Docker Compose Stack"

    cd "${SCRIPT_DIR}"

    execute_command "Starting all services" docker compose up -d || return 1

    log_info "⏳ Waiting for services to start..."
    sleep 5

    log_success "✅ Stack started"
}

wait_for_service_healthy() {
    local service=$1
    local timeout=${2:-$SERVICE_READY_TIMEOUT}
    local interval=2
    local elapsed=0

    log_info "Waiting for $service to be healthy..."

    while [ $elapsed -lt $timeout ]; do
        local container_id
        container_id=$(docker compose ps -q "$service" 2>/dev/null)

        if [ -z "$container_id" ]; then
            log_warn "$service container not found"
            sleep $interval
            elapsed=$((elapsed + interval))
            continue
        fi

        local health_status
        health_status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}running{{end}}' "$container_id" 2>/dev/null || echo "unknown")

        if [ "$health_status" = "healthy" ] || [ "$health_status" = "running" ]; then
            log_success "$service is $health_status"
            return 0
        fi

        sleep $interval
        elapsed=$((elapsed + interval))
    done

    log_error "$service failed to become healthy within ${timeout}s"
    return 1
}

wait_for_core_services() {
    log_section "⏳ Waiting for Core Services"

    for service in "${CORE_SERVICES[@]}"; do
        wait_for_service_healthy "$service" || return 1
    done

    log_success "✅ All core services are healthy"
}

################################################################################
# Endpoint Validation
################################################################################

validate_endpoint() {
    local name=$1
    local url=$2
    local expected_code=${3:-200}
    local description=${4:-""}

    log_info "Validating: $name"
    log_info "  URL: $url"

    local response_code
    if response_code=$(curl -k -s -o /dev/null -w "%{http_code}" --max-time "$ENDPOINT_TIMEOUT" "$url" 2>/dev/null); then
        if [ "$response_code" = "$expected_code" ]; then
            log_success "$name is accessible (HTTP $response_code)"
            return 0
        else
            log_error "$name returned unexpected HTTP code: $response_code (expected $expected_code)"
            return 1
        fi
    else
        log_error "$name is not accessible"
        return 1
    fi
}

validate_endpoints() {
    log_section "🔍 Validating Endpoints"

    local failed=0

    # PKI (step-ca)
    log_step "🔐 Validating PKI endpoints..."
    validate_endpoint "step-ca Health" "https://localhost:4210/health" 200 || ((failed++))
    validate_endpoint "step-ca ACME Directory" "https://localhost:4210/acme/acme/directory" 200 || ((failed++))

    # CRL
    log_step "📜 Validating CRL endpoint..."
    validate_endpoint "CRL HTTP Server" "http://localhost:4211/health" 200 || ((failed++))
    validate_endpoint "CRL File" "http://localhost:4211/crl/ca.crl" 200 || ((failed++))

    # OpenXPKI EST
    log_step "🌐 Validating EST endpoints..."
    # OpenXPKI returns 301 redirect, which is acceptable
    if ! validate_endpoint "OpenXPKI Web UI" "http://localhost:4212/" 200; then
        if validate_endpoint "OpenXPKI Web UI (redirect)" "http://localhost:4212/" 301; then
            log_success "OpenXPKI Web UI is accessible (HTTP 301 redirect)"
        else
            ((failed++))
        fi
    fi
    # EST cacerts endpoint returns 200 when accessible
    validate_endpoint "EST cacerts" "https://localhost:4213/.well-known/est/cacerts" 200 || ((failed++))

    # Target services
    log_step "🎯 Validating target services..."
    validate_endpoint "Target Server" "https://localhost:4214" 200 || log_warn "⚠️  Target server may not have cert yet"

    if [ $failed -eq 0 ]; then
        log_success "✅ All endpoints validated successfully"
        return 0
    else
        log_error "❌ $failed endpoint(s) failed validation"
        return 1
    fi
}

################################################################################
# Testing
################################################################################

run_integration_tests() {
    log_section "🧪 Running Integration Tests"

    cd "${SCRIPT_DIR}"

    log_step "⚙️  Running Pester integration tests..."

    # Check if test runner service exists in docker-compose
    if docker compose ps test-runner &> /dev/null; then
        log_info "🐳 Using docker-compose test-runner service"
        docker compose run --rm test-runner pwsh -Command "
            \$config = New-PesterConfiguration
            \$config.Run.Path = './tests/integration'
            \$config.Run.Exit = \$true
            \$config.Output.Verbosity = 'Detailed'
            Invoke-Pester -Configuration \$config
        "
    else
        log_info "Using local PowerShell for tests"
        if command -v pwsh &> /dev/null; then
            pwsh -Command "
                \$config = New-PesterConfiguration
                \$config.Run.Path = './tests/integration'
                \$config.Run.Exit = \$true
                \$config.Output.Verbosity = 'Detailed'
                Invoke-Pester -Configuration \$config
            "
        else
            log_error "PowerShell (pwsh) not found. Cannot run tests."
            return 1
        fi
    fi

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log_success "All integration tests passed"
        return 0
    else
        log_error "Integration tests failed (exit code: $exit_code)"
        return 1
    fi
}

################################################################################
# Status Display
################################################################################

display_stack_status() {
    log_section "Stack Status"

    echo -e "${CYAN}Container Status:${NC}"
    docker compose ps

    echo ""
    echo -e "${CYAN}Quick Access URLs (Custom Port Range 4210-4230):${NC}"
    echo -e "  ${GREEN}step-ca:${NC}        https://localhost:4210/health"
    echo -e "  ${GREEN}ACME Directory:${NC} https://localhost:4210/acme/acme/directory"
    echo -e "  ${GREEN}CRL Endpoint:${NC}   http://localhost:4211/crl/ca.crl"
    echo -e "  ${GREEN}EST Endpoint:${NC}   https://localhost:4213/.well-known/est/"
    echo -e "  ${GREEN}OpenXPKI UI:${NC}    http://localhost:4212/"
    echo -e "  ${GREEN}Target Server:${NC}  https://localhost:4214/"
    echo -e "  ${GREEN}Web UI:${NC}         http://localhost:4216/"
    echo -e "  ${GREEN}Grafana:${NC}        http://localhost:4219/ (admin/eca-admin)"
    echo ""
}

################################################################################
# Cleanup
################################################################################

cleanup_stack() {
    if [ "$NO_CLEANUP" = true ]; then
        log_info "Skipping cleanup (--no-cleanup flag set)"
        display_stack_status
        return 0
    fi

    log_section "Cleaning Up"

    execute_command "Stopping services" docker compose down || true

    log_success "Cleanup complete"
}

################################################################################
# Main Execution Flow
################################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --init-only)
                INIT_ONLY=true
                shift
                ;;
            --start-only)
                START_ONLY=true
                shift
                ;;
            --validate-only)
                VALIDATE_ONLY=true
                shift
                ;;
            --test-only)
                TEST_ONLY=true
                shift
                ;;
            --no-cleanup)
                NO_CLEANUP=true
                shift
                ;;
            --skip-init)
                SKIP_INIT=true
                shift
                ;;
            --quick)
                QUICK_MODE=true
                SKIP_INIT=true
                shift
                ;;
            --clean)
                CLEAN_MODE=true
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    # Header
    log_section "ECA PoC - Integration Test Orchestration"

    # Setup logging
    setup_logging

    # Check prerequisites first
    if ! check_prerequisites; then
        log_error "Prerequisites not met. Aborting."
        exit 1
    fi

    # Clean mode
    if [ "$CLEAN_MODE" = true ]; then
        clean_volumes
        SKIP_INIT=false
    fi

    # Execution based on flags
    if [ "$VALIDATE_ONLY" = true ]; then
        validate_endpoints || exit 3
        exit 0
    fi

    if [ "$TEST_ONLY" = true ]; then
        run_integration_tests || exit 4
        exit 0
    fi

    # Initialize volumes
    if [ "$INIT_ONLY" = true ] || [ "$START_ONLY" = false ]; then
        initialize_volumes || exit 1
    fi

    if [ "$INIT_ONLY" = true ]; then
        log_success "🎉 Initialization complete (--init-only mode)"

        echo ""
        echo -e "${GREEN}🚀 Next steps (Custom Port Range 4210-4230):${NC}"
        echo -e "  ${CYAN}1.${NC} Start all services:        ${GREEN}docker compose up -d${NC}"
        echo -e "  ${CYAN}2.${NC} Verify PKI health:         ${GREEN}curl -k https://localhost:4210/health${NC}"
        echo -e "  ${CYAN}3.${NC} Open OpenXPKI Web UI:      ${GREEN}http://localhost:4212${NC}"
        echo -e "  ${CYAN}4.${NC} Open Web UI:               ${GREEN}http://localhost:4216${NC}"
        echo -e "  ${CYAN}5.${NC} Open Grafana:              ${GREEN}http://localhost:4219${NC} ${BLUE}(admin/eca-admin)${NC}"
        echo ""
        exit 0
    fi

    # Start stack
    if [ "$START_ONLY" = true ] || [ "$INIT_ONLY" = false ]; then
        start_stack || exit 2
        wait_for_core_services || exit 2
    fi

    if [ "$START_ONLY" = true ]; then
        log_success "Stack started (--start-only mode)"
        display_stack_status
        exit 0
    fi

    # Validate endpoints
    sleep 5  # Give services a moment to fully stabilize
    validate_endpoints || {
        log_error "Endpoint validation failed"
        cleanup_stack
        exit 3
    }

    # Run tests
    run_integration_tests || {
        log_error "Integration tests failed"
        cleanup_stack
        exit 4
    }

    # Cleanup
    cleanup_stack

    # Success
    log_section "🎉 Integration Tests Complete"
    log_success "✅ All tests passed successfully!"

    echo ""
    echo -e "${GREEN}🚀 Next steps:${NC}"
    echo -e "  ${CYAN}⚡${NC} Run ${CYAN}./integration-test.sh --quick${NC} for faster subsequent runs"
    echo -e "  ${CYAN}🔍${NC} Use ${CYAN}--no-cleanup${NC} to keep stack running for manual testing"
    echo -e "  ${CYAN}📊${NC} Use ${CYAN}docker compose logs -f${NC} to monitor agent activity"
    echo -e "  ${CYAN}📈${NC} Open Grafana at ${GREEN}http://localhost:4219${NC} (admin/eca-admin)"
    echo -e "  ${CYAN}🌐${NC} Open Web UI at ${GREEN}http://localhost:4216${NC}"
    echo ""
}

# Handle script interruption
trap 'log_error "Script interrupted"; cleanup_stack; exit 130' INT TERM

# Run main function
main "$@"
