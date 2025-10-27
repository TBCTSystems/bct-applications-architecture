# ECA Testing Strategy

**Everything is testable. Everything is scriptable. Everything runs in Docker.**

## Testing Philosophy

The ECA PoC follows a comprehensive testing strategy to ensure reliability and maintainability:

1. **Unit Tests** - Fast, isolated tests for individual modules
2. **Integration Tests** - End-to-end workflows with live services
3. **Automated Verification** - Scripts to validate infrastructure
4. **Test-Driven Design** - All code designed for testability
5. **Dockerized Testing** - Consistent environment everywhere

## Quick Start

### Local Test Runner (Requires PowerShell 7.0+)

```bash
# Run all tests
./scripts/run-tests.sh

# Run only unit tests
./scripts/run-tests.sh -u

# Run only integration tests
./scripts/run-tests.sh -i

# Run tests with code coverage report
./scripts/run-tests.sh -c

# Run tests with verbose output
./scripts/run-tests.sh -v
```

### Docker Test Runner (No PowerShell Required) ⭐ **RECOMMENDED**

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
```

**Advantages of Docker Test Runner:**
- ✅ No local PowerShell installation required
- ✅ Consistent test environment across all machines
- ✅ Identical to CI/CD environment
- ✅ Isolated from host system
- ✅ Works on Linux, macOS, Windows with Docker

### Direct Docker Compose Usage

```bash
# Build test runner image
docker compose build test-runner

# Run all tests
docker compose run --rm test-runner

# Run only unit tests
docker compose run --rm test-runner pwsh -Command "Invoke-Pester -Path ./tests/unit"

# Run with custom Pester configuration
docker compose run --rm test-runner pwsh -Command "
    \$config = New-PesterConfiguration
    \$config.Run.Path = './tests/unit'
    \$config.Output.Verbosity = 'Detailed'
    Invoke-Pester -Configuration \$config
"
```

## Test Structure

```
tests/
├── unit/                           # Unit tests (fast, isolated)
│   ├── AcmeClient.Tests.ps1       # ACME protocol module tests
│   ├── EstClient.Tests.ps1        # EST protocol module tests
│   └── BootstrapTokenManager.Tests.ps1  # Token management tests
├── integration/                    # Integration tests (requires infrastructure)
│   ├── AcmeWorkflow.Tests.ps1     # ACME end-to-end workflow
│   └── EstWorkflow.Tests.ps1      # EST end-to-end workflow
├── fixtures/                       # Test data and mock responses
└── Dockerfile                      # Test runner Docker image
```

## Unit Tests

### Coverage Targets

- **AcmeClient.psm1**: >80% code coverage
- **EstClient.psm1**: >80% code coverage
- **BootstrapTokenManager.psm1**: >90% code coverage

### What's Tested

#### ACME Client (`AcmeClient.Tests.ps1`)
- ✅ Directory discovery and caching
- ✅ JWS signature creation
- ✅ Account creation with key management
- ✅ Order placement for certificates
- ✅ HTTP-01 challenge completion
- ✅ CSR submission and order finalization
- ✅ Certificate download and parsing
- ✅ Error handling (401, 403, 404, 500)
- ✅ Nonce management
- ✅ Key authorization generation

#### EST Client (`EstClient.Tests.ps1`)
- ✅ Initial enrollment with bootstrap token
- ✅ Re-enrollment with mTLS
- ✅ CSR encoding (PEM → DER → Base64)
- ✅ PKCS#7 response parsing
- ✅ Authorization header validation
- ✅ Content-Type validation
- ✅ Bootstrap token redaction in logs
- ✅ Certificate extraction
- ✅ Error handling (400, 401, 403, 500)

#### Bootstrap Token Manager (`BootstrapTokenManager.Tests.ps1`)
- ✅ Token retrieval from environment variables
- ✅ Token retrieval from config files
- ✅ Token validation (length, character set)
- ✅ Token redaction in all log messages
- ✅ Precedence rules (env var > config file)
- ✅ Error handling for missing tokens

### Running Unit Tests

**Local:**
```bash
# All unit tests
./scripts/run-tests.sh -u

# Specific test file
pwsh -Command "Invoke-Pester -Path ./tests/unit/AcmeClient.Tests.ps1"

# With coverage report
./scripts/run-tests.sh -u -c
```

**Docker:**
```bash
# All unit tests
./scripts/run-tests-docker.sh -u

# Specific test file
docker compose run --rm test-runner pwsh -Command "Invoke-Pester -Path ./tests/unit/AcmeClient.Tests.ps1"

