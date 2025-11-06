#!/usr/bin/env bash
################################################################################
# ECA PoC - Environment Reset Helper Script
################################################################################
#
# Purpose: Intelligently detect initialization state and assist with cleanup
#          and re-initialization of the ECA PoC environment.
#
# Usage:
#   ./reset-environment.sh [OPTIONS]
#
# Options:
#   --force         Skip confirmation prompts (use with caution)
#   --volumes-only  Only remove volumes, keep containers stopped
#   --help          Show this help message
#
################################################################################

set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Flags
FORCE_MODE=false
VOLUMES_ONLY=false

################################################################################
# Helper Functions
################################################################################

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

print_section() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

print_usage() {
    cat << EOF
ECA PoC - Environment Reset Helper Script

Usage: $0 [OPTIONS]

Options:
  --force         Skip confirmation prompts (use with caution)
  --volumes-only  Only remove volumes, keep containers stopped
  --help          Show this help message

Examples:
  $0                    # Interactive reset with prompts
  $0 --force            # Force reset without prompts
  $0 --volumes-only     # Remove volumes only

EOF
}

################################################################################
# Environment Detection
################################################################################

check_docker_available() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker first."
        return 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker."
        return 1
    fi

    return 0
}

check_containers_running() {
    local running_count
    running_count=$(docker compose ps -q 2>/dev/null | wc -l)

    if [ "$running_count" -gt 0 ]; then
        return 0
    fi
    return 1
}

check_volumes_exist() {
    local volumes=(
        "pki-data"
        "openxpki-config-data"
        "openxpki-db"
        "server-certs"
        "client-certs"
        "challenge"
        "posh-acme-state"
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

    local existing_volumes=()
    for vol in "${volumes[@]}"; do
        if docker volume inspect "$vol" &> /dev/null; then
            existing_volumes+=("$vol")
        fi
    done

    if [ ${#existing_volumes[@]} -gt 0 ]; then
        echo "${existing_volumes[@]}"
        return 0
    fi
    return 1
}

get_initialization_status() {
    local status="UNINITIALIZED"
    local details=""

    # Check if volumes exist
    local volumes
    if volumes=$(check_volumes_exist); then
        status="PARTIAL"

        # Check if critical volumes exist
        if docker volume inspect pki-data &> /dev/null; then
            # Check if pki-data is properly initialized
            if docker run --rm -v pki-data:/check:ro alpine test -f /check/config/ca.json 2>/dev/null; then
                status="INITIALIZED"
                details="PKI volume appears properly initialized"
            else
                status="INCOMPLETE"
                details="PKI volume exists but appears incomplete"
            fi
        else
            details="Some volumes exist but critical PKI volume is missing"
        fi
    else
        details="No volumes found"
    fi

    echo "$status|$details"
}

################################################################################
# Display Functions
################################################################################

display_environment_status() {
    print_section "Current Environment Status"

    # Docker availability
    if check_docker_available; then
        log_success "Docker is available and running"
    else
        log_error "Docker is not available"
        return 1
    fi

    # Container status
    echo ""
    log_info "Container Status:"
    if check_containers_running; then
        log_warn "Containers are currently running"
        docker compose ps 2>/dev/null | tail -n +2 | while read -r line; do
            echo "  • $line"
        done
    else
        log_info "No containers running"
    fi

    # Volume status
    echo ""
    log_info "Volume Status:"
    local volumes
    if volumes=$(check_volumes_exist); then
        log_warn "Found existing volumes:"
        for vol in $volumes; do
            local size
            size=$(docker volume inspect "$vol" --format '{{.Mountpoint}}' 2>/dev/null | xargs du -sh 2>/dev/null | cut -f1 || echo "unknown")
            echo "  • $vol (size: $size)"
        done
    else
        log_info "No volumes found"
    fi

    # Initialization status
    echo ""
    local init_status
    init_status=$(get_initialization_status)
    local status="${init_status%%|*}"
    local details="${init_status##*|}"

    case "$status" in
        UNINITIALIZED)
            log_info "Environment Status: ${CYAN}${status}${NC}"
            log_info "Details: $details"
            ;;
        PARTIAL|INCOMPLETE)
            log_warn "Environment Status: ${YELLOW}${status}${NC}"
            log_warn "Details: $details"
            log_warn "This may cause startup issues - re-initialization recommended"
            ;;
        INITIALIZED)
            log_success "Environment Status: ${GREEN}${status}${NC}"
            log_info "Details: $details"
            ;;
    esac

    return 0
}

################################################################################
# Cleanup Functions
################################################################################

