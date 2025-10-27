# `init-volumes.sh` Execution Flow

This document traces the complete execution of `init-volumes.sh` and lists the actions and command-line utilities invoked at each stage. Use it to troubleshoot mismatched environments or to replicate the initialization flow manually.

---

## Overview

- Script location: `./init-volumes.sh`
- Purpose: initializes Docker volumes and configuration for the ECA PoC PKI (`step-ca`) and OpenXPKI EST server.
- Exit on error: `set -euo pipefail` aborts on any non-zero command, unset variable, or pipe error.

---

## Environment Requirements

| Requirement | Validation in Script | Notes |
|-------------|---------------------|-------|
| `step` CLI  | `command -v step`   | Must be installed on host. |
| Docker CLI  | `command -v docker` | Requires Docker Engine running locally. |
| Docker daemon | `docker info`    | Fails if daemon unavailable. |

---

## Execution Flow

### 0. Entry Point

- Registers trap: `trap 'log_error ...; cleanup; exit 1' INT TERM`
- Calls `main`, which orchestrates all subsequent steps.

### 1. Banner and Confirmation (`main`)

- Prints section banner via `log_section`.
- Invokes prerequisite check (see Step 2).
- Prints summary of operations.
- If stdin is a TTY, prompts user with `read -p "Continue? (y/N):"`.
- Sequentially calls the core functions:
  1. `initialize_pki`
  2. `create_pki_volume`
  3. `copy_pki_to_volume`
  4. `start_pki_for_provisioning`
  5. `wait_for_est_certificates`
  6. `initialize_openxpki`
  7. `initialize_openxpki_database`
  8. `import_certificates_to_openxpki`
- Runs `cleanup` and prints completion banner plus next-step guidance.

### 2. Prerequisite Validation (`check_prerequisites`)

| Action | Command(s) | Purpose |
|--------|------------|---------|
| Verify `step` CLI | `command -v step` | Ensures Smallstep CLI available; logs install instructions otherwise. |
| Verify Docker CLI | `command -v docker` | Confirms Docker CLI is present. |
| Verify Docker daemon | `docker info` | Validates engine connectivity; fails if daemon down. |

### 3. Initialize PKI Workspace (`initialize_pki`)

| Order | Action | Command(s) / Notes |
|-------|--------|---------------------|
| 1 | Announce section | `log_section` |
| 2 | Remove old temp dir | `rm -rf /tmp/eca-pki-init` (if exists) |
| 3 | Create temp dir | `mkdir -p /tmp/eca-pki-init` |
| 4 | Determine CA password | Uses `ECA_CA_PASSWORD`, `read -s -p`, or default `eca-poc-default-password` |
| 5 | Export step path | `export STEPPATH=/tmp/eca-pki-init` |
| 6 | Write password files | `printf '%s' ... > password.txt` and `provisioner_password.txt` |
| 7 | Initialize CA | `step ca init --name ... --dns ... --address ... --provisioner ... --password-file ... --provisioner-password-file ...` |
| 8 | Remove temp password files | `rm -f password.txt provisioner_password.txt` |
| 9 | Persist runtime password | `mkdir -p secrets`, `printf ... > secrets/password`, `chmod 600 secrets/password` |
|10 | Rewrite config paths | `sed -i "s|/tmp/eca-pki-init|/home/step|g" config/ca.json` and `config/defaults.json` |

### 4. Manage PKI Docker Volume (`create_pki_volume`)

- Check existing volume: `docker volume inspect pki-data`
- If present, prompt user (`read -p`). On confirmation: `docker volume rm pki-data`
- Create volume: `docker volume create pki-data`

### 5. Copy PKI Data to Volume (`copy_pki_to_volume`)

- Runs helper container:
  ```
  docker run --rm \
    -v pki-data:/home/step \
    -v /tmp/eca-pki-init:/source:ro \
    smallstep/step-ca:latest \
    sh -c "cp -r /source/* /home/step/ && chown -R step:step /home/step"
  ```
- Copies initialized PKI files with correct ownership.

### 6. Start PKI for Provisioning (`start_pki_for_provisioning`)

| Action | Command(s) | Notes |
|--------|------------|-------|
| Launch PKI service | `docker compose up -d pki` | Uses `docker-compose.yml` |
| Check health loop | `docker compose ps pki | grep -q "healthy"` | 30 attempts, 2s interval |

### 7. Wait for EST Certificates (`wait_for_est_certificates`)

- Polls certificate creation:
  - Command per iteration: `docker run --rm -v pki-data:/pki:ro alpine test -f /pki/est-certs/est-ca.pem`
  - Repeats 30 times with `sleep 2`.

### 8. Initialize OpenXPKI Config (`initialize_openxpki`)

| Order | Action | Command(s) |
|-------|--------|------------|
| 1 | Ensure config volume exists | `docker volume inspect openxpki-config-data`; create via `docker volume create` if missing |
| 2 | Copy base configuration | `docker run --rm -v openxpki-config-data:/config -v "$(pwd)/est-server/openxpki-setup/openxpki-config:/source:ro" alpine sh -c "cp -r /source/* /config/"` |
| 3 | Copy EST + Step CA certs/keys | `docker run --rm -v pki-data:/pki:ro -v openxpki-config-data:/config alpine sh -c "mkdir -p ... && cp /pki/est-certs/est-ca.* ... && cp /pki/certs/intermediate_ca.crt ... && cp /pki/certs/root_ca.crt ... && chmod ..."` |
| 4 | Prepare CA directories | `docker run --rm -v openxpki-config-data:/config alpine sh -c "mkdir -p ... && cp ... && chmod ..."` |

