# POC: HashiCorp Vault

## Overview
This repository serves as a **proof of concept (POC)** for using HashiCorp Vault to manage secrets securely. It contains documentation and example implementations covering authentication, secret storage, encryption, and best practices.

## Documentation
Below are links to the main sections of this repository:

- [Overview](docs/1.overview.md) - Introduction to Vault and its purpose.
- [Introduction to Commands](docs/2.commands-intro.md) - Covers basic command structure and usage.
- [Authentication](docs/3.authentication.md) - Explains authentication methods, creating users, AppRole, and certificate-based authentication.
- [Policies](docs/4.policies.md) - Details Vault’s policy system, capabilities, and assignment.
- [Tokens](docs/5.token.md) - Explains token properties, creation, renewal, and management.
- [Secrets Engine](docs/6.secrets-engine.md) - Provides an overview of various secrets engines, their use cases, and configuration.
- [Vault Leases](docs/7.lease) - Explains lease management for dynamic secrets (to be added).

## TODOs
- Extract Vault service into a shared project that can be used by multiple implementations.
- Add CLI instructions to populate Vault with required secrets.

## Accessing Secrets
This [directory](src/AccessSecrets) contains examples of how to access secrets from Vault using **VaultSharp** and **Token Authentication**.

**Note:** Secrets must be added to Vault before running the app.

## Secure HashiCorp Vault with Self-Signed TLS and .NET Certificate Authentication
This [markdown](src/TLSAuthV2/README.md) provides a step-by-step guide for authenticating a .NET 9 app using self-signed certificates.