# With coverage
./scripts/run-tests-docker.sh -u -c
```

### Test Framework

We use **Pester 5.7.1** (PowerShell testing framework):

```powershell
Describe "Module Name" {
    Context "Feature Category" {
        BeforeEach {
            # Setup for each test
        }

        It "Should do something specific" {
            # Arrange
            $input = "test data"

            # Act
            $result = Invoke-Function -Input $input

            # Assert
            $result | Should -Be "expected output"
        }
    }
}
```

## Integration Tests

Integration tests require live services to be running.

### Prerequisites

```bash
# Start PKI infrastructure
docker compose up -d pki openxpki-web openxpki-client openxpki-server

# Verify services are healthy
docker compose ps

# Verify PKI connectivity
curl -k https://localhost:9000/health
```

### What's Tested

#### ACME Workflow (`AcmeWorkflow.Tests.ps1`)
- ✅ PKI server connectivity
- ✅ ACME directory retrieval
- ✅ Account creation (skipped by default)
- ⏸️ Full certificate enrollment workflow (future)

#### EST Workflow (`EstWorkflow.Tests.ps1`)
- ✅ EST server connectivity
- ✅ Bootstrap token validation logic
- ✅ Token retrieval from various sources
- ⏸️ Enrollment with real OpenXPKI (future)

### Running Integration Tests

**Local:**
```bash
# All integration tests
./scripts/run-tests.sh -i

# Specific integration test
pwsh -Command "Invoke-Pester -Path ./tests/integration/EstWorkflow.Tests.ps1"
```

**Docker (Recommended):**
```bash
# All integration tests (automatically starts PKI)
./scripts/run-tests-docker.sh -i

# Specific test
docker compose run --rm test-runner pwsh -Command "Invoke-Pester -Path ./tests/integration/EstWorkflow.Tests.ps1"
```

### Integration Test Tags

Tests use tags to categorize risk and requirements:

- `Integration` - Requires live services
- `ACME` - Tests ACME protocol
- `EST` - Tests EST protocol
- `AccountCreation` - Creates actual accounts (skipped by default)

Skip destructive tests by default:
```powershell
# Only run non-destructive integration tests
Invoke-Pester -Path ./tests/integration/ -ExcludeTag AccountCreation
```

## Docker Test Environment

### Test Runner Image

The test runner is based on `mcr.microsoft.com/powershell:7.4-alpine-3.18` with:
- PowerShell 7.4
- Pester 5.0+
- Bash, curl, jq, openssl
- Alpine Linux (minimal footprint)

### Building the Image

```bash
# Build manually
docker compose build test-runner

# Build with wrapper script
./scripts/run-tests-docker.sh -b

# Build directly
docker build -t eca-test-runner -f tests/Dockerfile .
```

### Running Tests in Docker

```bash
# Using docker compose (recommended)
docker compose run --rm test-runner

# Direct docker run
docker run --rm \
  -v $(pwd)/agents:/workspace/agents:ro \
  -v $(pwd)/tests:/workspace/tests:ro \
  --network eca-poc-network \
  eca-test-runner

# With coverage
docker compose run --rm -e GENERATE_COVERAGE=true test-runner
```

### Extracting Coverage Reports

```bash
# Run with coverage
./scripts/run-tests-docker.sh -c

# Coverage report is written to mounted volume
cat tests/coverage.xml
```

## Mocking Strategy

### What We Mock in Unit Tests

1. **Network Calls** - `Invoke-RestMethod`, `Invoke-WebRequest`
2. **File Operations** - `Write-FileAtomic`, `Set-FilePermissions`
3. **Logging** - `Write-LogInfo`, `Write-LogDebug`, `Write-LogError`
4. **Cryptography** - `New-RSAKeyPair` (use fixtures)

### What We DON'T Mock in Integration Tests

1. **PKI Services** - Real step-ca, OpenXPKI
2. **Network Stack** - Actual HTTPS calls
3. **Certificate Validation** - Real crypto operations

## Test Data and Fixtures

Test fixtures are stored in `tests/fixtures/`:

```
tests/fixtures/
├── certificates/
│   ├── valid-cert.pem
│   ├── expired-cert.pem
│   └── test-chain.pem
├── keys/
│   ├── test-rsa-2048.pem
│   └── test-rsa-4096.pem
└── responses/
    ├── acme-directory.json
    ├── acme-order.json
    └── est-pkcs7.p7b
```

## Continuous Integration

### GitHub Actions Workflow

```yaml
name: Run Tests

on: [push, pull_request]

jobs:
  docker-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Run Tests in Docker
        run: ./scripts/run-tests-docker.sh -c

      - name: Upload Coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./tests/coverage.xml
```

### Local CI Simulation

```bash
# Simulate CI environment locally
./scripts/run-tests-docker.sh -b -c

