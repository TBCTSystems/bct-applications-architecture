# POC: HashiCorp Vault

## Overview
This repository serves as a **proof of concept (POC)** for using HashiCorp Vault to manage secrets securely. It contains documentation and example implementations covering authentication, secret storage, encryption, and best practices.

## Documentation
### Introduction To Vault
- [Overview](docs/vault-basics/1.overview.md) - Introduction to Vault and its purpose.
- [Introduction to Commands](docs/vault-basics/2.commands-intro.md) - Covers basic command structure and usage.
- [Authentication](docs/vault-basics/3.authentication.md) - Explains authentication methods, creating users, AppRole, and certificate-based authentication.
- [Policies](docs/vault-basics/4.policies.md) - Details Vault’s policy system, capabilities, and assignment.
- [Tokens](docs/vault-basics/5.token.md) - Explains token properties, creation, renewal, and management.
- [Secrets Engine](docs/vault-basics/6.secrets-engine.md) - Provides an overview of various secrets engines, their use cases, and configuration.
- [Vault Leases](docs/vault-basics/7.lease) - Explains lease management for dynamic secrets (to be added).

### Other Topics

- [Generate self-signed certificates](docs/miscellaneous/self-signed-certs.md)
- [Configure, start, and unseal Vault using docker](docs/miscellaneous/start-and-unseal.md)
- [Dotnet Examples](docs/dotnet/dotnet-and-vault.md)


