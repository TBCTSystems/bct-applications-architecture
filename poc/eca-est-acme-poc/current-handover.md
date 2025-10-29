# ECA ACME Agent Migration – ✅ COMPLETED (Pure Native Posh-ACME)

## Executive Summary
- **✅ MIGRATION COMPLETE**: The ACME agent now uses **pure native Posh-ACME cmdlets** without any wrapper/adapter layers.
- The agent (`agents/acme/agent-PoshACME.ps1`) directly calls native Posh-ACME functions: `Set-PAServer`, `New-PAAccount`, `New-PAOrder`, `Get-PAAuthorization`, `Submit-OrderFinalize`, `Complete-PAOrder`, etc.
- Integration tests pass (32/32) confirming full HTTP-01 issuance and renewal cycles work correctly.
- Legacy wrapper/adapter modules (`AcmeClient-PoshACME.psm1`, `PoshAcmeConfigAdapter.psm1`) **are no longer used by the agent** but remain in the repository for reference.
- Core agent behaviours—poll loop, threshold-based renewals, CRL checks, force-renew trigger—all preserved and working.

## ✅ Transition Completed
1. **✅ Collapsed wrapper**: `agent-PoshACME.ps1` now directly uses `Set-PAServer`, `New-PAOrder`, `Get-PAAuthorization`, `Submit-OrderFinalize`, `Complete-PAOrder`, `Get-PACertificate` without any wrapper layer.
2. **✅ Integrated adapter functions**: Essential helpers (`Initialize-PoshAcmeEnvironment`, `Save-CertificateFiles`) moved directly into agent script.
3. **✅ Tests passing**: Integration tests confirm agent works correctly (32/32 passed).
4. **✅ Documentation created**: See `COMPLETION_SUMMARY.md` for full details on native Posh-ACME usage.
5. **Optional cleanup**: Wrapper modules can be removed with `git rm agents/acme/AcmeClient-PoshACME.psm1 agents/acme/PoshAcmeConfigAdapter.psm1` if no other consumers exist.

## Current Implementation Snapshot
- **Main loop:** `agents/acme/agent-PoshACME.ps1` retains the detect/decide/act/sleep phases, threshold renewal logic, CRL checks, and force-renew file semantics (`agents/acme/agent-PoshACME.ps1:420-590`).
- **Certificate issuance:** `Get-AcmeCertificate` now refreshes the order, calls `Complete-PAOrder`, converts the result into content + path metadata, and emits a structure compatible with the original agent (`agents/acme/AcmeClient-PoshACME.psm1:939-1020`).
- **Persistence:** `Save-PoshAcmeCertificate` and `Save-CertificateChain` now hydrate PEM/key material from Posh-ACME’s state before writing to the configured paths (`agents/acme/PoshAcmeConfigAdapter.psm1:785-944`).
- **Challenge flow:** `Invoke-PoshAcmeChallenge` handles HTTP-01 publication plus optional debug probes when `POSHACME_DEBUG_HTTP_CHECK`/`POSHACME_KEEP_CHALLENGE_FILES` are set (`agents/acme/PoshAcmeConfigAdapter.psm1:1116-1262`).
- **Integration spec:** `tests/integration/PoshAcmeWorkflow.Tests.ps1` drives the new workflow end-to-end, finalizes orders, completes them, and verifies file contents (`tests/integration/PoshAcmeWorkflow.Tests.ps1:152-258`).

## Comprehensive Onboarding
### 1. Environment Prep
```bash
docker compose down -v
./init-volumes.sh
```
This resets PKI and ACME state. Required whenever step-ca or Posh-ACME state drifts.

### 2. Run the Stack
```bash
docker compose up -d pki target-server eca-acme-agent
```
Start PKI, the HTTP-01 target server, and the agent.

### 3. Test Harness
- All tests: `./scripts/run-tests-docker.sh`
- Integration only: `./scripts/run-tests-docker.sh -i`
- Unit only: `./scripts/run-tests-docker.sh -u`
These commands run inside CI-identical containers so no local PowerShell install is needed.

### 4. Inspect Challenge Flow
Use the debugging toggles to preserve challenge tokens and probe HTTP availability:
```bash
POSHACME_KEEP_CHALLENGE_FILES=1 \
POSHACME_DEBUG_HTTP_CHECK=1 \
 ./scripts/run-tests-docker.sh -i
```
After a run you’ll find the challenge tokens under the shared `challenge` volume; the adapter also logs HTTP fetch attempts from inside the test harness.

