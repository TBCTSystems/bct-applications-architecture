# ECA Scripts

This directory contains utility scripts for the ECA PoC project.

## Platform Support

All scripts are available in two versions for cross-platform compatibility:

- **`.sh` (Bash)** - For Linux, macOS, and WSL (Windows Subsystem for Linux)
- **`.ps1` (PowerShell)** - For native Windows (PowerShell 7.0+)

**Windows developers:** Use the `.ps1` PowerShell scripts for the best native Windows experience.
**Linux/macOS developers:** Use the `.sh` Bash scripts.

## Available Scripts

### bootstrap-pki.sh

PKI initialization and bootstrap certificate generation script.

**Purpose:** Initializes the step-ca PKI and generates bootstrap certificates required for EST agent authentication.

**Usage:**
```bash
./scripts/bootstrap-pki.sh
```

**What it does:**
- Initializes step-ca configuration and CA certificates
- Creates ACME and EST provisioners
- Generates bootstrap client certificates for EST enrollment
- Configures certificate lifetimes for the PoC

**When to use:**
- First time setting up the PKI
- After deleting PKI volumes
- When resetting the entire PoC environment

---

### run-tests.sh / run-tests.ps1

Automated test runner for unit and integration tests.

**Purpose:** Runs all Pester tests for the ECA PoC agents, with support for coverage reports and selective test execution.

**Usage (Bash - Linux/macOS/WSL):**
```bash
# Run all tests (unit + integration)
./scripts/run-tests.sh

# Run only unit tests
./scripts/run-tests.sh -u

# Run only integration tests
./scripts/run-tests.sh -i

# Run with code coverage report
./scripts/run-tests.sh -c

# Run with verbose output
./scripts/run-tests.sh -v

# Show help
./scripts/run-tests.sh -h
```

**Usage (PowerShell - Windows):**
```powershell
# Run all tests (unit + integration)
.\scripts\run-tests.ps1

# Run only unit tests
.\scripts\run-tests.ps1 -UnitOnly

# Run only integration tests
.\scripts\run-tests.ps1 -IntegrationOnly

# Run with code coverage report
.\scripts\run-tests.ps1 -Coverage

# Run with verbose output
.\scripts\run-tests.ps1 -Verbose

# Show help
.\scripts\run-tests.ps1 -Help
```

**What it tests:**
- PowerShell module unit tests (AcmeClient, EstClient, BootstrapTokenManager)
- Integration tests for end-to-end workflows
- Code coverage analysis (with `-c` flag)

**Exit codes:**
- `0` - All tests passed
- `1` - One or more tests failed
- `2` - Script error or missing dependencies

**Dependencies:**
- PowerShell Core 7.0+ (`pwsh`)
- Pester 5.0+ (auto-installs if missing)

**When to use:**
- Before committing code changes
- During development (fast unit tests)
- In CI/CD pipelines
- To verify agent behavior

**Coverage report location:** `tests/coverage.xml`

---

### run-tests-docker.sh / run-tests-docker.ps1

Docker-based test runner for consistent test environment.

**Purpose:** Runs all tests inside Docker containers, eliminating "works on my machine" problems.

**Usage (Bash - Linux/macOS/WSL):**
```bash
# Run all tests in Docker
./scripts/run-tests-docker.sh

# Run only unit tests
./scripts/run-tests-docker.sh -u

# Run only integration tests
./scripts/run-tests-docker.sh -i

# Run with code coverage
./scripts/run-tests-docker.sh -c

# Rebuild test image and run
./scripts/run-tests-docker.sh -b

# Show help
./scripts/run-tests-docker.sh -h
```

**Usage (PowerShell - Windows):**
```powershell
# Run all tests in Docker
.\scripts\run-tests-docker.ps1

# Run only unit tests
.\scripts\run-tests-docker.ps1 -UnitOnly

# Run only integration tests
.\scripts\run-tests-docker.ps1 -IntegrationOnly

# Run with code coverage
.\scripts\run-tests-docker.ps1 -Coverage

# Rebuild test image and run
.\scripts\run-tests-docker.ps1 -Build

# Show help
.\scripts\run-tests-docker.ps1 -Help
```

