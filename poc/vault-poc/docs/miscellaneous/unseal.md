# Start and Unseal Vault
This document walks you through starting and unsealing a vault container in production mode.
Make sure that the vault container is running.

## Initialize & Unseal
When running Vault in “production” mode, it starts off **sealed**. You need to initialize and then **unseal** it.

**Open a shell inside the container:**
```bash
docker exec -it vault sh
```

**Set environment variables so the Vault CLI can connect via HTTPS with your self-signed CA:**
```bash
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_CACERT="/vault/config/certs/ca.crt"
```

**Initialize Vault:**
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
...
```

---

## Log in as Root
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

---
