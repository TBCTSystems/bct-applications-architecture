# ==============================================================================
# JWK Agent Dockerfile - Automated ACME Account Key Rotation
# ==============================================================================
#
# Builds the ECA-JWK agent container responsible for rotating the ACME account
# key material (JWK) on a configurable cadence. The agent relies on Posh-ACME
# to perform the ACME account key rollover workflow and persists the freshly
# generated JWK to a shared volume for downstream consumers.
#
# Build Context: project root (required to copy common modules and schema)
# docker compose build eca-jwk-agent
#
# ============================================================================== 

FROM mcr.microsoft.com/powershell:7.4-alpine-3.20 AS build

RUN pwsh -NoLogo -Command "Install-Module -Name powershell-yaml,Posh-ACME -Force -Scope AllUsers"

FROM mcr.microsoft.com/powershell:7.4-alpine-3.20 AS runtime

# Install Docker CLI (for ServiceReloadController) and OpenSSL (for certificate introspection)
RUN apk add --no-cache docker-cli openssl

COPY --from=build /usr/local/share/powershell/Modules/powershell-yaml /usr/local/share/powershell/Modules/powershell-yaml
COPY --from=build /usr/local/share/powershell/Modules/Posh-ACME /usr/local/share/powershell/Modules/Posh-ACME

COPY agents/common/*.psm1 /agent/common/
COPY agents/acme/ServiceReloadController.psm1 /agent/ServiceReloadController.psm1
COPY config/agent_config_schema.json /config/agent_config_schema.json
COPY agents/jwk/agent-JWK.ps1 /agent/agent-JWK.ps1
COPY agents/jwk/config.yaml /agent/config.yaml

WORKDIR /agent

ENTRYPOINT ["pwsh", "/agent/agent-JWK.ps1"]