### 9. Provision OpenXPKI Web TLS (`provision_openxpki_web_tls`)

| Action | Command(s) | Purpose |
|--------|------------|---------|
| Request certificate from Step CA | `docker exec -i eca-pki bash -c "set -euo pipefail; mkdir -p /home/step/tmp; STEPPATH=/home/step step ca certificate openxpki-web /home/step/tmp/openxpki-web.crt /home/step/tmp/openxpki-web.key --provisioner admin --provisioner-password-file /home/step/secrets/password --ca-url https://localhost:9000 --root /home/step/certs/root_ca.crt --san openxpki-web --san localhost --force"` | Issues TLS key/cert for Apache |
| Install into config volume | `docker run --rm -v pki-data:/pki:ro -v openxpki-config-data:/config alpine sh -c "mkdir -p /config/tls/{private,endentity,chain} && cat /pki/tmp/openxpki-web.crt /pki/certs/intermediate_ca.crt > /config/tls/endentity/openxpki.crt && cp /pki/tmp/openxpki-web.key /config/tls/private/openxpki.pem && cp /pki/certs/intermediate_ca.crt /config/tls/chain/intermediate-ca.crt && cp /pki/certs/root_ca.crt /config/tls/chain/root-ca.crt && chmod ..."` | Installs leaf + intermediate bundle, private key, and CA chain |
| Remove temp files | `docker exec eca-pki rm -f /home/step/tmp/openxpki-web.crt /home/step/tmp/openxpki-web.key` | Cleans up temporary outputs |

### 10. Initialize OpenXPKI Database (`initialize_openxpki_database`)

| Action | Command(s) | Purpose |
|--------|------------|---------|
| Start database service | `docker compose up -d openxpki-db` | Launch MariaDB container |
| Wait for health | `docker compose ps openxpki-db | grep -q "healthy"` (loop) | Up to 30 attempts |
| Extract schema file | `docker run --rm -v openxpki-config-data:/config:ro alpine cat /config/contrib/sql/schema-mariadb.sql > /tmp/openxpki-schema.sql` | Copies schema to host |
| Import schema | `docker exec -i eca-openxpki-db mariadb -uopenxpki -popenxpki openxpki < /tmp/openxpki-schema.sql` | Loads schema into MariaDB |
| Cleanup | `rm -f /tmp/openxpki-schema.sql` | Removes temp file |

### 11. Import Certificates into OpenXPKI (`import_certificates_to_openxpki`)

| Order | Action | Command(s) / Notes |
|-------|--------|---------------------|
| 1 | Start OpenXPKI server | `docker compose up -d openxpki-server` |
| 2 | Verify health | `docker compose ps openxpki-server | grep -q "healthy"` |
| 3 | Import root CA | `docker exec eca-openxpki-server openxpkiadm certificate import --file /etc/openxpki/local/secrets/root-ca.crt --realm democa --force-no-chain` |
| 4 | Import Step CA intermediate | `docker exec eca-openxpki-server openxpkiadm certificate import --file /etc/openxpki/local/secrets/step-intermediate.crt --realm democa` |
| 5 | Import EST CA & alias | `docker exec eca-openxpki-server openxpkiadm alias --realm democa --token certsign --file /etc/openxpki/local/secrets/est-ca.crt --key /etc/openxpki/local/secrets/est-ca.key` |
| 6 | Fallback for key permissions (conditional) | `docker exec -u root ... cp`, `chown`, `chmod` |
| 7 | Generate bootstrap cert | `docker exec -i eca-pki bash -c "STEPPATH=/home/step step ca certificate ... --ca-url https://localhost:9000 --not-before 1m --not-after 23h --san bootstrap-client --force"`; script pauses briefly afterwards to let validity windows settle |
| 8 | Extract bootstrap leaf cert | `docker exec eca-openxpki-server sh -c "sed -n ... > /tmp/bootstrap-only.pem"` |
| 9 | Import bootstrap cert | `docker exec eca-openxpki-server openxpkiadm certificate import --file /tmp/bootstrap-only.pem --realm democa`; temp file is removed after import |

### 12. Cleanup (`cleanup`)

- Remove temporary PKI directory if it still exists: `rm -rf /tmp/eca-pki-init`
- Logs completion message.

---

## Timing and Control Notes

- Health checks (`docker compose ps ... | grep -q "healthy"`) run up to 30 iterations with 2-second sleeps (~60 seconds total).
- Certificate wait loop similarly attempts 30 times.
- Any command returning non-zero status aborts the script due to `set -e`.
- Interactive prompts only run when the script has a TTY; otherwise defaults are used automatically.

---

## Post-Initialization Guidance

After successful execution the script prints next steps:

| Task | Command |
|------|---------|
| Start all services | `docker compose up -d` |
| Health check PKI | `curl -k https://localhost:9000/health` |
| OpenXPKI UI | `http://localhost:8080` or `https://localhost:8443` |
| Grafana | `http://localhost:3000` (credentials `admin/eca-admin`) |
| Run integration tests | `./scripts/run-tests.sh` |
