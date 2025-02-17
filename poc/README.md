# Proof of Concept (POC)

This directory contains multiple Proof of Concepts (POCs). Over time, additional directories will be added. Below are the currently available POCs:

## 1. Vault POC
[This directory](./vault-poc) contains a POC for **HashiCorp Vault**, demonstrating how to securely authenticate, store, and retrieve secrets in a .NET application using **VaultSharp**.

### Key Features:
- **Authentication Methods**: Covers multiple authentication approaches such as Token, UserPass, AppRole, and TLS Certificate-based authentication.
- **Secrets Engine**: Demonstrates interaction with Vault’s **Key-Value (KV) v2 secrets engine**.
- **Best Practices**: Includes how to structure policies, manage authentication, and interact with Vault programmatically.
- **Integration with .NET**: Uses **VaultSharp** for API interactions.

Most of the **fundamental concepts** and **tutorials** in this Vault POC also apply to **OpenBao**, making it a useful reference for both.

## 2. OpenBao POC
[This directory](./bao-poc) contains a POC for **OpenBao**, an alternative to HashiCorp Vault. It follows similar principles for secrets management and authentication.

### Key Features:
- **Basic Authentication & Secrets Storage**: Demonstrates how to authenticate and store/retrieve secrets.
- **Similarities with Vault**: Since OpenBao shares many design principles with Vault, users can refer to the **Vault POC** for understanding core concepts.
- **Differences from Vault**: Highlights key differences in how OpenBao handles secrets and authentication.

For a detailed comparison between **Vault** and **OpenBao**, see: [Vault vs. OpenBao](./OpenBao-HashiCorp%20Comparison.md).

