# POC: HashiCorp Vault
This is work in process.
TODOs:
- Extract vault service into a shared project that can be used by both projects listed below.
- Add instructions (CLI commands) to add the required secrets.

## Accessing Secrets
This [directory](src/AccessSecrets) contains examples of how accessing secrets from vault using VaultSharp and Token Authentication.
Note that secrets must be added to vault before running the app.

## Secure HashiCorp Vault with Self-Signed TLS and .NET Certificate Authentication
This [markdown](src/TLSAuthV2/README.md) provides a step-by-step guide for authenticating a .NET9 app using self-signed certificate.