# Exit code determines pass/fail
echo "Exit code: $?"
```

## Writing New Tests

### Unit Test Template

```powershell
<#
.SYNOPSIS
    Unit tests for YourModule.

.DESCRIPTION
    Tests covering all exported functions in YourModule.psm1

.NOTES
    Requires: Pester 5.0+, PowerShell Core 7.0+
#>

#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = "$PSScriptRoot/../../path/to/YourModule.psm1"
    Import-Module $modulePath -Force

    # Mock dependencies
    Mock -ModuleName YourModule -CommandName Write-LogInfo {}
}

AfterAll {
    Remove-Module YourModule -Force -ErrorAction SilentlyContinue
}

Describe "Your-Function" {
    Context "Happy Path" {
        It "Returns expected result when given valid input" {
            # Arrange
            $input = "test"

            # Act
            $result = Your-Function -Input $input

            # Assert
            $result | Should -Be "expected"
        }
    }

    Context "Error Handling" {
        It "Throws when input is invalid" {
            { Your-Function -Input $null } | Should -Throw "*invalid*"
        }
    }
}
```

### Testing in Docker

```bash
# Add your new test
vim tests/unit/YourModule.Tests.ps1

# Run it
./scripts/run-tests-docker.sh -u
```

## Test Execution Best Practices

### Local Development

```bash
# 1. Run unit tests frequently (fast feedback)
./scripts/run-tests.sh -u

# OR use Docker for consistency
./scripts/run-tests-docker.sh -u
```

### Pre-Commit Checklist

- [ ] All unit tests pass (`./scripts/run-tests-docker.sh -u`)
- [ ] No reduction in code coverage
- [ ] Integration tests pass (if modified agent code)
- [ ] New code has corresponding tests
- [ ] Tests run in Docker (consistent environment)

### Debugging Failed Tests

**Local:**
```bash
# Run specific test with verbose output
pwsh -Command "Invoke-Pester -Path ./tests/unit/AcmeClient.Tests.ps1 -Output Detailed"
```

**Docker:**
```bash
# Run with verbose output
docker compose run --rm test-runner pwsh -Command "
    \$config = New-PesterConfiguration
    \$config.Run.Path = './tests/unit/AcmeClient.Tests.ps1'
    \$config.Output.Verbosity = 'Detailed'
    Invoke-Pester -Configuration \$config
"

# Interactive debugging session
docker compose run --rm test-runner pwsh
# Then inside container:
PS> Import-Module ./tests/unit/AcmeClient.Tests.ps1
PS> Invoke-Pester -Path ./tests/unit/AcmeClient.Tests.ps1 -Output Detailed
```

## Test Metrics

### Current Coverage

| Module | Coverage | Tests | Docker | Status |
|--------|----------|-------|--------|--------|
| AcmeClient.psm1 | >80% | 50+ | ✅ | ✅ |
| EstClient.psm1 | >80% | 40+ | ✅ | ✅ |
| BootstrapTokenManager.psm1 | >90% | 30+ | ✅ | ✅ |

### Test Execution Time

| Test Suite | Local | Docker | Notes |
|------------|-------|--------|-------|
| Unit Tests | ~30s | ~35s | Minimal overhead |
| Integration Tests | ~2min | ~2.5min | Includes startup |
| Full Suite | ~3min | ~3.5min | Including coverage |

## Troubleshooting

### "Docker image not found"

```bash
# Build the image
./scripts/run-tests-docker.sh -b

# Or manually
docker compose build test-runner
```

### "Tests fail in Docker but pass locally"

```bash
# Check mounted volumes
docker compose run --rm test-runner ls -la /workspace/tests/unit

# Run interactively to debug
docker compose run --rm test-runner pwsh
```

### "Cannot connect to PKI in integration tests"

```bash
# Ensure PKI is on same network
docker compose up -d pki

# Verify network connectivity
docker compose run --rm test-runner ping -c 3 pki

# Check PKI health from container
docker compose run --rm test-runner pwsh -Command "
    Invoke-RestMethod -Uri 'https://pki:9000/health' -SkipCertificateCheck
"
```

### "Coverage report not generated"

```bash
# Run with coverage flag
./scripts/run-tests-docker.sh -c

# Manually check
docker compose run --rm -e GENERATE_COVERAGE=true test-runner

# Verify file exists
ls -la tests/coverage.xml
```

## References

- **Pester Documentation**: https://pester.dev/docs/quick-start
- **PowerShell Testing Best Practices**: https://pester.dev/docs/usage/testdrive
- **Mocking Guide**: https://pester.dev/docs/usage/mocking
- **Docker Best Practices**: https://docs.docker.com/develop/dev-best-practices/

---

**Remember: If it's not tested, it's broken. If it doesn't run in Docker, it's not consistent.**
