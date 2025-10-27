# Project Automation Tools

This directory contains robust shell scripts for automating common project tasks.

## Available Scripts

### 1. `install.sh` - Environment Setup & Dependency Installation

**Purpose:** Ensures the development environment is properly configured and all dependencies are installed.

**Usage:**
```bash
bash tools/install.sh
```

**Features:**
- Auto-detects project type (Python, Node.js, PowerShell, Docker)
- Creates and activates Python virtual environment (`.venv`)
- Installs/updates dependencies from manifest files (`requirements.txt`, `package.json`, etc.)
- Installs development tools (pylint, Pester, etc.)
- Idempotent: safe to run multiple times
- Provides helpful warnings if required tools are missing

**Exit Codes:**
- `0` - Success
- `1` - Error during setup

---

### 2. `run.sh` - Run Project Application

**Purpose:** Runs the main project application after ensuring dependencies are installed.

**Usage:**
```bash
bash tools/run.sh
```

**Features:**
- Automatically calls `install.sh` to ensure environment is ready
- Auto-detects project entry point:
  - Docker Compose (`docker-compose.yml`)
  - Node.js (`package.json` with `scripts.start`)
  - Python (`main.py`, `app.py`, `src/main.py`)
  - PowerShell (`main.ps1`, `agents/acme/agent.ps1`)
- Activates Python virtual environment if present

**Exit Codes:**
- `0` - Success
- `1` - Error during execution

---

### 3. `lint.sh` - Code Linting with JSON Output

**Purpose:** Lints project source code and outputs results in JSON format.

**Usage:**
```bash
bash tools/lint.sh
```

**Output Format:**
- **stdout:** Valid JSON array of linting errors
- **stderr:** Progress logs and informational messages

**JSON Schema:**
```json
[
  {
    "type": "error",
    "path": "/path/to/file.py",
    "obj": "function_name",
    "message": "Syntax error: ...",
    "line": "42",
    "column": "10"
  }
]
```

**Supported Languages:**
- **Python:** pylint (errors and fatal issues only)
- **JavaScript/TypeScript:** eslint
- **PowerShell:** PSScriptAnalyzer
- **Shell:** shellcheck

**Features:**
- Auto-installs missing linting tools
- Only reports syntax errors and critical warnings
- Clean JSON output to stdout (no mixed output)
- Returns non-zero exit code if issues found

**Exit Codes:**
- `0` - No linting issues found
- `1` - Linting issues found or script error

---

### 4. `test.sh` - Run Project Tests

**Purpose:** Runs all project tests across multiple frameworks.

**Usage:**
```bash
bash tools/test.sh
```

**Features:**
- Automatically calls `install.sh` to ensure test dependencies
- Auto-detects and runs tests for:
  - **Python:** pytest or unittest
  - **Node.js:** npm test (from `package.json`)
  - **PowerShell:** Pester (`*.Tests.ps1` files)
  - **Shell:** Test scripts in `tests/` directory
  - **Integration:** `tests/integration/run-all-tests.sh`
- Color-coded output showing pass/fail status
- Comprehensive summary of all test results

**Exit Codes:**
- `0` - All tests passed
- `1` - One or more tests failed

---

## Script Design Principles

All scripts follow these best practices:

1. **Robust Error Handling:**
   - `set -e` - Exit on error
   - `set -u` - Exit on undefined variable
   - `set -o pipefail` - Exit on pipe failure

2. **Safety:**
   - All variables properly quoted
   - No destructive commands without safeguards
   - Idempotent operations (safe to run multiple times)

3. **User Experience:**
   - Color-coded output (when terminal supports it)
   - Clear, informative log messages
   - Helpful warnings and error messages
   - Proper exit codes for automation

4. **Modularity:**
   - `install.sh` is called by other scripts to ensure dependencies
   - Each script has a single, clear responsibility
   - Scripts can be run independently or as part of workflows

---

## Example Workflow

```bash
# 1. Set up environment and install dependencies
bash tools/install.sh

# 2. Run linting to check code quality
bash tools/lint.sh > lint-results.json

# 3. Run tests
bash tools/test.sh

# 4. Run the application
bash tools/run.sh
```

---

## Environment Detection

The scripts automatically detect:

- **Python:** Looks for `requirements.txt`, creates `.venv`, installs with pip
- **Node.js:** Looks for `package.json`, runs `npm install`
- **PowerShell:** Checks for `pwsh`, installs Pester module
- **Conda:** Looks for `environment.yml`, manages conda environments
- **Docker:** Checks for `docker-compose.yml`, uses Docker Compose

---

## Troubleshooting

### PowerShell Not Found

If you see warnings about PowerShell not being found:
```bash
[WARN] PowerShell (pwsh) not found
```

Install PowerShell from: https://github.com/PowerShell/PowerShell

### Linting Tools Missing

Linting tools are automatically installed when needed. If you prefer to install them manually:

```bash
# Python
pip install pylint

# JavaScript
npm install --save-dev eslint

# PowerShell
pwsh -Command "Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser"

# Shell
# Install shellcheck from: https://github.com/koalaman/shellcheck
```

### Tests Not Found

If `test.sh` reports no tests found, ensure your tests follow these naming conventions:

- **Python:** `test_*.py` or `*_test.py` in `tests/` directory
- **Node.js:** Define `"test"` script in `package.json`
- **PowerShell:** `*.Tests.ps1` files
- **Shell:** `test-*.sh` or `*-test.sh` in `tests/` directory

---

## Contributing

When modifying these scripts:

1. Test changes thoroughly
2. Verify bash syntax: `bash -n tools/<script>.sh`
3. Ensure idempotency (safe to run multiple times)
4. Update this README if adding new features
5. Follow existing error handling patterns

---

## License

These scripts are part of the Edge Certificate Agent (ECA) Proof of Concept project.
