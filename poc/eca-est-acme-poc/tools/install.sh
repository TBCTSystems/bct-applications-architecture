#!/bin/bash
# tools/install.sh
#
# Purpose: Environment setup and dependency installation
# - Detects project type and creates/activates environments
# - Installs/updates all project dependencies
# - Idempotent: safe to run multiple times
#
# Exit Codes:
#   0 - Success
#   1 - Error during setup

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Color output for better readability (only if terminal supports it)
if [[ -t 2 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
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

# Get project root directory (parent of tools/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

log_info "Starting environment setup and dependency installation"
log_info "Project root: $PROJECT_ROOT"

# Track if any installations occurred
INSTALLED_SOMETHING=false

#####################################
# Python Environment Management
#####################################
setup_python_env() {
    local python_cmd=""

    # Find Python 3 command
    if command -v python3 &> /dev/null; then
        python_cmd="python3"
    elif command -v python &> /dev/null && [[ "$(python --version 2>&1)" == *"Python 3"* ]]; then
        python_cmd="python"
    else
        log_warn "Python 3 not found, skipping Python environment setup"
        return 0
    fi

    log_info "Found Python: $python_cmd ($(${python_cmd} --version))"

    # Create virtual environment if it doesn't exist
    if [[ ! -d ".venv" ]]; then
        log_info "Creating Python virtual environment..."
        "$python_cmd" -m venv .venv
        INSTALLED_SOMETHING=true
    else
        log_info "Python virtual environment already exists"
    fi

    # Activate virtual environment
    # shellcheck disable=SC1091
    source .venv/bin/activate

    # Upgrade pip to latest version
    log_info "Ensuring pip is up to date..."
    python -m pip install --upgrade pip --quiet

    # Install/update dependencies from requirements files
    if [[ -f "requirements.txt" ]]; then
        log_info "Installing dependencies from requirements.txt..."
        pip install -r requirements.txt --quiet
        INSTALLED_SOMETHING=true
    fi

    if [[ -f "requirements-dev.txt" ]]; then
        log_info "Installing development dependencies from requirements-dev.txt..."
        pip install -r requirements-dev.txt --quiet
        INSTALLED_SOMETHING=true
    fi

    # Install pylint for linting if not present
    if ! python -c "import pylint" &> /dev/null; then
        log_info "Installing pylint for linting..."
        pip install pylint --quiet
        INSTALLED_SOMETHING=true
    fi

    # Export environment activation helper for other scripts
    cat > .venv/activate.sh <<'EOF'
#!/bin/bash
# Auto-generated activation helper
# Source this file to activate the Python virtual environment
if [[ -f ".venv/bin/activate" ]]; then
    source .venv/bin/activate
fi
EOF
    chmod +x .venv/activate.sh
}

#####################################
# Node.js Environment Management
#####################################
setup_nodejs_env() {
    if [[ ! -f "package.json" ]] && [[ ! -f "web-ui/package.json" ]]; then
        return 0
    fi

    if ! command -v npm &> /dev/null; then
        log_warn "npm not found, skipping Node.js dependency installation"
        return 0
    fi

    log_info "Found Node.js: $(node --version) with npm: $(npm --version)"

    # Install dependencies in root if package.json exists
    if [[ -f "package.json" ]]; then
        log_info "Installing Node.js dependencies from root package.json..."
        npm install --silent
        INSTALLED_SOMETHING=true
    fi

    # Install dependencies in web-ui if package.json exists
    if [[ -f "web-ui/package.json" ]]; then
        log_info "Installing Node.js dependencies for web-ui..."
        cd web-ui
        npm install --silent
        cd "$PROJECT_ROOT"
        INSTALLED_SOMETHING=true
    fi
}

#####################################
# PowerShell Environment Check
#####################################
check_powershell() {
    if ! command -v pwsh &> /dev/null; then
        log_warn "PowerShell (pwsh) not found"
        log_warn "This project uses PowerShell for certificate agents"
        log_warn "Install from: https://github.com/PowerShell/PowerShell"
        return 1
    fi

    log_info "Found PowerShell: $(pwsh --version)"

    # Check for Pester (PowerShell testing framework)
    if ! pwsh -NoProfile -Command "Get-Module -ListAvailable -Name Pester" &> /dev/null; then
        log_info "Installing Pester for PowerShell testing..."
        pwsh -NoProfile -Command "Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser" &> /dev/null || true
        INSTALLED_SOMETHING=true
    fi
}

#####################################
# Docker Environment Check
#####################################
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_warn "Docker not found"
        log_warn "This project requires Docker for containerized services"
        return 1
    fi

    log_info "Found Docker: $(docker --version)"

    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_warn "docker-compose not found"
        log_warn "Install docker-compose or use Docker with Compose plugin"
        return 1
    fi

    if command -v docker-compose &> /dev/null; then
        log_info "Found docker-compose: $(docker-compose --version)"
    else
        log_info "Found docker compose: $(docker compose version)"
    fi
}

#####################################
# Conda Environment Management
#####################################
setup_conda_env() {
    if [[ ! -f "environment.yml" ]] && [[ ! -f "conda.yml" ]]; then
        return 0
    fi

    if ! command -v conda &> /dev/null; then
        log_warn "Conda not found, but environment.yml detected"
        log_warn "Install Miniconda or Anaconda to use Conda environments"
        return 1
    fi

    local env_file=""
    if [[ -f "environment.yml" ]]; then
        env_file="environment.yml"
    elif [[ -f "conda.yml" ]]; then
        env_file="conda.yml"
    fi

    # Extract environment name from file
    local env_name
    env_name=$(grep "^name:" "$env_file" | awk '{print $2}')

    if [[ -z "$env_name" ]]; then
        log_error "Could not extract environment name from $env_file"
        return 1
    fi

    # Check if environment exists
    if ! conda env list | grep -q "^${env_name} "; then
        log_info "Creating Conda environment: $env_name"
        conda env create -f "$env_file"
        INSTALLED_SOMETHING=true
    else
        log_info "Updating Conda environment: $env_name"
        conda env update -f "$env_file" --prune
        INSTALLED_SOMETHING=true
    fi

    log_info "Conda environment '$env_name' is ready"
    log_info "Activate with: conda activate $env_name"
}

#####################################
# Main Execution
#####################################
main() {
    log_info "========================================="
    log_info "Environment & Dependency Installation"
    log_info "========================================="

    # Detect and setup environments based on project files

    # 1. Check for Conda environment
    if [[ -f "environment.yml" ]] || [[ -f "conda.yml" ]]; then
        setup_conda_env || log_warn "Conda setup failed, continuing..."
    fi

    # 2. Check for Python virtual environment
    if [[ -f "requirements.txt" ]] || [[ -f "requirements-dev.txt" ]]; then
        setup_python_env || log_warn "Python setup failed, continuing..."
    fi

    # 3. Check for Node.js dependencies
    setup_nodejs_env || log_warn "Node.js setup failed, continuing..."

    # 4. Check for PowerShell
    check_powershell || log_warn "PowerShell check failed, continuing..."

    # 5. Check for Docker
    check_docker || log_warn "Docker check failed, continuing..."

    log_info "========================================="
    if [[ "$INSTALLED_SOMETHING" == "true" ]]; then
        log_info "Environment setup complete - dependencies installed/updated"
    else
        log_info "Environment setup complete - all dependencies up to date"
    fi
    log_info "========================================="

    exit 0
}

# Run main function
main "$@"
