#!/bin/bash
# tools/lint.sh
#
# Purpose: Lint project source code and output results in JSON format
# - Ensures environment is set up and linting tools are installed
# - Detects project type and runs appropriate linter
# - Output ONLY valid JSON to stdout (all other output goes to stderr)
#
# Exit Codes:
#   0 - Linting passed (no syntax errors or critical warnings)
#   1 - Linting failed (syntax errors or critical warnings found) or script error

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Get project root directory (parent of tools/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

# All logging goes to stderr to keep stdout clean for JSON
log_info() {
    echo "[INFO] $*" >&2
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

#####################################
# Environment Setup
#####################################
setup_environment() {
    log_info "Ensuring environment is set up..."

    # Run install script silently to ensure dependencies are installed
    if [[ -f "tools/install.sh" ]]; then
        bash tools/install.sh >&2 2>&1 || log_warn "install.sh had warnings"
    fi

    # Activate Python virtual environment if it exists
    if [[ -f ".venv/bin/activate" ]]; then
        # shellcheck disable=SC1091
        source .venv/bin/activate
    fi
}

#####################################
# Python Linting with pylint
#####################################
lint_python() {
    log_info "Linting Python files..."

    # Ensure pylint is installed
    if ! python -c "import pylint" &> /dev/null; then
        log_info "Installing pylint..."
        pip install pylint --quiet >&2 2>&1
    fi

    # Find all Python files
    local python_files
    python_files=$(find . -name "*.py" \
        -not -path "./.venv/*" \
        -not -path "./venv/*" \
        -not -path "./.tox/*" \
        -not -path "./build/*" \
        -not -path "./dist/*" \
        -not -path "./.eggs/*" \
        -not -path "./.git/*" \
        -not -path "./node_modules/*" \
        2>/dev/null)

    if [[ -z "$python_files" ]]; then
        log_info "No Python files found to lint"
        echo "[]"
        return 0
    fi

    log_info "Found $(echo "$python_files" | wc -l) Python files to lint"

    # Run pylint with JSON output, filtering for syntax errors and critical warnings only
    # We use --disable=all and --enable=E,F to show only errors and fatal issues
    local temp_output
    temp_output=$(mktemp)
    local exit_code=0

    # Run pylint with JSON reporter
    # shellcheck disable=SC2086
    pylint $python_files \
        --output-format=json \
        --disable=all \
        --enable=E,F \
        --score=no \
        --reports=no \
        2>/dev/null > "$temp_output" || exit_code=$?

    # Transform pylint JSON to required format
    if [[ -s "$temp_output" ]]; then
        python3 <<'PYTHON_SCRIPT'
import json
import sys

try:
    with open(sys.argv[1], 'r') as f:
        pylint_output = json.load(f)

    # Transform to required format
    transformed = []
    for item in pylint_output:
        transformed.append({
            "type": item.get("type", "error"),
            "path": item.get("path", ""),
            "obj": item.get("obj", ""),
            "message": item.get("message", ""),
            "line": str(item.get("line", "")),
            "column": str(item.get("column", ""))
        })

    # Output as JSON array
    print(json.dumps(transformed, indent=2))
except Exception as e:
    print(f"[]", file=sys.stderr)
    print(f"Error processing pylint output: {e}", file=sys.stderr)
    print("[]")
PYTHON_SCRIPT
"$temp_output"
    else
        echo "[]"
    fi

    rm -f "$temp_output"

    # Return non-zero if pylint found issues
    return "$exit_code"
}

#####################################
# JavaScript/Node.js Linting with eslint
#####################################
lint_javascript() {
    log_info "Linting JavaScript/TypeScript files..."

    # Check if eslint is available
    local eslint_cmd=""
    if [[ -f "node_modules/.bin/eslint" ]]; then
        eslint_cmd="./node_modules/.bin/eslint"
    elif command -v eslint &> /dev/null; then
        eslint_cmd="eslint"
    else
        log_info "ESLint not found, installing..."
        npm install --save-dev eslint --silent >&2 2>&1
        eslint_cmd="./node_modules/.bin/eslint"
    fi

    # Find all JavaScript/TypeScript files
    local js_files
    js_files=$(find . \( -name "*.js" -o -name "*.jsx" -o -name "*.ts" -o -name "*.tsx" \) \
        -not -path "./node_modules/*" \
        -not -path "./dist/*" \
        -not -path "./build/*" \
        -not -path "./.git/*" \
        2>/dev/null)

    if [[ -z "$js_files" ]]; then
        log_info "No JavaScript/TypeScript files found to lint"
        echo "[]"
        return 0
    fi

    log_info "Found $(echo "$js_files" | wc -l) JavaScript/TypeScript files to lint"

    local temp_output
    temp_output=$(mktemp)
    local exit_code=0

    # Run eslint with JSON output
    # shellcheck disable=SC2086
    $eslint_cmd $js_files \
        --format json \
        --quiet \
        2>/dev/null > "$temp_output" || exit_code=$?

    # Transform eslint JSON to required format
    if [[ -s "$temp_output" ]]; then
        python3 <<'PYTHON_SCRIPT'
import json
import sys

try:
    with open(sys.argv[1], 'r') as f:
        eslint_output = json.load(f)

    # Transform to required format
    transformed = []
    for file_result in eslint_output:
        file_path = file_result.get("filePath", "")
        for message in file_result.get("messages", []):
            # Only include errors and warnings (severity 2 = error, 1 = warning)
            if message.get("severity", 0) >= 1:
                transformed.append({
                    "type": "error" if message.get("severity") == 2 else "warning",
                    "path": file_path,
                    "obj": message.get("ruleId", ""),
                    "message": message.get("message", ""),
                    "line": str(message.get("line", "")),
                    "column": str(message.get("column", ""))
                })

    # Output as JSON array
    print(json.dumps(transformed, indent=2))
except Exception as e:
    print(f"Error processing eslint output: {e}", file=sys.stderr)
    print("[]")
PYTHON_SCRIPT
"$temp_output"
    else
        echo "[]"
    fi

    rm -f "$temp_output"
    return "$exit_code"
}

#####################################
# PowerShell Linting with PSScriptAnalyzer
#####################################
lint_powershell() {
    log_info "Linting PowerShell files..."

    if ! command -v pwsh &> /dev/null; then
        log_warn "PowerShell (pwsh) not found, skipping PowerShell linting"
        echo "[]"
        return 0
    fi

    # Ensure PSScriptAnalyzer is installed
    if ! pwsh -NoProfile -Command "Get-Module -ListAvailable -Name PSScriptAnalyzer" &> /dev/null; then
        log_info "Installing PSScriptAnalyzer..."
        pwsh -NoProfile -Command "Install-Module -Name PSScriptAnalyzer -Force -SkipPublisherCheck -Scope CurrentUser" >&2 2>&1
    fi

    # Find all PowerShell files
    local ps_files
    ps_files=$(find . \( -name "*.ps1" -o -name "*.psm1" -o -name "*.psd1" \) \
        -not -path "./.git/*" \
        2>/dev/null)

    if [[ -z "$ps_files" ]]; then
        log_info "No PowerShell files found to lint"
        echo "[]"
        return 0
    fi

    log_info "Found $(echo "$ps_files" | wc -l) PowerShell files to lint"

    local temp_output
    temp_output=$(mktemp)
    local exit_code=0

    # Run PSScriptAnalyzer and convert to JSON
    # Only show errors and warnings (severity: Error, Warning)
    pwsh -NoProfile -Command "
        \$results = @()
        Get-ChildItem -Path . -Include *.ps1,*.psm1,*.psd1 -Recurse -File |
            Where-Object { \$_.FullName -notmatch '[\\\\/]\\.git[\\\\/]' } |
            ForEach-Object {
                Invoke-ScriptAnalyzer -Path \$_.FullName -Severity Error,Warning |
                    ForEach-Object {
                        \$results += @{
                            type = \$_.Severity.ToString().ToLower()
                            path = \$_.ScriptPath
                            obj = \$_.RuleName
                            message = \$_.Message
                            line = \$_.Line.ToString()
                            column = \$_.Column.ToString()
                        }
                    }
            }
        \$results | ConvertTo-Json -Depth 10
    " 2>/dev/null > "$temp_output" || exit_code=$?

    # Ensure output is valid JSON array
    if [[ -s "$temp_output" ]]; then
        local content
        content=$(cat "$temp_output")

        # If output is a single object, wrap in array
        if [[ "$content" =~ ^\{.*\}$ ]]; then
            echo "[$content]"
        elif [[ "$content" == "null" ]] || [[ -z "$content" ]]; then
            echo "[]"
        else
            echo "$content"
        fi
    else
        echo "[]"
    fi

    rm -f "$temp_output"
    return "$exit_code"
}

#####################################
# Bash/Shell Linting with shellcheck
#####################################
lint_shell() {
    log_info "Linting shell scripts..."

    if ! command -v shellcheck &> /dev/null; then
        log_warn "shellcheck not found, skipping shell script linting"
        log_warn "Install shellcheck: https://github.com/koalaman/shellcheck"
        echo "[]"
        return 0
    fi

    # Find all shell scripts
    local shell_files
    shell_files=$(find . \( -name "*.sh" -o -name "*.bash" \) \
        -not -path "./.git/*" \
        -not -path "./node_modules/*" \
        2>/dev/null)

    if [[ -z "$shell_files" ]]; then
        log_info "No shell scripts found to lint"
        echo "[]"
        return 0
    fi

    log_info "Found $(echo "$shell_files" | wc -l) shell scripts to lint"

    local temp_output
    temp_output=$(mktemp)
    local exit_code=0

    # Run shellcheck with JSON output
    # shellcheck disable=SC2086
    shellcheck $shell_files \
        --format=json \
        --severity=error \
        2>/dev/null > "$temp_output" || exit_code=$?

    # Transform shellcheck JSON to required format
    if [[ -s "$temp_output" ]]; then
        python3 <<'PYTHON_SCRIPT'
import json
import sys

try:
    with open(sys.argv[1], 'r') as f:
        shellcheck_output = json.load(f)

    # Transform to required format
    transformed = []
    for item in shellcheck_output:
        transformed.append({
            "type": item.get("level", "error"),
            "path": item.get("file", ""),
            "obj": "SC" + str(item.get("code", "")),
            "message": item.get("message", ""),
            "line": str(item.get("line", "")),
            "column": str(item.get("column", ""))
        })

    # Output as JSON array
    print(json.dumps(transformed, indent=2))
except Exception as e:
    print(f"Error processing shellcheck output: {e}", file=sys.stderr)
    print("[]")
PYTHON_SCRIPT
"$temp_output"
    else
        echo "[]"
    fi

    rm -f "$temp_output"
    return "$exit_code"
}

#####################################
# Main Execution
#####################################
main() {
    log_info "========================================="
    log_info "Linting Project Source Code"
    log_info "========================================="

    # Ensure environment is set up (output to stderr)
    setup_environment

    # Detect project type and run appropriate linter
    local all_results="[]"
    local has_errors=0

    # Check for Python files
    if find . -name "*.py" -not -path "./.venv/*" -not -path "./.git/*" 2>/dev/null | grep -q .; then
        log_info "Python files detected"
        local python_results
        if python_results=$(lint_python); then
            log_info "Python linting passed"
        else
            log_warn "Python linting found issues"
            has_errors=1
        fi
        all_results=$(python3 -c "import json; import sys; a=json.loads('$all_results'); b=json.loads('''$python_results'''); print(json.dumps(a+b))")
    fi

    # Check for JavaScript/TypeScript files
    if find . \( -name "*.js" -o -name "*.jsx" -o -name "*.ts" -o -name "*.tsx" \) -not -path "./node_modules/*" -not -path "./.git/*" 2>/dev/null | grep -q .; then
        log_info "JavaScript/TypeScript files detected"
        local js_results
        if js_results=$(lint_javascript); then
            log_info "JavaScript/TypeScript linting passed"
        else
            log_warn "JavaScript/TypeScript linting found issues"
            has_errors=1
        fi
        all_results=$(python3 -c "import json; a=json.loads('$all_results'); b=json.loads('''$js_results'''); print(json.dumps(a+b))")
    fi

    # Check for PowerShell files
    if find . \( -name "*.ps1" -o -name "*.psm1" \) -not -path "./.git/*" 2>/dev/null | grep -q .; then
        log_info "PowerShell files detected"
        local ps_results
        if ps_results=$(lint_powershell); then
            log_info "PowerShell linting passed"
        else
            log_warn "PowerShell linting found issues"
            has_errors=1
        fi
        all_results=$(python3 -c "import json; a=json.loads('$all_results'); b=json.loads('''$ps_results'''); print(json.dumps(a+b))")
    fi

    # Check for shell scripts
    if find . \( -name "*.sh" -o -name "*.bash" \) -not -path "./.git/*" 2>/dev/null | grep -q .; then
        log_info "Shell scripts detected"
        local shell_results
        if shell_results=$(lint_shell); then
            log_info "Shell script linting passed"
        else
            log_warn "Shell script linting found issues"
            has_errors=1
        fi
        all_results=$(python3 -c "import json; a=json.loads('$all_results'); b=json.loads('''$shell_results'''); print(json.dumps(a+b))")
    fi

    # Output final JSON to stdout
    echo "$all_results"

    log_info "========================================="
    if [[ $has_errors -eq 0 ]]; then
        log_info "Linting completed: No issues found"
        log_info "========================================="
        exit 0
    else
        log_warn "Linting completed: Issues found (see JSON output)"
        log_info "========================================="
        exit 1
    fi
}

# Run main function
main "$@"
