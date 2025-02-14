# Configure, Start, and Unseal Vault
This document walks you through configuring, starting and unsealing a vault container in production mode.
Make sure that the vault container is running.

## Pre-requisites
If you intend to enable TLS, make sure to [create certificates](../miscellaneous/self-signed-certs.md) first and update the cert paths in `vault.hcl`.

## Configure Vault
See [vault.hcl](../../devtools/vault/config/vault.hcl). It tell vault:
- `ui = true`: Lets you access the Vault UI (graphical interface).
- `disable_mlock = true`: Required in Docker or other environments where memory locking isn’t allowed by default.
- `listener "tcp"`: Configures the Vault server’s TCP listener on port 8200.
    - `address: 0.0.0.0:8200` tells Vault to listen on all interfaces in the container (mapped to port 8200 on your host).
    - `tls_cert_file` / `tls_key_file`: The server certificate & private key (from your self-signed certs).
    - `tls_client_ca_file`: Instructs Vault to request/verify client certificates signed by `ca.crt`. This is crucial for mTLS if you enable cert auth.
- `storage "file"`: Uses local disk storage at `/vault/file`. Fine for a PoC, but for production, consider a more robust backend.

## Start The Container
See [docker-compose.yaml](../../devtools/docker-compose.yaml):

- Mounting `vault.hcl`, `./certs`, and `./policies` into the container so Vault sees them at `/vault/config`.
- Exposing port `8200` on the host for Vault’s HTTPS endpoint.
- Using a named volume `vault-file` for Vault’s file storage.
- `VAULT_SKIP_VERIFY: true`: ⚠️ for demo purposes/development only, when self-signed certs are used.

Start the container:
```bash
docker compose up -d
```

## Initialize & Unseal
When running Vault in “production” mode, it starts off **sealed**. You need to initialize and then **unseal** it.

Open a shell inside the container:
```bash
docker exec -it vault sh
```

Initialize Vault:
```bash
vault operator init
```
> ⚠️ This command prints **5 unseal keys** and **1 initial root token**. Write them down securely.

**Unseal with 3 of those unseal keys:**
```bash
vault operator unseal
# Paste Key 1
vault operator unseal
# Paste Key 2
vault operator unseal
# Paste Key 3
```

After the 3rd key, you should see **`Sealed: false`**.

**Verify unseal:**
```bash
vault status
```

Expected output:
```plaintext
Sealed: false
Initialized: true
```

## Log in as `root`
Use the **root token** you got from `vault operator init`:

```bash
vault login
# Paste your root token
```

**Verification:**
```bash
vault token lookup
```

Expected output:
```plaintext
policies = [root]
```

After this, Vault is **running, unsealed**, and you can proceed to enable cert authentication, create policies, and manage secrets.
