# Secure OpenBao with mTLS and .NET Certificate Authentication

This guide walks you through setting up a local OpenBao instance (in “production” mode) with **TLS** and **client certificate authentication**, then consuming secrets from a minimal **.NET** app **without** storing any OpenBao token in the code or environment variables.

We create Server CA and client CA to sign server and client certificates to see how OpenBao can do **mTLS** (mutual TLS).

---
## Table of Contents
1. [Introduction](#1-introduction)
2. [Directory Structure](#2-directory-structure)
3. [Generate TLS Certificates](#3-generate-tls-certificates)
4. [Prepare OpenBao Configuration](#4-prepare-openbao-configuration)
5. [Start OpenBao & Unseal](#5-start-openbao--unseal)
6. [Enable Cert Auth & Create Policy](#6-enable-cert-auth--create-policy)
7. [Run Console App](#run-the-demo)


---

## 1. Introduction
- **Why TLS?** OpenBao deals with sensitive data (secrets); enabling HTTPS ensures data in transit is encrypted.
- **Why mutual TLS (mTLS)?** With certificate-based authentication, the client presents a certificate to OpenBao. OpenBao can recognize it (via its own CA) and issue a token without environment variables or code-stored tokens.
- **Why “production” mode OpenBao?** In dev mode, OpenBao auto-unseals and uses HTTP by default, which isn’t secure. Production mode demonstrates a more realistic setup.

---

## 2. Directory Structure

Beside **`src/`** for the .NET demo app, We’ll create a base `bao/` folder containing `certs/`, `config/` and `myapp-policy.hcl` . 
- **`certs/`**: store working CAs, keys, certs for use. The files in this folder are for reference only. You should create your own certs per the [instruction](#generate-server-certificate).
- **`config/`**: `config.hcl` is OpenBao configuration file.
- **`myapp-policy.hcl`**: policy file granting .NET app access to secrets.
- **`src/`**: a console app for demo only. It store a secret in OpenBao and retrieve it.

```plaintext
└── src/                      (a .NET demo app)
└── bao/                      (OpenBao config and certs in one place)
    ├── certs/                (store CA, server cert, client cert, etc.)
    ├── config/
        ├── config.hcl        (OpenBao configuration)
    └── myapp-policy.hcl      (Policy file granting .NET app access to secrets)
    └── docker-compose.yaml
```

This is just to organize your OpenBao config and certs in one place.

---

## 3. Generate TLS Certificates

### Create a Server Certificate Authority (CA)
In PowerShell, navigate to a directory (e.g., `\bao\certs`).

```powershell
openssl req -newkey rsa:2048 -nodes -keyout ca.key -x509 -days 365 -out ca.crt -subj "/CN=OpenBao CA"
```

### Generate Server Certificate
1. Create a CSR Configuration File (openssl.cnf):

```ini
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name

[req_distinguished_name]
CN = OpenBao Server

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost   # Replace with your domain
IP.1 = 127.0.0.1          # Replace with your server IP
``` 

2. Generate Server Key and CSR:

```powershell
openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr \
  -subj "/CN=OpenBao Server" -config openssl.cnf
```

3. Sign the CSR with the CA:

```powershell
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out server.crt -days 365 -extensions v3_req -extfile openssl.cnf
```

### Create a Client Certificate Authority (CA)
In PowerShell, navigate to a directory (e.g., `\bao\certs`).

```powershell
# Generate Client CA
openssl req -newkey rsa:2048 -nodes -keyout client-ca.key -x509 -days 365 -out client-ca.crt -subj "/CN=OpenBao Client CA"
```

### Create a Client Certificate
1. Generate Client Key and CSR:

```powershell
openssl req -newkey rsa:2048 -nodes -keyout client.key -out client.csr -subj "/CN=openbao-client"
```
2. Sign Client CSR with Client CA:

```powershell
openssl x509 -req -in client.csr -CA client-ca.crt -CAkey client-ca.key -CAcreateserial -out client.crt -days 365
```

3. Create a PFX for .NET
Windows SChannel often prefers PFX certificates (containing both the certificate and private key) instead of separate PEM files. Use OpenSSL to convert your client certificate and key to PFX:

```powershell
openssl pkcs12 -export -inkey C:\OpenBao\certs\client.key -in C:\OpenBao\certs\client.crt -out C:\OpenBao\certs\client.pfx -passout pass:
```

(Note: Leaving `-passout pass:` blank sets no password. Or replace with a real pass, e.g. `-passout pass:pfxpwd`.)

This creates a client.pfx file in C:\OpenBao\certs. 

## 4. Prepare OpenBao Configuration
1. Create a configuration file (`\bao\config\config.hcl`). This file tells OpenBao:
- **Where to listen** and how to serve TLS.
- **Where to store** its data (in our case, the local file system).

Use the following example:

```hcl

storage "file" {
  path = "/bao/data"   # Directory where OpenBao will store its data
}

listener "tcp" {
  address                            = "0.0.0.0:8200"             # Listen on all interfaces inside Docker
  tls_cert_file                      = "/bao/certs/server.crt"    # Path to the OpenBao server's TLS certificate
  tls_key_file                       = "/bao/certs/server.key"    # Path to the OpenBao server's TLS private key
  tls_disable                        = false
  tls_require_and_verify_client_cert = true                       # Enable mTLS
  tls_client_ca_file                 = "/bao/certs/client-ca.crt" # Trust this CA for client certs (mTLS)
}
```

### Explanation:
- `listener "tcp"`: Configures the OpenBao server’s TCP listener on port 8200.
    - `address: 0.0.0.0:8200` tells OpenBao to listen on all interfaces in the container (mapped to port 8200 on your host).
    - `tls_cert_file` / `tls_key_file`: The server certificate & private key (from your self-signed certs).
    - `tls_client_ca_file`: Instructs OpenBao to request/verify client certificates signed by `client-ca.crt`. This is crucial for mTLS if you enable cert auth.
- `storage "file"`: Uses local disk storage at `/bao/data`. Fine for a PoC, but for production, consider a more robust backend.


## 5. Start OpenBao & Unseal

### 5.1 Navigate to the folder containing `docker-compose.yaml`. Launch bao in the background:

```bash
docker compose up -d
```

Check logs (optional):

```bash
docker compose logs -f
```

You should see something like:

```plaintext
==> OpenBao server started! Log data will stream in below:
...
```

> ⚠️ If you see TLS handshake errors referencing an unknown certificate, it’s often due to connections not trusting your self-signed CA. As long as OpenBao is up, you can proceed.

---

### 5.2 Initialize & Unseal
When running OpenBao in “production” mode, it starts off **sealed**. You need to initialize and then **unseal** it.

**Open a shell inside the container:**
```bash
docker exec -it bao sh
```

**Set environment variables so the Vault CLI can connect via HTTPS with your self-signed CA:**
```bash
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_CACERT="/bao/config/certs/ca.crt"
```

**Initialize OpenBao:**
```bash
bao operator init
```
> ⚠️ This command prints **5 unseal keys** and **1 initial root token**. Write them down securely. This is important!

**Unseal with 3 of those unseal keys:**
```bash
bao operator unseal
# Paste Key 1
bao operator unseal
# Paste Key 2
bao operator unseal
# Paste Key 3
```

After the 3rd key, you should see **`Sealed: false`**.

**Verify unseal:**
```bash
bao status
```

Expected output:
```plaintext
Sealed: false
Initialized: true
...
```

---

### 5.3 Log in as Root
Use the **root token** you got from `bao operator init`:

```bash
bao login
# Paste your root token
```

**Verification:**
```bash
bao token lookup
```

Expected output:
```plaintext
policies = [root]
```

After this, OpenBao is **running, unsealed**, and you can proceed to enable cert authentication, create policies, and manage secrets.


---

## 6. Enable Cert Auth & Create Policy

Before proceeding, ensure you are **logged in** to OpenBao (with the root token or a token that can manage auth methods/policies):
```bash
bao token lookup
````

You should see `policies  [root]` indicating you have full privileges. If not, run:
```bash
bao login
```

### 6.1 Enable Certificate Authentication

```bash
bao auth enable cert
```

**Verification:**
```bash
bao auth list
```
Expected output should include:
```plaintext
path                    type    ...
----                    ----
cert/                   cert    ...
```
indicating that the "cert" auth method is enabled at `auth/cert/`.


### 6.2 Apply Policy `myapp-policy`

A policy `myapp-policy.hcl` with the following content was pre-created in the `/bao` directory (If the file does not exist in the `/bao` directory, you need to copy it to docker.):
```hcl
path "secret/data/myapp/*" {
  capabilities = ["create", "update", "read", "delete", "list"]
}
```

This policy grants the ability to read and write any secrets stored at `secret/data/myapp/*`.

Apply the policy:
```bash
bao policy write myapp-policy /bao/myapp-policy.hcl
```

**Verification:**
```bash
bao policy list
```
Should now list `myapp-policy` among the policies.

### 6.3 Register the Client Certificate for Cert Auth
To authenticate the .NET app via cert auth using (`client.crt`), register it so OpenBao knows which policy to assign:

```bash
bao write auth/cert/certs/myapp-cert \
  display_name="demo app" \
  policies="myapp-policy" \
  certificate=@/bao/certs/client.crt \
  ttl=1h
```

Any client connecting with a cert matching `client.crt` (and signed by your CA) will automatically get a token with `myapp-policy` for 1 hour.

**Verification:**
```bash
  bao read auth/cert/certs/myapp-cert
```
You should see a JSON response with details of the certificate name and policy mapping.

### Enable the KV (Key-Value) secrets engine for storing secrets:

```bash
  bao secrets enable -path=secret kv-v2
```

## Run the demo

**Set client certificate**  
Navigate to the `src` folder, then `Set client certificate`:

```powershell
$env:CLIENT_CERT_PATH = "..\bao\certs\client.pfx" 
```
Note: in case the client.pfx was created with a password, the password (e.g. `pfxpassword`) also need to be set:
```powershell
$env:CLIENT_CERT_PASSWORD = "pfxpassword"
```

**The app will securely store a key/value pair to OpenBao and retrieve it:**
```powershell
dotnet run
```

Expected output:
```plaintext
Secret stored successfully!
Retrieved secret value: MySupersecret123!
```