# Interact with HashCorp Vault From a .NET App

## Overview
This guide provides an overview of how to authenticate with HashiCorp Vault using different authentication methods and how to interact with Vault from a .NET application.

## Table of Contents
- [Directory Structure]()
- [Create Vault Client using VaultSharp]()
- [Authenticate with Vault](<path_to_vault_authentication.md>)
- [Interacting with Vault](<path_to_interacting_with_vault.md>)

### Prerequisites

#### Generate Certificates (Included)
Self-signed certificates are generated and included under the `devtools/certs` directory for this POC. However, if you are interested to regenerate them, you can follow the instructions here: [certificate generation guide](../../docs/miscellaneous/self-signed-certs.md).

#### Configure, Start, and Unseal Vault
This document assumes that you have already configured, unsealed, and started Vault. You can find the instructions [here](../../docs/miscellaneous/start-and-unseal.md).
Also, ensure that the Secrets Engine V2 is enabled:
```bash
vault secrets enable -path=secret kv-v2
```

## 1. Directory Structure
Below is the folder structure for the files used in the POC. This is just to organize your Vault config and certs in one place.

xxx update based on the final refactor
```plaintext
└── config/
    ├── certs/                 (Self-signed certificates for client and Vault)
    ├── policies/              (Vault policy files)
    ├── vault.hcl              (Vault configuration)
    ├── docker-compose.yaml    (Docker Compose for Vault)
    └── dotnet-policy.hcl      (Policy file granting .NET app access to secrets)
```

## Create and Configure VaultSharp Client

See [VaultClientFactory.cs](../../src/VaultDemo.Console/Factories/VaultClientFactory.cs) that instantiates an `IVaultClient` based on the authentication method and the provided [VaultConfiguration](../../src/VaultDemo.Console/Models/VaultConfiguration.cs).

The authentication method and Vault configurations can be set in [appsettings.json](../../src/VaultDemo.Console/appsettings.json).

Then, in [Program.cs](../../src/VaultDemo.Console/Program.cs), we can register the `IVaultClient` as follows:

```csharp
// Add configuration sources
config.AddJsonFile("appsettings.json", optional: true, reloadOnChange: true);

// Load Vault config
var vaultConfig = config.GetSection("Vault").Get<VaultConfiguration>();

// Register Vault client as a singleton so it can be injected anywhere
builder.Services.AddSingleton(new VaultClientFactory().CreateVaultClient(vaultConfig));
```



## Authenticate With Vault

The []() contains properties for different authentication methods. You can set the desired authentication method in [appsettings.json]()


The .NET app can authenticate itself with Vault via various methods, which are discussed below. We will be using the policy provided in [dotnet-app-policy.hcl](../../devtools/vault/config/vault.hcl) so that the app can read and write certificates into Vault.

### 2.1. Create a New Policy (dotnet-app-policy)
We need to create a policy with capabilities such as reading and writing secrets. It will be assigned to the client certificate (e.g., the .NET app) so it can access secrets after authenticating using the certificate.

Apply the policy:
```bash
vault policy write dotnet-app-policy /vault/policies/dotnet-app-policy.hcl
```

### Token Authentication
Token authentication is the simplest method to authenticate with Vault. It involves providing a Vault-generated token in each request. This method is best suited for initial development or where token-based authentication is explicitly required.

```bash
# Create a new token with the policy
vault token create -policy=dotnet-app-policy
```
Update `appsetting.json` with the generated token.

### UserPass Authentication
The UserPass authentication method allows applications or users to authenticate using a username and password. This is useful for human users but not ideal for machine authentication in production environments.

```bash
# Enable UserPass authentication
vault auth enable userpass

# Create a new user with a policy
vault write auth/userpass/users/myuser password=mypassword policies=dotnet-app-policy
```

### AppRole Authentication
AppRole authentication is designed for applications and services that require programmatic authentication without human intervention. It involves a `RoleID` and a `SecretID` for authentication.

```bash
# Enable AppRole authentication
vault auth enable approle

# Create a new role with the policy
vault write auth/approle/role/dotnet-app policies=dotnet-app-policy

# Retrieve RoleID
vault read auth/approle/role/dotnet-app/role-id

# Generate SecretID
vault write -f auth/approle/role/dotnet-app/secret-id
```

### Cert Authentication
Certificate-based authentication allows clients to authenticate with Vault using TLS certificates. This is a secure method, especially in environments where mTLS is enforced.

```bash
# Enable certificate authentication
vault auth enable cert

# Configure the certificate authentication method
vault write auth/cert/certs/dotnet-app \
    display_name="dotnet-app" \
    certificate="$(cat /certs/client.crt)" \
    policies="dotnet-app-policy"
```


## 4. Enable Cert Auth & Create Policy

Before proceeding, ensure you are **logged in** to Vault (with the root token or a token that can manage auth methods/policies):
```bash
vault token lookup
````

You should see `policies  [root]` indicating you have full privileges. If not, run:
```bash
vault login
```

### 4.1 Enable Certificate Authentication

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



This policy grants the ability to read and write any secrets stored at `secret/data/*`.


```

**Verification:**
```bash
vault policy list
```
Should now list `dotnet-policy` among the policies.

### 4.3 Register the Client Certificate for Cert Auth
To authenticate the .NET app via cert auth using (`client.crt`), register it so Vault knows which policy to assign:

```bash
vault write auth/cert/certs/dotnet-client \
    display_name="dotnet-client" \
    policies="dotnet-app-policy" \
    certificate=@/certs/client.crt
```

Any client connecting with a cert matching `client.crt` (and signed by your CA) will automatically get a token with `dotnet-policy`.

**Verification:**
```bash
vault read auth/cert/certs/dotnet-client
```
You should see a JSON response with details of the certificate name and policy mapping.

## 5. Minimal .NET 9 Console App

### 5.1. Store a Test Secret
First let's create a secret that the .NET app will fetch.

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

Below is a sample `Program.cs` demonstrating how to:

1. **Load** a client certificate (`client.pfx`).  
2. **POST** to `Vault` at `/v1/auth/cert/login` to retrieve a Vault token.  
3. **Use** that token to read the secret at `secret/data/hello`.

### 5.2. Add the PFX File to Your Project

- **Place** `client.pfx` in a `certs/` subfolder of your .NET project.  
- In your `.csproj`, ensure the file is copied to the output:

  ```xml
  <ItemGroup>
    <None Update="certs\client.pfx">
      <CopyToOutputDirectory>Always</CopyToOutputDirectory>
    </None>
  </ItemGroup>
  ```

### 5.3. Sample `Program.cs`

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

Explanation of Key Parts

- `handler.ClientCertificates.Add(new X509Certificate2("certs/client.pfx"))`: Loads your client certificate so the Vault "cert" auth recognizes you.
- `ServerCertificateCustomValidationCallback`: Bypasses server certificate checks. This is fine for a PoC, but in production, you’d install your `ca.crt` in the OS trust store or validate properly.
- `POST /v1/auth/cert/login`: This uses your client cert to authenticate. Vault responds with a token.
- `GET /v1/secret/data/hello`: The token is used in the `X-Vault-Token` header to read your secret from the KV engine.

### 5.4 Run the App

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