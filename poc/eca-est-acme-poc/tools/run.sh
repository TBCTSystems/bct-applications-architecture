#!/bin/bash
# tools/run.sh
#
# Purpose: Run the main project application
# - Ensures environment is set up and dependencies are installed
# - Detects project type and runs appropriate entry point
#
# Exit Codes:
#   0 - Success
#   1 - Error during execution

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Color output for better readability (only if terminal supports it)
if [[ -t 2 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_run() {
    echo -e "${BLUE}[RUN]${NC} $*" >&2
}

# Get project root directory (parent of tools/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

#####################################
# Environment Setup
#####################################
setup_environment() {
    log_info "Ensuring environment is set up..."

    # Run install script to ensure dependencies are installed
    if [[ -f "tools/install.sh" ]]; then
        bash tools/install.sh
    else
        log_warn "tools/install.sh not found, skipping dependency check"
    fi

    # Activate Python virtual environment if it exists
    if [[ -f ".venv/bin/activate" ]]; then
        log_info "Activating Python virtual environment..."
        # shellcheck disable=SC1091
        source .venv/bin/activate
    fi
}

#####################################
# Run Functions for Different Project Types
#####################################

run_python_project() {
    local main_file="$1"

    if [[ ! -f "$main_file" ]]; then
        log_error "Python main file not found: $main_file"
        return 1
    fi

    log_run "Running Python application: $main_file"
    python "$main_file"
}

run_nodejs_project() {
    local package_json="$1"

    if [[ ! -f "$package_json" ]]; then
        log_error "package.json not found: $package_json"
        return 1
    fi

    # Check for start script in package.json
    if grep -q '"start"' "$package_json"; then
        log_run "Running Node.js application via npm start"
        npm start
    else
        # Try to find main entry point from package.json
        local main_file
        main_file=$(grep -o '"main"[[:space:]]*:[[:space:]]*"[^"]*"' "$package_json" | sed 's/"main"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')

        if [[ -n "$main_file" ]] && [[ -f "$main_file" ]]; then
            log_run "Running Node.js application: $main_file"
            node "$main_file"
        else
            log_error "No start script or main entry point found in package.json"
            return 1
        fi
    fi
}

run_docker_project() {
    if [[ ! -f "docker-compose.yml" ]] && [[ ! -f "docker-compose.yaml" ]]; then
        log_error "docker-compose.yml not found"
        return 1
    fi

    log_run "Starting Docker Compose services..."

    # Use docker-compose or docker compose based on availability
    if command -v docker-compose &> /dev/null; then
        docker-compose up
    else
        docker compose up
    fi
}

run_powershell_project() {
    local main_file="$1"

    if [[ ! -f "$main_file" ]]; then
        log_error "PowerShell main file not found: $main_file"
        return 1
    fi

    if ! command -v pwsh &> /dev/null; then
        log_error "PowerShell (pwsh) not found"
        log_error "Install from: https://github.com/PowerShell/PowerShell"
        return 1
    fi

    log_run "Running PowerShell application: $main_file"
    pwsh -File "$main_file"
}

#####################################
# Main Execution
#####################################
main() {
    log_info "========================================="
    log_info "Running Project Application"
    log_info "========================================="

    # Ensure environment is set up
    setup_environment

    log_info "Detecting project type and entry point..."

    # Priority 1: Docker Compose (multi-container application)
    if [[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]; then
        log_info "Detected Docker Compose project"
        run_docker_project
        exit $?
    fi

    # Priority 2: Node.js project with package.json
    if [[ -f "package.json" ]]; then
        log_info "Detected Node.js project (root)"
        run_nodejs_project "package.json"
        exit $?
    fi

    # Priority 3: Node.js web-ui subproject
    if [[ -f "web-ui/package.json" ]]; then
        log_info "Detected Node.js project (web-ui)"
        cd web-ui
        run_nodejs_project "package.json"
        exit $?
    fi

    # Priority 4: Python project
    if [[ -f "main.py" ]]; then
        log_info "Detected Python project (main.py)"
        run_python_project "main.py"
        exit $?
    fi

    if [[ -f "app.py" ]]; then
        log_info "Detected Python project (app.py)"
        run_python_project "app.py"
        exit $?
    fi

    if [[ -f "src/main.py" ]]; then
        log_info "Detected Python project (src/main.py)"
        run_python_project "src/main.py"
        exit $?
    fi

    # Priority 5: PowerShell project
    if [[ -f "main.ps1" ]]; then
        log_info "Detected PowerShell project (main.ps1)"
        run_powershell_project "main.ps1"
        exit $?
    fi

    if [[ -f "agents/acme/agent.ps1" ]]; then
        log_info "Detected PowerShell ACME agent"
        run_powershell_project "agents/acme/agent.ps1"
        exit $?
    fi

    # No recognized project type found
    log_error "Could not detect project type or entry point"
    log_error ""
    log_error "Searched for:"
    log_error "  - docker-compose.yml (Docker Compose)"
    log_error "  - package.json (Node.js)"
    log_error "  - main.py, app.py (Python)"
    log_error "  - main.ps1, agents/acme/agent.ps1 (PowerShell)"
    log_error ""
    log_error "Please create one of these entry points or specify in package.json scripts.start"
    exit 1
}

# Run main function
main "$@"
