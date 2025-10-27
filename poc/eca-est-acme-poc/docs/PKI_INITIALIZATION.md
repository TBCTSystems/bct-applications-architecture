# PKI Initialization Guide

## Overview

The ECA PoC uses smallstep's `step-ca` as the Certificate Authority. Due to limitations in running `step ca init` non-interactively in Docker (TTY allocation issues), the CA must be initialized on the host machine before starting the Docker containers.

## Problem Background

The `step ca init` command has interactive password prompts that cannot be fully suppressed in a Docker environment:
- Even with `--password-file` flags, it attempts to display the provisioner password
- This requires `/dev/tty` which is not available in non-interactive Docker containers
- Multiple workarounds were attempted (DOCKER_STEPCA_INIT_* vars, stdin piping, context clearing) but all failed

**Solution**: Initialize the CA on the host where TTY is available, then copy the initialized PKI data into the Docker volume.

## Prerequisites

### 1. Install step CLI on Host

The `step` CLI tool must be installed on your host machine (not in Docker).

**Linux (Debian/Ubuntu)**:
```bash
wget https://dl.smallstep.com/cli/docs-ca-install/latest/step-cli_amd64.deb
sudo dpkg -i step-cli_amd64.deb
```

**macOS**:
```bash
brew install step
```

**Other platforms**: See [official installation guide](https://smallstep.com/docs/step-cli/installation)

### 2. Verify Installation

```bash
step version
```

You should see output like:
```
Smallstep CLI/0.25.0 (linux/amd64)
Release Date: 2024-01-15
```

## Initialization Procedure

### Automated Method (Recommended)

We provide a script that handles the entire initialization process:

```bash
cd poc
./pki/init-pki-volume.sh
```

The script will:
1. Check prerequisites (step CLI, Docker)
2. Initialize the CA on your host in `/tmp/eca-pki-init`
3. Create the Docker volume `pki-data`
4. Copy the initialized PKI files to the volume
5. Clean up temporary files
6. Display next steps

**Important**: When prompted for passwords, press Enter for empty passwords (this is a PoC environment).

### Manual Method

If you prefer to do it manually:

#### Step 1: Initialize CA on Host

```bash
# Create temporary directory
export STEPPATH="/tmp/eca-pki-init"
mkdir -p "$STEPPATH"

# Create password files (empty for PoC)
echo "" > "$STEPPATH/password.txt"
echo "" > "$STEPPATH/provisioner_password.txt"

# Initialize CA
step ca init \
    --name="ECA-PoC-CA" \
    --dns="pki,localhost" \
    --address=":9000" \
    --provisioner="admin" \
    --password-file="$STEPPATH/password.txt" \
    --provisioner-password-file="$STEPPATH/provisioner_password.txt"

# Create runtime password file
mkdir -p "$STEPPATH/secrets"
echo "" > "$STEPPATH/secrets/password"
chmod 600 "$STEPPATH/secrets/password"
```

#### Step 2: Create Docker Volume

```bash
# Remove existing volume if it exists
docker volume rm pki-data 2>/dev/null || true

# Create new volume
docker volume create pki-data
```

#### Step 3: Copy PKI Data to Volume

```bash
docker run --rm \
    -v pki-data:/home/step \
    -v /tmp/eca-pki-init:/source:ro \
    smallstep/step-ca:latest \
    sh -c "cp -r /source/* /home/step/ && chown -R step:step /home/step"
```

#### Step 4: Cleanup

```bash
rm -rf /tmp/eca-pki-init
```

## Starting the PoC

After initialization, start the services:

```bash
# Start PKI service
docker compose up -d pki

# Wait for it to be healthy
docker compose ps

# Check logs
docker logs eca-pki

# Verify health endpoint
curl -k https://localhost:9000/health
```

Expected response:
```json
{"status":"ok"}
```

## Configure Provisioners

After the PKI service is running, configure ACME and EST provisioners:

```bash
docker exec eca-pki /usr/local/bin/configure-provisioners.sh
```

This will:
- Add an ACME provisioner for HTTP-01 challenges
- Add an EST provisioner with bootstrap token generation
- Generate and store the EST bootstrap token

## Start Remaining Services

```bash
docker compose up -d
```

## Verification

### Check All Services

```bash
docker compose ps
```

All services should show "Up" and "healthy".

### Test ACME Agent

```bash
docker logs eca-acme-agent
```

Look for successful certificate requests.

### Test EST Agent

```bash
docker logs eca-est-agent
```

Look for successful enrollment.

### Test Target Server

```bash
curl -k https://localhost:443
```

Should return the NGINX welcome page served over HTTPS with an ACME-issued certificate.

## Troubleshooting

### "step: command not found"

Install the step CLI on your host (see Prerequisites).

### "Volume already exists"

The initialization script will prompt you to remove it. Alternatively:
```bash
docker compose down -v
docker volume rm pki-data
```

### "Permission denied" when copying to volume

Make sure Docker is running and you have permissions:
```bash
docker info
```

### CA fails to start after initialization

Check the password file exists:
```bash
docker run --rm -v pki-data:/home/step smallstep/step-ca:latest \
    ls -la /home/step/secrets/password
```

### Reinitializing from scratch

```bash
# Stop all services
docker compose down -v

# Remove the volume
docker volume rm pki-data

# Re-run initialization
./pki/init-pki-volume.sh

# Start services
docker compose up -d
```

## File Structure in Volume

After initialization, the `pki-data` volume contains:

```
/home/step/
├── config/
│   ├── ca.json              # Main CA configuration
│   ├── defaults.json        # CLI defaults
│   └── provisioners.json    # Provisioner configurations (added later)
├── certs/
│   ├── root_ca.crt          # Root CA certificate
│   └── intermediate_ca.crt  # Intermediate CA certificate
├── secrets/
│   ├── root_ca_key          # Root CA private key (encrypted)
│   ├── intermediate_ca_key  # Intermediate CA private key (encrypted)
│   └── password             # Password file for key decryption
└── db/                      # BadgerDB database for issued certificates
```

## Security Notes

⚠️ **This is a Proof-of-Concept configuration**:
- Empty passwords are used for simplicity
- Self-signed certificates are acceptable
- No production-grade security hardening

For production deployments:
- Use strong passwords for CA keys
- Store passwords securely (Docker secrets, HashiCorp Vault, etc.)
- Implement proper backup and disaster recovery
- Follow smallstep's production deployment guide
- Use Hardware Security Modules (HSMs) for key storage

## References

- [smallstep Documentation](https://smallstep.com/docs/step-ca)
- [step CLI Installation](https://smallstep.com/docs/step-cli/installation)
- [step-ca Docker Image](https://hub.docker.com/r/smallstep/step-ca)
- [ECA PoC Architecture](./ARCHITECTURE.md)
