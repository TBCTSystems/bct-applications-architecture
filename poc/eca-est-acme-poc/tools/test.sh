#!/bin/bash
# tools/test.sh
#
# Purpose: Run project tests
# - Ensures environment is set up and dependencies are installed
# - Detects project type and runs appropriate test framework
#
# Exit Codes:
#   0 - All tests passed
#   1 - Tests failed or error during execution

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

log_test() {
    echo -e "${BLUE}[TEST]${NC} $*" >&2
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
# Python Testing
#####################################
test_python() {
    log_test "Running Python tests..."

    local test_framework=""
    local has_tests=false

    # Detect test framework
    if python -c "import pytest" &> /dev/null || [[ -f "pytest.ini" ]] || [[ -f "pyproject.toml" ]]; then
        test_framework="pytest"
        has_tests=true
    elif python -c "import unittest" &> /dev/null && find . -name "test_*.py" -o -name "*_test.py" 2>/dev/null | grep -q .; then
        test_framework="unittest"
        has_tests=true
    fi

    if [[ "$has_tests" == "false" ]]; then
        log_warn "No Python test framework detected or no tests found"
        return 0
    fi

    case "$test_framework" in
        pytest)
            log_test "Using pytest framework"
            if ! python -c "import pytest" &> /dev/null; then
                log_info "Installing pytest..."
                pip install pytest pytest-cov --quiet
            fi
            pytest --verbose
            ;;
        unittest)
            log_test "Using unittest framework"
            python -m unittest discover -s . -p "test_*.py" -v
            ;;
    esac
}

#####################################
# JavaScript/Node.js Testing
#####################################
test_javascript() {
    local package_json="$1"

    if [[ ! -f "$package_json" ]]; then
        log_warn "package.json not found: $package_json"
        return 0
    fi

    # Check for test script in package.json
    if grep -q '"test"' "$package_json"; then
        log_test "Running Node.js tests via npm test"
        npm test
    else
        log_warn "No test script defined in package.json"
        log_info "Add a test script to package.json: \"test\": \"jest\" or similar"
        return 0
    fi
}

#####################################
# PowerShell Testing with Pester
#####################################
test_powershell() {
    log_test "Running PowerShell tests..."

    if ! command -v pwsh &> /dev/null; then
        log_warn "PowerShell (pwsh) not found, skipping PowerShell tests"
        return 0
    fi

    # Ensure Pester is installed
    if ! pwsh -NoProfile -Command "Get-Module -ListAvailable -Name Pester" &> /dev/null; then
        log_info "Installing Pester..."
        pwsh -NoProfile -Command "Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser" &> /dev/null
    fi

    # Find test files
    local test_files
    test_files=$(find . -name "*.Tests.ps1" -not -path "./.git/*" 2>/dev/null)

    if [[ -z "$test_files" ]]; then
        log_warn "No PowerShell test files found (*.Tests.ps1)"
        return 0
    fi

    log_test "Found $(echo "$test_files" | wc -l) PowerShell test files"

    # Run Pester tests
    pwsh -NoProfile -Command "
        \$config = New-PesterConfiguration
        \$config.Run.Path = '.'
        \$config.Run.PassThru = \$true
        \$config.Output.Verbosity = 'Detailed'
        \$config.TestResult.Enabled = \$true

        \$result = Invoke-Pester -Configuration \$config

        if (\$result.FailedCount -gt 0) {
            Write-Host \"Tests failed: \$(\$result.FailedCount) failed, \$(\$result.PassedCount) passed\"
            exit 1
        } else {
            Write-Host \"All tests passed: \$(\$result.PassedCount) passed\"
            exit 0
        }
    "
}

#####################################
# Shell Script Testing
#####################################
test_shell() {
    log_test "Looking for shell script tests..."

    # Look for test scripts in tests/ directory
    if [[ -d "tests" ]]; then
        local test_scripts
        test_scripts=$(find tests -name "test-*.sh" -o -name "*-test.sh" 2>/dev/null)

        if [[ -n "$test_scripts" ]]; then
            log_test "Found $(echo "$test_scripts" | wc -l) shell test scripts"

            local failed=0
            while IFS= read -r test_script; do
                if [[ -x "$test_script" ]]; then
                    log_test "Running: $test_script"
                    if bash "$test_script"; then
                        log_info "✓ $test_script passed"
                    else
                        log_error "✗ $test_script failed"
                        failed=$((failed + 1))
                    fi
                else
                    log_warn "Skipping non-executable: $test_script"
                fi
            done <<< "$test_scripts"

            if [[ $failed -gt 0 ]]; then
                log_error "$failed test script(s) failed"
                return 1
            fi
        else
            log_warn "No shell test scripts found in tests/"
        fi
    fi

    return 0
}

