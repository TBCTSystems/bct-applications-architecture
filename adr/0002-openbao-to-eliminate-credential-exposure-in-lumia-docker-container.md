# Use of KeyValut to Eliminate Credential Exposure in Lumia Docker Container

* Status: **Accepted**  
* Deciders: BCT Architecture Team
* Date: **2025-04-08**

**Technical Story:** [EPM-25651](https://terumobct.atlassian.net/browse/EPM-25651)

## Context and Problem Statement

The Lumia application, running as a Docker container, requires access to sensitive credentials and secrets (e.g., database credentials, MQTT Broker credentials, Redis Credentials, MINIO credentials etc). Previously, credentials were passed through environment variables, leading to potential security vulnerabilities and exposure risks.

**How can we securely manage secrets and credentials for Lumia without exposing them within the Docker environment?**

## Decision Drivers

* Eliminate credential exposure inside Docker containers
* Ensure secrets are dynamically retrievable and revocable
* Enable integration with authentication methods (certs, AppRole)
* Support for templating and secret rendering
* Lightweight and container-friendly secret management solution
* Limited modifications to the established code base.
## Considered Options

* OpenBao
* HashiCorp Vault
* Docker Secrets

## Decision Outcome

**Chosen option: "OpenBao"**, because it provides a lightweight, container-friendly solution that supports dynamic secrets, file-based templating, and pluggable authentication (including AppRole and TLS certificate auth). It’s also open-source and suitable for our existing Dockerized setup.

### Positive Consequences

* Credentials are no longer hardcoded or stored in environment variables
* Supports ephemeral token-based access with AppRole and TLS auth
* Dynamic secret rendering to tmpfs via OpenBao agent templates
* Reduced attack surface for credentials within containers

### Negative Consequences

* Requires additional setup and maintenance of OpenBao server and agents
* Learning curve for integrating and configuring AppRole and template rendering
* Initial configuration complexity for secure auth and storage policies

## Pros and Cons of the Options

### OpenBao

* Good, because it's open-source and actively maintained
* Good, because it supports templating for secret rendering
* Good, because it integrates with our current certificate and AppRole-based auth methods
* Bad, because it requires setup of a separate secret management infrastructure

### HashiCorp Vault

* Good, because it's a mature and feature-rich secret management solution
* Good, because it has enterprise support
* Bad, because it has a steeper learning curve and is heavier than OpenBao for our use case
* Bad, because licensing and cost may become a concern in future

### Docker Secrets

* Good, because it integrates natively with Docker Swarm
* Good, because it's simple to set up for small-scale use
* Bad, because it lacks support for dynamic secrets
* Bad, because it doesn't integrate easily with certificate/AppRole authentication

## Links

* [OpenBao GitHub](https://github.com/openbao/openbao)
* [HashiCorp Vault](https://www.vaultproject.io/)
* [Docker Secrets Documentation](https://docs.docker.com/engine/swarm/secrets/)
