# Secure HashiCorp Vault with Self-Signed TLS and .NET Certificate Authentication

This guide walks you through setting up a local HashiCorp Vault instance (in “production” mode) with **TLS** and **client certificate authentication**, then consuming secrets from a minimal **.NET** app **without** storing any Vault token in the code or environment variables.

In production, you’d use valid certificates (signed by a known CA) and possibly more sophisticated policies. But for a **proof-of-concept**, we’ll create a **self-signed** CA and see how Vault can do **mTLS** (mutual TLS).

---
## Table of Contents
1. [Introduction](#1-introduction)
2. [Directory Structure](#2-directory-structure)
3. [Create Project Folders](#3-create-project-folders)
4. [Generate Certificates (Self-Signed)](#4-generate-certificates-self-signed)
5. [Prepare the Vault Configuration](#5-prepare-the-vault-configuration)
6. [Start Vault & Unseal](#6-start-vault--unseal)
7. [Enable Cert Auth & Create Policy](#7-enable-cert-auth--create-policy)
8. [Store a Test Secret](#8-store-a-test-secret)
9. [Minimal .NET 9 Console App](#9-minimal-net-9-console-app)


---

## 1. Introduction
- **Why TLS?** Vault deals with sensitive data (secrets); enabling HTTPS ensures data in transit is encrypted.
- **Why mutual TLS (mTLS)?** With certificate-based authentication, the client presents a certificate to Vault. Vault can recognize it (via its own CA) and issue a token without environment variables or code-stored tokens.
- **Why “production” mode Vault?** In dev mode, Vault auto-unseals and uses HTTP by default, which isn’t secure. Production mode demonstrates a more realistic setup.

---

## 2. Directory Structure

We’ll create a base `vault/` folder containing `config/`. Inside `config/`, we’ll store:
- Our **certs** subdirectory (for keys, certs).
- A **`vault.hcl`** (Vault configuration file).
- A **`docker-compose.yaml`** (to run Vault).

Finally, we’ll have a separate folder for our .NET 9 console app if desired.

**Initial Folder Layout (empty placeholders)**:
```plaintext
└── config/
    ├── certs/                (will store CA, server cert, client cert, etc.)
    ├── vault.hcl             (Vault configuration)
    ├── docker-compose.yaml    (Docker Compose for Vault)
    └── dotnet-policy.hcl      (Policy file granting .NET app access to secrets)
```

We’ll fill these in as we go.

---

## 3. Create Project Folders

Create the skeleton with empty folders:
```bash
mkdir -p vault/config/certs
touch vault/config/vault.hcl
touch vault/config/dotnet-policy.hcl
touch vault/config/docker-compose.yaml
```
Verification:
```bash
tree vault
vault
└── config
    ├── certs
    ├── docker-compose.yaml
    ├── dotnet-policy.hcl
    └── vault.hcl
```

This is just to organize your Vault config and certs in one place.

---

## 4. Generate Certificates (Self-Signed)

> ⚠️ This is only required if you don’t have real certificates from a trusted CA. In production, you’d get a valid certificate so users don’t have to manually trust your CA.

### 4.1 Generate a CA private key
```bash
openssl genrsa -out ca.key 2048
```
Verification:
```bash
ls
ca.key
```

### 4.2 Create a Root CA
```bash
openssl req -x509 -new -nodes -key ca.key -sha256 -days 365 -out ca.crt -subj "/C=US/ST=MyState/L=MyCity/O=MyOrg/OU=DevOps/CN=MyRootCA"
```
Verification:
```bash
ls
ca.crt  ca.key
```

### 4.3 Create Vault Server Certificate

Generate a private key for Vault:

```bash
openssl genrsa -out vault.key 2048
```

Manually create a file named `vault.ext` with the following content:
```
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
IP.1 = 127.0.0.1
```

This ensures the server certificate is valid for connections to `localhost` or `127.0.0.1`.

Create a CSR:
```bash
openssl req -new -key vault.key \
  -out vault.csr \
  -subj "/C=US/ST=MyState/L=MyCity/O=MyOrg/OU=Server/CN=localhost"
```

Sign the server cert:
```bash
openssl x509 -req -in vault.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out vault.crt -days 365 -sha256 \
  -extfile vault.ext
```

Verification:

```bash
ls
```

Expected files:
```
ca.crt   ca.key   ca.srl
vault.key   vault.csr   vault.crt   vault.ext
```

### 4.4 Create a Client Certificate (for .NET)

As the goal is to authenticate the .NET app to Vault with cert-based auth, you need a client certificate signed by the same CA.

Generate a private key for the client:
```bash
openssl genrsa -out client.key 2048
```

Create a CSR (Common Name = dotnet-client):
```bash
openssl req -new -key client.key \
  -out client.csr \
  -subj "/C=US/ST=MyState/L=MyCity/O=MyOrg/OU=Client/CN=dotnet-client"
```

Manually create a file named `client.ext` with:
```ini
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
```

Explanation: This indicates the certificate is intended for client authentication (`extendedKeyUsage = clientAuth`).

Sign the client certificate using your CA:
```bash
openssl x509 -req -in client.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out client.crt -days 365 -sha256 \
  -extfile client.ext
```

Verification:
```bash
ls | grep client
```
Expected new files related to the client:
```
client.key   client.csr   client.crt   client.ext
```

#### 4.4.1 Create a PFX for .NET

If your .NET app prefers a .pfx or .p12 file:
```bash
openssl pkcs12 -export \
  -out client.pfx \
  -inkey client.key \
  -in client.crt \
  -certfile ca.crt \
  -passout pass:
```
(Leaving `-passout pass:` blank sets no password. Or replace with a real pass, e.g. `-passout pass:changeit`.)

Verification:
```bash
ls | grep client
```
```
client.key   client.csr   client.crt   client.ext   client.pfx
```

`.pfx` files bundle the client certificate and private key in one password-protected file that’s easy for .NET to load.

## 5. Prepare the Vault Configuration

Create a file named `vault.hcl` in `vault/config/`. This file tells Vault:
- **Where to listen** and how to serve TLS.
- **Where to store** its data (in our case, the local file system).

Use the following example:

```hcl
ui = true                 # Enables Vault's built-in UI at https://localhost:8200/ui
disable_mlock = true      # Allow Vault to run without mlock. Usually needed in containers.

listener "tcp" {
  address             = "0.0.0.0:8200"                  # Listen on all interfaces inside Docker
  tls_cert_file       = "/vault/config/certs/vault.crt" # Path to the Vault server's TLS certificate
  tls_key_file        = "/vault/config/certs/vault.key" # Path to the Vault server's TLS private key
  tls_client_ca_file  = "/vault/config/certs/ca.crt"    # Trust this CA for client certs (mTLS)
}

storage "file" {
  path = "/vault/file"   # Simple file-based storage in the container's /vault/file directory
}
```

### Explanation:
- `ui = true`: Lets you access the Vault UI (graphical interface).
- `disable_mlock = true`: Required in Docker or other environments where memory locking isn’t allowed by default.
- `listener "tcp"`: Configures the Vault server’s TCP listener on port 8200.
    - `address: 0.0.0.0:8200` tells Vault to listen on all interfaces in the container (mapped to port 8200 on your host).
    - `tls_cert_file` / `tls_key_file`: The server certificate & private key (from your self-signed certs).
    - `tls_client_ca_file`: Instructs Vault to request/verify client certificates signed by `ca.crt`. This is crucial for mTLS if you enable cert auth.
- `storage "file"`: Uses local disk storage at `/vault/file`. Fine for a PoC, but for production, consider a more robust backend.

---

## 6. Start Vault & Unseal

### 6.1 Create `docker-compose.yaml`
In the same folder as your `vault.hcl` (i.e., `vault/config/`), ensure you have a **`docker-compose.yaml`** that looks like this:

```yaml
services:
  vault:
    image: hashicorp/vault:1.14.1
    container_name: vault
    volumes:
      - ./vault.hcl:/vault/config/vault.hcl
      - ./certs:/vault/config/certs
      - vault-file:/vault/file
    ports:
      - "8200:8200"
    cap_add:
      - IPC_LOCK
    environment:
      # This helps Vault generate correct self-referencing URLs
      VAULT_API_ADDR: "https://localhost:8200"
    command: >
      vault server -config=/vault/config/vault.hcl

volumes:
  vault-file:
```

**Important parts:**
- Mounting `vault.hcl` and `./certs` into the container so Vault sees them at `/vault/config`.
- Exposing port `8200` on the host for Vault’s HTTPS endpoint.
- Using a named volume `vault-file` for Vault’s file storage.

---

### 6.2 Start Vault
Navigate to the folder containing `docker-compose.yaml`:

```bash
cd vault/config
```

Launch Vault in the background:

```bash
docker compose up -d
```

Check logs (optional):

```bash
docker compose logs -f
```

You should see something like:

```plaintext
==> Vault server started! Log data will stream in below:
...
```

> ⚠️ If you see TLS handshake errors referencing an unknown certificate, it’s often due to connections not trusting your self-signed CA. As long as Vault is up, you can proceed.

---

### 6.3 Initialize & Unseal
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

### 6.4 Log in as Root
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

## 7. Enable Cert Auth & Create Policy

Before proceeding, ensure you are **logged in** to Vault (with the root token or a token that can manage auth methods/policies):
```bash
vault token lookup
````

You should see `policies  [root]` indicating you have full privileges. If not, run:
```bash
vault login
```

### 7.1 Enable Certificate Authentication

```bash
vault auth enable cert
```

**Verification:**
```bash
vault auth list
```
Expected output should include:
```plaintext
path                    type    ...
----                    ----
cert/                   cert    ...
```
indicating that the "cert" auth method is enabled at `auth/cert/`.

### 7.2 Create a New Policy (dotnet-policy)
Create a file named `dotnet-policy.hcl` with the following content:

```hcl
path "secret/data/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
```

This policy grants the ability to read and write any secrets stored at `secret/data/*`.

Apply the policy:
```bash
vault policy write dotnet-policy dotnet-policy.hcl
```

If Vault cannot find the `dotnet-policy.hcl` file in the current directory, you need to copy it to docker. From another terminal (outside of the container shell) `cd` to the config folder that contains `dotnet-policy.hcl` and run:
```bash
docker cp dotnet-policy.hcl vault:/dotnet-policy.hcl
```

You should see:
```plaintext
Successfully copied 2.05kB to vault:/dotnet-policy.hcl
```

Now try to apply the policy again.

**Verification:**
```bash
vault policy list
```
Should now list `dotnet-policy` among the policies.

### 7.3 Register the Client Certificate for Cert Auth
To authenticate the .NET app via cert auth using (`client.crt`), register it so Vault knows which policy to assign:

```bash
vault write auth/cert/certs/dotnet-client \
    display_name="dotnet-client" \
    policies="dotnet-policy" \
    certificate=@/vault/config/certs/client.crt \
    ttl=1h
```

Any client connecting with a cert matching `client.crt` (and signed by your CA) will automatically get a token with `dotnet-policy` for 1 hour.

**Verification:**
```bash
vault read auth/cert/certs/dotnet-client
```
You should see a JSON response with details of the certificate name and policy mapping.

## 8. Store a Test Secret
To ensure the policy works for reading/writing secrets, we create a secret.

First check whether the `secret/` path is enabled, run:
```bash
vault secrets list
```

If you don’t see `secret/` in the output, enable the KV secrets engine with:

```bash
vault secrets enable -path=secret kv-v2
```

list secrets again and make sure `secret/` is in the output.

Now add a secret in `secret/hello` path:

```bash
vault kv put secret/hello greetings="Hello from Vault!"
```

**Verification:**
```bash
vault kv get secret/hello
```
Should return:
```plaintext
=== Data ===
Key         Value
---         -----
greetings   Hello from Vault!
```

Now your .NET client (with `client.crt`) can authenticate via `POST /v1/auth/cert/login` and access `secret/data/hello` using the policy permissions.


## 9. Minimal .NET 9 Console App

Below is a sample `Program.cs` demonstrating how to:

1. **Load** a client certificate (`client.pfx`).  
2. **POST** to `Vault` at `/v1/auth/cert/login` to retrieve a Vault token.  
3. **Use** that token to read the secret at `secret/data/hello`.

### 9.1 Add the PFX File to Your Project

- **Place** `client.pfx` in a `certs/` subfolder of your .NET project.  
- In your `.csproj`, ensure the file is copied to the output:

  ```xml
  <ItemGroup>
    <None Update="certs\client.pfx">
      <CopyToOutputDirectory>Always</CopyToOutputDirectory>
    </None>
  </ItemGroup>
  ```

### 9.2 Sample `Program.cs`

To use VaultSharp, you need to install the `VaultSharp` NuGet packages:
```
dotnet add package VaultSharp 
```

The below code snippet demonstrates how to use the `HttpClient` or `VaultSharp` libraries to authenticate with Vault using a client certificate and read a secret.

```csharp
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using Serilog;
using Serilog.Events;
using VaultSharp;
using VaultSharp.V1.AuthMethods;
using VaultSharp.V1.AuthMethods.Cert;

namespace VaultDemo.AuthWithTLSV2;

public static class Program
{
   private const string CertPath = "certs/client.pfx";
   private const string CertPassword = "";
   private const string VaultAddress = "https://127.0.0.1:8200/";

   public static async Task Main(string[] args)
   {
      // Configure Serilog
      Log.Logger = new LoggerConfiguration()
         .MinimumLevel.Override("Microsoft", LogEventLevel.Warning) // Suppress noisy logs
         .Enrich.FromLogContext()
         .WriteTo.Console()
         .CreateLogger();

      await UseHttpClient();
      await UseVaultSharp();
   }

   private static async Task UseHttpClient()
   {
      // 1) Create an HttpClientHandler that uses our client certificate
      var handler = new HttpClientHandler();
      handler.ClientCertificates.Add(
         new X509Certificate2(CertPath,
            CertPassword,
            X509KeyStorageFlags.DefaultKeySet));

      // 2) Optionally trust all server certs, or do a custom check
      //    In production, better to import 'ca.crt' into the machine store
      //    or do a proper check. For a POC:
      handler.ServerCertificateCustomValidationCallback =
         (message, cert, chain, errors) => true;

      // 3) Create HttpClient
      using var client = new HttpClient(handler);
      client.BaseAddress = new Uri(VaultAddress);

      // 4) Cert Auth: POST /v1/auth/cert/login
      var loginRequest = new StringContent("{}", Encoding.UTF8, "application/json");
      var loginResponse = await client.PostAsync("v1/auth/cert/login", loginRequest);
      loginResponse.EnsureSuccessStatusCode();

      var loginContent = await loginResponse.Content.ReadAsStringAsync();

      // 5) Parse JSON to extract client_token
      string vaultToken;
      using var doc = JsonDocument.Parse(loginContent);
      vaultToken = doc.RootElement
         .GetProperty("auth")
         .GetProperty("client_token")
         .GetString();

      Console.WriteLine($"Got Vault token: {vaultToken}");

      // 6) Use the token to read secret
      var secretRequest = new HttpRequestMessage(HttpMethod.Get, "v1/secret/data/hello");
      secretRequest.Headers.Add("X-Vault-Token", vaultToken);

      var secretResponse = await client.SendAsync(secretRequest);
      secretResponse.EnsureSuccessStatusCode();

      var secretJson = await secretResponse.Content.ReadAsStringAsync();
      Console.WriteLine($"Secret JSON: {secretJson}");
   }

   private static async Task UseVaultSharp()
   {
      // Vault Secret Path and mount
      const string secretPath = "hello"; // The path within the mount
      const string secretMountPoint = "secret"; // The mount point of the secrets engine

      // Load the Certificate
      var certificate = new X509Certificate2(CertPath, CertPassword, X509KeyStorageFlags.DefaultKeySet);

      // Vault Authentication
      IAuthMethodInfo authMethod = new CertAuthMethodInfo(certificate);

      // Initialize Vault client settings and provide a custom HttpClient provider.
      // This delegate receives the default handler and returns an HttpClient that uses it.
      // Here we check if the provided handler is an HttpClientHandler and override the certificate validation.
      var vaultClientSettings = new VaultClientSettings(VaultAddress, authMethod)
      {
         MyHttpClientProviderFunc = (handler) =>
         {
            if (handler is HttpClientHandler httpClientHandler)
            {
               // Bypass SSL certificate validation (only for dev environments!)
               httpClientHandler.ServerCertificateCustomValidationCallback =
                  (message, cert, chain, errors) => true;
            }
            // It's essential to use the provided handler to preserve certificate authentication.
            return new HttpClient(handler);
         }

         // You can set other settings if necessary, e.g.:
         // VaultServiceTimeout = TimeSpan.FromSeconds(100),
      };
      
      // // Initialize settings.  Use VaultAddress, and provide the authentication method.
      // var vaultClientSettings = new VaultClientSettings(VaultAddress, authMethod)
      // {
      //    //if you are not using https, then you can disable it.
      //    //VaultServiceTimeout = TimeSpan.FromSeconds(100),  // Optional timeout.
      //    //ContinueAsyncTasksOnCapturedContext = false,  // Often improves performance.
      // };

      IVaultClient vaultClient = new VaultClient(vaultClientSettings);

      var secret = await vaultClient.V1.Secrets.KeyValue.V2.ReadSecretAsync(secretPath, mountPoint: secretMountPoint);

      Log.Logger.Information("Content: {@Secret}", secret.Data.Data);
   }
}
```

To use `VaultSharp` with self-signed certificates in development, we need to use a custom HTTP client to bypass the certificate validation. Alternatively you can add it to list of trusted certificates in your machine.

### Explanation of Key Parts

- `handler.ClientCertificates.Add(new X509Certificate2("certs/client.pfx"))`: Loads your client certificate so the Vault "cert" auth recognizes you.
- `ServerCertificateCustomValidationCallback`: Bypasses server certificate checks. This is fine for a PoC, but in production, you’d install your `ca.crt` in the OS trust store or validate properly.
- `POST /v1/auth/cert/login`: This uses your client cert to authenticate. Vault responds with a token.
- `GET /v1/secret/data/hello`: The token is used in the `X-Vault-Token` header to read your secret from the KV engine.

### 9.3 Run the App

From the project directory:
```bash
dotnet run
```

**Expected Output:**
```plaintext
Got Vault token: hvs.XXXXXXXXXXXXXXXXXXXXXXXX
Secret JSON: {"request_id":"...","data":{"data":{"greetings":"Hello from Vault!"}...}...}
```

- If you see **403 (Forbidden)**, ensure your policy (`dotnet-policy`) grants read access to `secret/data/hello` and that your client certificate is registered to use that policy.
- If you see **x509: certificate signed by unknown authority**, you likely need to trust the self-signed CA or skip validation (as shown above).