# ECA Testing Strategy

The Edge Certificate Agent (ECA) PoC ships with a streamlined, script-driven test harness built on Pester 5. Use it to validate agent behaviour, configuration parsing, and end-to-end certificate flows before cutting a release.

## Test Layers

1. **Unit tests** – Fast, deterministic coverage of PowerShell modules (`tests/unit`).
2. **Integration tests** – Exercise ACME and EST agents against the live Docker stack (`tests/integration`).
3. **CI workflow** – GitHub Actions executes the same commands on every push and pull request.

## Quick Start

### Bash / WSL / macOS

```bash
# Run all tests
./scripts/run-tests.sh

# Run only unit tests
./scripts/run-tests.sh -u

# Run integration tests (auto-starts required services)
./scripts/run-tests.sh --auto-start-integration

# Generate coverage
./scripts/run-tests.sh --coverage
```

### PowerShell 7+

```powershell
# Run all tests
pwsh -File scripts/run-tests.ps1

# Run only unit tests
pwsh -File scripts/run-tests.ps1 -UnitOnly

# Run integration tests (auto-starts required services)
pwsh -File scripts/run-tests.ps1 -IntegrationOnly -AutoStartIntegration

# Generate coverage
pwsh -File scripts/run-tests.ps1 -Coverage
```

### Docker Compose Test Runner

```bash
# Build the container image (one-time)
docker compose build test-runner

# Run all tests inside the container
docker compose run --rm test-runner

# Run a specific suite
docker compose run --rm test-runner pwsh -Command "Invoke-Pester -Path ./tests/unit"
```

> Use the Docker runner when you want parity with CI or prefer not to install PowerShell 7 locally.

## Directory Layout

```
tests/
├── unit/                 # Unit tests (fast, isolated)
│   ├── AcmeClient.Tests.ps1
│   ├── EstClient.Tests.ps1
│   ├── BootstrapTokenManager.Tests.ps1
│   └── ConfigManager.Tests.ps1
├── integration/          # Integration suites (require Docker services)
│   ├── AcmeWorkflow.Tests.ps1
│   └── EstWorkflow.Tests.ps1
├── fixtures/             # Mock certificates and protocol responses
└── Dockerfile            # Image for the docker compose test-runner profile
```

## Unit Tests

- Cover protocol clients, bootstrap token handling, configuration parsing, logging, and file operations.
- Execute with `./scripts/run-tests.sh -u` or `pwsh -File scripts/run-tests.ps1 -UnitOnly`.
- Scope coverage reports with `--coverage` / `-Coverage`; results are written to `tests/coverage.xml`.

## Integration Tests

- Validate real ACME renewals and EST enrollments using the Docker stack.
- Dependencies: `pki`, `openxpki-db`, `openxpki-server`, `openxpki-client`, `openxpki-web`, agents, and target workloads.
- Easiest path: `./scripts/run-tests.sh --auto-start-integration` (tears services down afterwards).
- Manual path: run `docker compose up -d pki openxpki-db openxpki-server openxpki-client openxpki-web eca-acme-agent eca-est-agent target-server target-client` and then `pwsh -File scripts/run-tests.ps1 -IntegrationOnly`.

## Continuous Integration

- `.github/workflows/test.yml` builds the repository, runs unit tests, executes integration tests, and publishes coverage artifacts when requested.
- Ensure new modules include unit coverage and negative-path assertions before merging.

## Troubleshooting

- **PowerShell not found:** Install PowerShell 7 (`pwsh`) on macOS/Linux (`brew install --cask powershell`) or Windows (MSI from Microsoft).
- **Docker daemon unavailable:** Start Docker Desktop/Engine before running integration tests or the compose runner.
- **Integration flakiness:** Confirm the PKI endpoints respond (`curl -k https://localhost:9000/health`, `curl -k https://localhost:8443/.well-known/est/cacerts`) and that challenge/certificate volumes are mounted.
- **Coverage file missing:** Only generated when the coverage flags are used.

Keep this document aligned with the scripts—if the CLI surface changes, update both the script help and this guide together.
