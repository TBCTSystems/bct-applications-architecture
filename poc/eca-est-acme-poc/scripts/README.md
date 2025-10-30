# ECA Scripts

The `scripts/` directory provides cross-platform helpers for running the project test suite.

## Platform Support

- **`.sh` (Bash)** – Linux, macOS, and WSL
- **`.ps1` (PowerShell 7+)** – Native Windows

Pick the variant that matches your shell; both share the same behaviour and flags.

## run-tests.sh / run-tests.ps1

Unified entry point for the Pester-based unit and integration suites.

### Common Scenarios

```bash
# Run everything (unit + integration)
./scripts/run-tests.sh

# Unit tests only
./scripts/run-tests.sh -u

# Integration tests (auto-starts Docker services)
./scripts/run-tests.sh --auto-start-integration

# Generate coverage
./scripts/run-tests.sh --coverage
```

```powershell
pwsh -File scripts/run-tests.ps1            # All tests
pwsh -File scripts/run-tests.ps1 -UnitOnly  # Unit suite
pwsh -File scripts/run-tests.ps1 -IntegrationOnly -AutoStartIntegration
pwsh -File scripts/run-tests.ps1 -Coverage  # Coverage report
```

### Flags (both shells)

| Flag | Description |
|------|-------------|
| `-u`, `-UnitOnly` | Run only unit tests |
| `-i`, `-IntegrationOnly` | Run only integration tests |
| `--auto-start-integration`, `-AutoStartIntegration` | Start/stop required Docker services automatically |
| `-c`, `-Coverage` | Generate `tests/coverage.xml` |
| `-v`, `-Verbose` | Increase output verbosity |
| `-h`, `-Help` | Display usage information |

### Exit Codes

- `0` – All tests passed
- `1` – One or more tests failed
- `2` – Script error or missing dependency

Both scripts install Pester 5 on demand (current user scope) and expect the Docker daemon to be available when integration tests run.

## observability.sh / observability.ps1

Spin up and validate the Fluentd → Loki → Grafana observability stack.

```bash
./scripts/observability.sh demo      # Start stack, verify, generate sample data
./scripts/observability.sh verify    # Re-run health checks only
```

```powershell
pwsh -File scripts/observability.ps1 demo
pwsh -File scripts/observability.ps1 verify -Verbose
```

The scripts provision dashboards, confirm log ingestion via `verify-logging`, and print Grafana access details (`http://localhost:3000`, `admin` / `eca-admin`).