stop_containers() {
    log_info "Stopping all containers..."
    if docker compose down 2>/dev/null; then
        log_success "Containers stopped successfully"
        return 0
    else
        log_error "Failed to stop containers"
        return 1
    fi
}

remove_volumes() {
    log_info "Removing volumes..."

    local volumes
    if volumes=$(check_volumes_exist); then
        local removed=0
        local failed=0

        for vol in $volumes; do
            if docker volume rm "$vol" 2>/dev/null; then
                log_success "Removed volume: $vol"
                ((removed++))
            else
                log_error "Failed to remove volume: $vol"
                ((failed++))
            fi
        done

        echo ""
        log_info "Summary: Removed $removed volume(s), Failed $failed"

        if [ $failed -gt 0 ]; then
            return 1
        fi
    else
        log_info "No volumes to remove"
    fi

    return 0
}

run_initialization() {
    print_section "Running Initialization"

    if [ -f "./integration-test.sh" ]; then
        log_info "Starting environment initialization..."
        echo ""

        # Set default password to avoid prompts
        export ECA_CA_PASSWORD="${ECA_CA_PASSWORD:-eca-poc-default-password}"

        if ./integration-test.sh --init-only; then
            echo ""
            log_success "Initialization completed successfully!"
            return 0
        else
            echo ""
            log_error "Initialization failed"
            return 1
        fi
    else
        log_error "integration-test.sh not found in current directory"
        return 1
    fi
}

################################################################################
# Main Logic
################################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_MODE=true
                shift
                ;;
            --volumes-only)
                VOLUMES_ONLY=true
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

    print_section "ECA PoC - Environment Reset Helper"

    # Check Docker availability
    if ! check_docker_available; then
        exit 1
    fi

    # Display current status
    if ! display_environment_status; then
        exit 1
    fi

    # Determine what needs to be done
    local init_status
    init_status=$(get_initialization_status)
    local status="${init_status%%|*}"

    echo ""

    # If already initialized and no issues, confirm if user wants to reset
    if [ "$status" = "INITIALIZED" ] && [ "$FORCE_MODE" = false ]; then
        print_section "Reset Confirmation"
        log_warn "The environment appears to be properly initialized."
        echo ""
        read -p "Do you want to reset and re-initialize everything? (yes/NO): " -r
        echo ""

        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Reset cancelled by user"
            echo ""
            log_info "To start the stack without resetting, run: ${CYAN}docker compose up -d${NC}"
            exit 0
        fi
    fi

    # Confirm cleanup for partial/incomplete states
    if [ "$status" = "PARTIAL" ] || [ "$status" = "INCOMPLETE" ]; then
        if [ "$FORCE_MODE" = false ]; then
            print_section "Cleanup Recommendation"
            log_warn "The environment is in an inconsistent state."
            log_info "Re-initialization is recommended to ensure proper operation."
            echo ""
            read -p "Proceed with cleanup and re-initialization? (yes/NO): " -r
            echo ""

            if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                log_info "Cleanup cancelled by user"
                exit 0
            fi
        fi
    fi

    # Perform cleanup
    print_section "Cleanup Process"

    # Stop containers
    if check_containers_running; then
        if ! stop_containers; then
            log_error "Failed to stop containers. Cannot proceed."
            exit 1
        fi
    else
        log_info "No running containers to stop"
    fi

    # Remove volumes
    if ! remove_volumes; then
        log_error "Failed to remove all volumes"
        log_warn "You may need to manually remove some volumes with: ${CYAN}docker volume rm <volume-name>${NC}"
        exit 1
    fi

    log_success "Cleanup completed successfully"

    # Run initialization unless volumes-only mode
    if [ "$VOLUMES_ONLY" = false ]; then
        if ! run_initialization; then
            log_error "Failed to initialize environment"
            exit 1
        fi

        print_section "Next Steps"
        echo ""
        log_success "Environment has been reset and initialized!"
        echo ""
        echo "You can now:"
        echo "  ${CYAN}1.${NC} Start all services:        ${GREEN}docker compose up -d${NC}"
        echo "  ${CYAN}2.${NC} Run integration tests:     ${GREEN}./integration-test.sh${NC}"
        echo "  ${CYAN}3.${NC} View service logs:         ${GREEN}docker compose logs -f${NC}"
        echo ""
    else
        print_section "Volumes Removed"
        echo ""
        log_info "Volumes have been removed. Containers are stopped."
        echo ""
        echo "To re-initialize, run: ${CYAN}./integration-test.sh --init-only${NC}"
        echo ""
    fi
}

# Run main function
main "$@"