**Advantages:**
- ✅ No local PowerShell installation required
- ✅ Consistent environment (same as CI/CD)
- ✅ Isolated from host system
- ✅ Works identically everywhere

**Dependencies:**
- Docker
- Docker Compose

**When to use:**
- CI/CD pipelines (consistent environment)
- Machines without PowerShell installed
- Cross-platform testing
- Ensuring test reproducibility

---

### verify-logging.sh / verify-logging.ps1

Automated verification script for the observability stack (FluentD + Loki + Grafana).

**Purpose:** Proves that logging is working correctly by testing all components of the logging pipeline.

**Usage (Bash - Linux/macOS/WSL):**
```bash
# Run all tests with normal output
./scripts/verify-logging.sh

# Run with detailed verbose output
./scripts/verify-logging.sh -v

# Run in quiet mode (only show pass/fail)
./scripts/verify-logging.sh -q

# Show help
./scripts/verify-logging.sh -h
```

**Usage (PowerShell - Windows):**
```powershell
# Run all tests with normal output
.\scripts\verify-logging.ps1

# Run with detailed verbose output
.\scripts\verify-logging.ps1 -Verbose

# Run in quiet mode (only show pass/fail)
.\scripts\verify-logging.ps1 -Quiet

# Show help
.\scripts\verify-logging.ps1 -Help
```

**What it tests:**
1. Container health (FluentD, Loki, Grafana)
2. Service endpoints and APIs
3. Log flow from agents → FluentD → Loki
4. Log structure and labels
5. End-to-end log generation and retrieval
6. Grafana datasource configuration
7. Dashboard availability
8. Resource usage
9. Buffer configuration

**Exit codes:**
- `0` - All tests passed
- `1` - One or more tests failed
- `2` - Script error or missing dependencies

**Dependencies:**
- `docker` - For container inspection and commands
- `curl` - For API health checks
- `jq` - For JSON parsing

**When to use:**
- After deploying the observability stack
- To troubleshoot logging issues
- In CI/CD pipelines for verification
- Before demonstrating the system to stakeholders

**Example output:**
```
===========================================================
Test Summary
===========================================================
Total Tests: 14
Passed: 14
Failed: 0

✓ All tests passed! Logging system is fully operational.
Access Grafana at: http://localhost:3000 (admin/eca-admin)
```

## Adding New Scripts

When adding new scripts to this directory:

1. Make the script executable: `chmod +x scripts/your-script.sh`
2. Add a shebang line: `#!/bin/bash`
3. Include usage documentation in the script header
4. Update this README with the new script
5. Use consistent exit codes (0=success, 1=failure, 2=error)
6. Include help text with `-h` or `--help` flag

## Script Conventions

- All scripts should be written in Bash (compatible with `/bin/bash`)
- Use `set -euo pipefail` for safety
- Provide clear error messages
- Support `-h` or `--help` for usage information
- Return meaningful exit codes
- Use color codes for output readability (but support `NO_COLOR` env var)
- Include dependency checks at the start

### observability.sh / observability.ps1

Convenience wrapper for managing the Fluentd → Loki → Grafana stack alongside the demo agents.

**Purpose:** Provides one-command bring-up (`demo`), lifecycle management (`up`/`down`/`status`/`logs`), and access to the automated verification flow.

**Usage (Bash - Linux/macOS/WSL):**
```bash
# Full demo: start stack, run verification, generate sample logs
./scripts/observability.sh demo

# Start stack (with agents)
./scripts/observability.sh up --with-agents

# Run verification only (pass flags through)
./scripts/observability.sh verify -v

# Stop stack (and optional agents)
./scripts/observability.sh down --with-agents
```

**Usage (PowerShell - Windows):**
```powershell
./scripts/observability.ps1 demo
./scripts/observability.ps1 up -WithAgents
./scripts/observability.ps1 verify -- -Verbose
./scripts/observability.ps1 down -WithAgents
```

**When to use:**
- Preparing for demos (auto-generates fresh log activity)
- Quickly spinning up the observability stack for troubleshooting
- Running the automated verification flow without remembering the command syntax

---