#####################################
# Integration Tests
#####################################
test_integration() {
    log_test "Looking for integration tests..."

    if [[ -d "tests/integration" ]]; then
        local test_runner="tests/integration/run-all-tests.sh"

        if [[ -f "$test_runner" ]] && [[ -x "$test_runner" ]]; then
            log_test "Running integration test suite: $test_runner"
            bash "$test_runner"
        else
            log_warn "Integration test runner not found or not executable: $test_runner"
        fi
    fi
}

#####################################
# Main Execution
#####################################
main() {
    log_info "========================================="
    log_info "Running Project Tests"
    log_info "========================================="

    # Ensure environment is set up
    setup_environment

    local tests_run=false
    local overall_exit=0

    # Run Python tests
    if [[ -d "tests/unit" ]] && find tests/unit -name "*.py" 2>/dev/null | grep -q .; then
        log_info "Python unit tests detected"
        if test_python; then
            log_info "✓ Python tests passed"
        else
            log_error "✗ Python tests failed"
            overall_exit=1
        fi
        tests_run=true
    fi

    # Run Node.js tests (root)
    if [[ -f "package.json" ]]; then
        log_info "Node.js project detected (root)"
        if test_javascript "package.json"; then
            log_info "✓ Node.js tests passed"
        else
            log_error "✗ Node.js tests failed"
            overall_exit=1
        fi
        tests_run=true
    fi

    # Run Node.js tests (web-ui)
    if [[ -f "web-ui/package.json" ]]; then
        log_info "Node.js project detected (web-ui)"
        cd web-ui
        if test_javascript "package.json"; then
            log_info "✓ Web UI tests passed"
        else
            log_error "✗ Web UI tests failed"
            overall_exit=1
        fi
        cd "$PROJECT_ROOT"
        tests_run=true
    fi

    # Run PowerShell tests
    if find . -name "*.Tests.ps1" -not -path "./.git/*" 2>/dev/null | grep -q .; then
        log_info "PowerShell tests detected"
        if test_powershell; then
            log_info "✓ PowerShell tests passed"
        else
            log_error "✗ PowerShell tests failed"
            overall_exit=1
        fi
        tests_run=true
    fi

    # Run shell script tests
    if [[ -d "tests" ]] && find tests -name "test-*.sh" -o -name "*-test.sh" 2>/dev/null | grep -q .; then
        log_info "Shell script tests detected"
        if test_shell; then
            log_info "✓ Shell script tests passed"
        else
            log_error "✗ Shell script tests failed"
            overall_exit=1
        fi
        tests_run=true
    fi

    # Run integration tests if they exist
    if [[ -d "tests/integration" ]]; then
        log_info "Integration tests detected"
        if test_integration; then
            log_info "✓ Integration tests passed"
        else
            log_error "✗ Integration tests failed"
            overall_exit=1
        fi
        tests_run=true
    fi

    log_info "========================================="
    if [[ "$tests_run" == "false" ]]; then
        log_warn "No tests found to run"
        log_info ""
        log_info "Looked for:"
        log_info "  - Python: tests/unit/*.py with pytest or unittest"
        log_info "  - Node.js: package.json with test script"
        log_info "  - PowerShell: *.Tests.ps1 files"
        log_info "  - Shell: tests/test-*.sh or tests/*-test.sh"
        log_info "  - Integration: tests/integration/run-all-tests.sh"
        log_info ""
        log_info "Create tests and run this script again"
        exit 0
    elif [[ $overall_exit -eq 0 ]]; then
        log_info "All tests passed!"
        log_info "========================================="
        exit 0
    else
        log_error "Some tests failed"
        log_info "========================================="
        exit 1
    fi
}

# Run main function
main "$@"
