# ECA ACME Agent Migration – Handover Notes

## Project Snapshot
- **Goal**: Replace the PoC’s bespoke ACME agent with Posh-ACME while preserving the existing configuration contract, Docker topology, and operational workflow.
- **Scope**: ACME PowerShell modules, Docker image, test harness, docs, and the PKI + OpenXPKI bootstrap that underpins the PoC (`init-volumes.sh`).
- **Current Branch State**: Wrapper + adapter modules (`agents/acme/AcmeClient-PoshACME.psm1`, `agents/acme/PoshAcmeConfigAdapter.psm1`) are wired into the agent, Docker services mount a shared `challenge` volume, and the new unit/integration suites are runnable through `scripts/run-tests-docker.sh`. HTTP-01 validation now completes inside the harness.
- **Primary Blocker**: Certificate retrieval still fails. `Get-PACertificate` returns `$null`, so `Get-AcmeCertificate` (`agents/acme/AcmeClient-PoshACME.psm1:939`) never emits artifacts and the integration suite cannot find any generated cert/key files.

## Repository Orientation
- `agents/acme/AcmeClient-PoshACME.psm1`: Backward-compatible wrapper over Posh-ACME. Handles account/order orchestration and exposes the legacy surface area.
- `agents/acme/PoshAcmeConfigAdapter.psm1`: Configuration bridge. Maps YAML/env settings to Posh-ACME (`Set-PoshAcmeServerFromConfig`, `Invoke-PoshAcmeChallenge`, etc.).
- `docker-compose.yml`: Full PoC stack (PKI, target HTTP-01 host, agents, observability, and `test-runner` profile) with shared volumes (`challenge`, `posh-acme-state`, certificate dirs).
- `scripts/run-tests-docker.sh`: Canonical entry point for unit/integration testing inside Docker.
- `tests/integration/PoshAcmeWorkflow.Tests.ps1`: Pester coverage for the new flow, including HTTP-01 challenge and certificate persistence.
- Docs & roadmap: `docs/POSH_ACME_*`, `posh-acme-roadmap.md`, `POSH_ACME_EPIC1_COMPLETION.md` capture design analysis and progress.

## Environment & Bootstrap Checklist
1. **Full reset** (needed any time PKI/Posh-ACME state drifts):
   ```bash
   docker compose down -v
   ./init-volumes.sh            # safe defaults for local dev
   ```
2. **Start targeted ACME services**:
   ```bash
   docker compose up -d pki target-server
   ```
3. **Run tests inside Docker** (host `pwsh` lacks dependencies):
   ```bash
   ./scripts/run-tests-docker.sh              # unit + integration
   ./scripts/run-tests-docker.sh -i           # integration only
   ./scripts/run-tests-docker.sh -u           # unit only
   ```

## Status – 2025-10-28
- ✅ `POSHACME_HOME` management is in place; Docker mounts `/posh-acme-state` and adapters respect it.
- ✅ HTTP-01 challenge path is functional; `Invoke-PoshAcmeChallenge` publishes tokens and Pester challenge tests pass.
- ✅ Unit suite is green in the Docker harness.
- ⚠️ **Integration suite**: 8 failures remain in the “Certificate Retrieval and Chain Management” context (`tests/integration/PoshAcmeWorkflow.Tests.ps1:187-238`). `Get-PACertificate` returns `$null`, leaving all filesystem assertions to fail.
- ⚠️ Until certificate retrieval works, `agent-PoshACME.ps1` cannot complete a renewal cycle, so rollout stays blocked.

## Latest Validation Run
- Command: 
  ```bash
  ./scripts/run-tests-docker.sh -i
  ```