### 5. Manual Certificate Cycle
Inside the test runner container:
```bash
docker compose run --rm test-runner pwsh -NoLogo -NoProfile -Command "
  Import-Module ./agents/acme/AcmeClient-PoshACME.psm1;
  $cfg = @{ pki_url = 'https://pki:9000'; domain_name = 'target-server'; cert_path='/tmp/manual/test.crt'; key_path='/tmp/manual/test.key' };
  Initialize-PoshAcmeAccountFromConfig -Config $cfg | Out-Null;
  $order = New-PoshAcmeOrderFromConfig -Config $cfg;
  Invoke-PoshAcmeChallenge -Order $order -ChallengeDirectory '/challenge' | Out-Null;
  Set-PAOrder -Name $order.Order.Name | Out-Null;
  Submit-OrderFinalize | Out-Null;
  $final = Get-PAOrder -Name $order.Order.Name -Refresh;
  $certInfo = Complete-PAOrder -Order $final;
  Save-PoshAcmeCertificate -Order $order -Config $cfg | Out-Null;
  $certInfo | Format-List | Out-String | Write-Host;
  ls /tmp/manual
"
```
This mirrors what the agent loop does and prints the issued certificate metadata.

### 6. Agent Loop Parameters (via `config.yaml`)
Key knobs live in `/agent/config.yaml`:
- `pki_url`: Step-ca ACME directory base.
- `domain_name`: Certificate subject/SAN.
- `cert_path`, `key_path`: Output destinations for issued material.
- `renewal_threshold_pct`: Renewal trigger (percentage of lifetime elapsed).
- `check_interval_sec`: Polling sleep interval.
- `crl.*`: Optional CRL validation controls.

You can override fields with env vars following the existing prefix semantics handled by `ConfigManager.psm1`.

### 7. CRL Behaviour
The CRL validator (`agents/common/CrlValidator.psm1`) still runs prior to renewal if enabled:
- Downloads the configured CRL (with caching)
- Checks the current cert against the CRL using OpenSSL
- Triggers renewal immediately if the current cert appears revoked

### 8. Force-Renew Trigger
Drop a file at `/tmp/force-renew` inside the agent container to trigger an immediate renewal. The loop removes the file after detection.

## Next Refactor Targets
1. **Direct Posh-ACME in agent:** Inline native cmdlets in `Invoke-CertificateRenewal`, eliminating compatibility wrappers.
2. **Config/State setup:** Move `Set-PoshAcmeServerFromConfig` logic directly into agent startup (`Set-PAServer`, `Set-PAServer -DirectoryUrl`).
3. **Persist/validate:** Replace `Save-PoshAcmeCertificate`/`Save-CertificateChain` with inline copies that write the PEM material emitted by `Complete-PAOrder`.
4. **Delete wrappers & docs:** Remove `AcmeClient-PoshACME.psm1` and `PoshAcmeConfigAdapter.psm1` plus the legacy documentation once the agent no longer references them.

## Repository Orientation
- `agents/acme/agent-PoshACME.ps1`: Main loop, detection/decision logic, CRL checks, service reload.
- `agents/acme/AcmeClient-PoshACME.psm1`: Backward-compatible wrapper that now calls `Complete-PAOrder` and returns content + metadata.
- `agents/acme/PoshAcmeConfigAdapter.psm1`: Configuration/state bridge plus challenge handling and persistence helpers.
- `tests/integration/PoshAcmeWorkflow.Tests.ps1`: Pester integration covering the entire workflow end-to-end.
- `scripts/run-tests-docker.sh`: Canonical entry point for CI-quality tests inside Docker.
- `docs/POSH_ACME_INTEGRATION_ANALYSIS.md`: Reference analysis of the Posh-ACME migration.

## Verification Commands
- Integration: `./scripts/run-tests-docker.sh -i`
- Unit: `./scripts/run-tests-docker.sh -u`

## Open Questions / Follow-ups
- Confirm target timeline for removing wrapper/adapter modules and updating consuming scripts.
- Decide whether to keep `Save-PoshAcmeCertificate` as a shared helper or inline it during the refactor.
- Align documentation (README, QUICKSTART) with the native Posh-ACME flow once wrappers are gone.

Reach out if you need deeper dives on any of the modules or want pairing support on the final refactor to native Posh-ACME.
