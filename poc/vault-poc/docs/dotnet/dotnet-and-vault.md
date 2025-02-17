# Interact with HashCorp Vault From a .NET App

## Overview

This guide provides an overview of how to set up a .NET application to interact with HashiCorp Vault. It covers creating a Vault client, authenticating using different methods, and securely accessing secrets.

## Table of Contents

- [Directory Structure](#1-directory-structure)
- [Create Vault Client using VaultSharp](#2-create-and-configure-vaultsharp-client)
- [Authenticate with Vault](#3-authenticate-with-vault)
- [Interacting with Vault](#4-interacting-with-vault-using-vaultsharp)

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
To be updated.

## 2. Create and Configure VaultSharp Client

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

## 3. Authenticate With Vault

The .NET app can authenticate itself with Vault via various methods, which are discussed below. We will be using the policy provided in [dotnet-app-policy.hcl](../../devtools/vault/config/vault.hcl) so that the app can read and write certificates into Vault.

> ⚠️ Do not forget to update `appsettings.json` with the credentials/tokens/etc.

### 3.1. Create a New Policy (dotnet-app-policy)
We need to create a policy with capabilities such as reading and writing secrets.

Apply the policy:
```bash
vault policy write dotnet-app-policy /vault/policies/dotnet-app-policy.hcl
```

### 3.2. Token Authentication
Token authentication is the simplest method to authenticate with Vault. It involves providing a Vault-generated token in each request.

```bash
# Create a new token with the policy
vault token create -policy=dotnet-app-policy
```

### 3.3. UserPass Authentication
The UserPass authentication method allows applications or users to authenticate using a username and password.

```bash
# Enable UserPass authentication
vault auth enable userpass

# Create a new user with a policy
vault write auth/userpass/users/myuser password=mypassword policies=dotnet-app-policy
```

### 3.4. AppRole Authentication
It involves a `RoleID` and a `SecretID` for authentication.

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

### 3.5. Cert Authentication
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

## 4. Interacting with Vault Using VaultSharp

VaultSharp is a .NET client for interacting with HashiCorp Vault. The [VaultService.cs](../../src/VaultDemo.Console/Services/VaultService.cs) class in this project is responsible for securely reading and writing secrets using Vault's Key-Value v2 engine.

### 4.1. Key Methods Explained

#### Reading a Secret
```csharp
var secret = await vaultClient.V1.Secrets.KeyValue.V2.ReadSecretAsync(path, mountPoint: "secret");
```
This retrieves a secret from Vault's **KV v2 engine** at the given `path`. The `mountPoint` parameter specifies where the KV engine is enabled (`secret` in this case).

#### Retrieving a Specific Key
```csharp
var value = secret.Data.Data.ContainsKey(key) ? secret.Data.Data[key]?.ToString() : null;
```
After reading the secret, this checks if the specified `key` exists in the response and extracts its value.

#### Writing a Secret
```csharp
var data = new Dictionary<string, object>
{
    { key, typeof(T) == typeof(string) ? value : JsonSerializer.Serialize(value) }
};
await vaultClient.V1.Secrets.KeyValue.V2.WriteSecretAsync(path, data, mountPoint: "secret");
```
This constructs a dictionary with the `key-value` pair and writes it to Vault. If the value is not a string, it is serialized to JSON before storage.

#### Error Handling
```csharp
catch (Exception ex)
{
    logger.LogError("Error fetching secret from Vault. Path: {SecretPath}, Key: {SecretKey}, Exception {Message}",
        path, key, ex.Message);
    return default;
}
```
All operations are wrapped in `try-catch` blocks, and errors are logged for troubleshooting.

### 4.2. Vault Client Factory

The [VaultClientFactory.cs](../../src/VaultDemo.Console/Factories/VaultClientFactory.cs) class is responsible for creating an `IVaultClient` instance based on the selected authentication method. It supports multiple Vault authentication mechanisms, including Token, UserPass, AppRole, and TLS Certificate-based authentication. Additionally, it allows disabling SSL verification for development environments using self-signed certificates.

### 4.3. Service Registration

The `VaultClientFactory` and `VaultService` are registered in the application's dependency injection container, allowing them to be injected into other services.

#### Key Points:

- **Vault client registration**: The factory is used to create an `IVaultClient` instance, which is registered as a singleton.
- **Vault service registration**: The `VaultService` is registered to interact with secrets stored in Vault.
- **Logging integration**: Serilog is configured to log messages to the console.

#### Code Example:

```csharp
// Register Vault client as a singleton
builder.Services.AddSingleton(new VaultClientFactory().CreateVaultClient(vaultConfig));

// Register Vault service
builder.Services.AddSingleton<IVaultService, VaultService>();
```

### 4.4. Building and Running the Application

To build and run the application using the .NET CLI, use the following commands:

```sh
# Restore dependencies
 dotnet restore

# Build the project
 dotnet build

# Run the application
 dotnet run
```

#### Important Notes:

- If you have generated a **new certificate**, update the `client.pfx` file under `Certs`.
- Ensure it is copied to the target output directory by including the following configuration in your `.csproj` file:

```xml
<ItemGroup>
  <None Remove="appsettings.json" />
  <Content Include="appsettings.json">
    <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
  </Content>
  <None Update="Certs\client.pfx">
    <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
  </None>
</ItemGroup>
```