- Timestamp: 2025-10-29 00:24 UTC.
- Result: `Tests Passed: 24, Failed: 8, Skipped: 1` (focus area: certificate retrieval).
- Representative failure signatures:
  - `Get-PACertificate` returned `$null` (`tests/integration/PoshAcmeWorkflow.Tests.ps1:193`), causing `Should -Not -Throw` to fail.
  - Chain checks (`tests/integration/PoshAcmeWorkflow.Tests.ps1:198`) and `Test-Path` assertions for `/tmp/eca-poshacme-integration-test-*/test.crt` (`tests/integration/PoshAcmeWorkflow.Tests.ps1:222`) fail because no files are written.
  - `Save-CertificateChain` receives a `$null` cert info object, so downstream persistence is never exercised.

## Investigation Notes
- The certificate pipeline currently stops at `Get-AcmeCertificate` (`agents/acme/AcmeClient-PoshACME.psm1:939-978`). `Submit-OrderFinalize` is invoked, but the subsequent `Get-PACertificate -Name $orderName` returns nothing. Confirm the selected order name matches the state populated by Posh-ACME.
- Validate that `Submit-OrderFinalize` is running in the same scope as the order whose CSR was generated. Logging the order status (`Get-PAOrder -Refresh | Format-List status,certificate`) immediately before the `Get-PACertificate` call will show whether the finalize step ever attaches a certificate URL.
- Inspect `/posh-acme-state` inside the `test-runner` container to see if `certs/` folders are created. If files exist there, the issue is in our wrapper; if not, the finalize/CSR flow is breaking earlier.
- Manual repro snippet (inside Docker):
  ```bash
  docker compose run --rm test-runner pwsh -NoLogo -NoProfile -Command "
    Import-Module ./agents/acme/AcmeClient-PoshACME.psm1;
    $cfg = @{ pki_url = 'https://pki:9000'; domain_name = 'target-server' };
    Initialize-PoshAcmeAccountFromConfig -Config $cfg | Out-Null;
    $order = New-PoshAcmeOrderFromConfig -Config $cfg;
    Invoke-PoshAcmeChallenge -Order $order -ChallengeDirectory '/challenge' | Out-Null;
    Get-PAOrder -Refresh | Format-List status,certificate"
  ```
  Extend this to call `Submit-OrderFinalize` and `Get-PACertificate -Name $order.Order.Name` to observe the failure path.
- Double-check `Save-CertificateChain` (`agents/acme/PoshAcmeConfigAdapter.psm1`) once a non-null `PACertificate` is available; it expects populated `.CertFile`, `.ChainFile`, `.FullChainFile`, and `.KeyFile`.
- For deeper HTTP-01 debugging you can now set `POSHACME_DEBUG_HTTP_CHECK=1` to have the adapter probe `http://target-server/.well-known/acme-challenge/<token>` from inside the runner, and `POSHACME_KEEP_CHALLENGE_FILES=1` to skip cleanup after a run.

## Remaining Work
1. **Unblock certificate retrieval**: Diagnose why `Get-PACertificate` returns `$null` and fix the finalize/export flow. Re-run `./scripts/run-tests-docker.sh -i` until the “Certificate Retrieval and Chain Management” context is green.
2. **Roadmap hygiene**: When the above is resolved, update `posh-acme-roadmap.md` Story 2.1/2.2 checkboxes to reflect the completed migration.
3. **Documentation refresh**: Align `README.md`, `QUICKSTART.md`, and `docs/POSH_ACME_*` with the new testing/bootstrap workflow.
4. **Cleanup**: Retire or update legacy scripts (e.g., `test-posh-acme*.ps1`) so the repo only advertises the new path.

## Helpful References
- Posh-ACME API docs: https://poshac.me (function semantics, especially `Submit-OrderFinalize` and `Get-PACertificate`).
- Step-CA HTTP-01 behaviour: https://smallstep.com/docs/step-ca.
- Internal design notes: `docs/POSH_ACME_INTEGRATION_ANALYSIS.md`, `docs/POSH_ACME_CONFIGURATION_MAPPING.md`, `POSH_ACME_EPIC1_COMPLETION.md`.

Reach out if you need deeper context from earlier experiments—the Docker test logs contain verbatim error messages for the failing steps.
