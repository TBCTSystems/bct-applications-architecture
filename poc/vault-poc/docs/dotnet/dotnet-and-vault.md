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

> Do not forget to update `appsettings.json`

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
To be updated (the code has been cleaned up and working!)