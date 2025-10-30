# ==============================================================================
# ACME Agent Dockerfile - Automated Server Certificate Lifecycle Management
# ==============================================================================
#
# This Dockerfile builds the ECA-ACME agent container using a multi-stage build
# to optimize image size and security. The agent implements automated certificate
# lifecycle management using the ACME protocol (RFC 8555) with HTTP-01 challenge
# validation, certificate installation, and zero-downtime NGINX reload.
#
# Build Context: agents/ (parent directory - required for common modules access)
# Build Command (standalone): docker build -t eca-acme-agent:latest -f agents/acme/Dockerfile agents/
# Build Command (compose): docker-compose build eca-acme-agent
#
# Note: The build context MUST be agents/ (not agents/acme/) to allow COPY operations
# to access both acme/ and common/ subdirectories. This is configured in docker-compose.yml
# with context: ./agents and dockerfile: acme/Dockerfile.
#
# Multi-Stage Build Rationale:
#   - Stage 1 (build): Install PowerShell modules and dependencies
#   - Stage 2 (runtime): Copy only required modules and scripts for minimal image
#   - Benefit: Reduces final image size by ~10-20 MB, excludes package manager cache
#
# Container Initialization Flow:
#   1. Container starts and executes agent.ps1 via PowerShell Core
#   2. Agent loads configuration from /agent/config.yaml with env var overrides
#   3. Initializes ACME account (creates on first run, loads existing thereafter)
#   4. Enters main event loop:
#      - DETECT: Monitor certificate expiry status
#      - DECIDE: Apply renewal policy (threshold-based or force-trigger)
#      - ACT: Execute ACME protocol flow if renewal needed
#      - SLEEP: Wait for next check interval (default: 60 seconds)
#   5. Handles graceful shutdown on SIGTERM
#
# Volume Requirements:
#   - /certs/server: Shared volume with target-server for certificate delivery
#   - /config: Persistent storage for ACME account key (acme-account.key)
#   - /challenge: Shared volume with target-server for HTTP-01 challenge token
#
# Required Environment Variables:
#   - PKI_URL: step-ca ACME server URL (default: https://pki:9000)
#   - DOMAIN: Domain name for certificate (default: target-server)
#   - CERT_PATH: Certificate output path (default: /certs/server/server.crt)
#   - KEY_PATH: Private key output path (default: /certs/server/server.key)
#
# Optional Environment Variables:
#   - RENEWAL_THRESHOLD_PCT: Renewal trigger percentage (default: 75)
#   - CHECK_INTERVAL_SEC: Polling interval in seconds (default: 60)
#
# Dependencies:
#   - powershell-yaml: PowerShell module for YAML configuration parsing
#   - Posh-ACME: Production-ready ACME client implementation (replaces custom AcmeClient.psm1)
#   - ACME-specific modules: ServiceReloadController.psm1, AcmeClient-PoshACME.psm1, PoshAcmeConfigAdapter.psm1
#   - Common modules: Logger, CertificateMonitor, ConfigManager, FileOperations
# Note: CryptoHelper no longer needed - Posh-ACME handles all cryptographic operations
#
# ==============================================================================

# ==============================================================================
# Build Stage: Install PowerShell modules and prepare dependencies
# ==============================================================================
# NOTE: Using alpine-3.20 instead of alpine-3.19 specified in requirements
# because 7.4-alpine-3.19 tag does not exist in Microsoft Container Registry.
# The 7.4-alpine-3.20 is the current stable Alpine-based PowerShell 7.4 image.
FROM mcr.microsoft.com/powershell:7.4-alpine-3.20 AS build

# Install PowerShell modules required by ECA-ACME agent
# - powershell-yaml: YAML configuration parsing for ConfigManager.psm1
# - Posh-ACME: Production-ready ACME client implementation (replacing custom AcmeClient.psm1)
# Install to AllUsers scope for consistent system-wide location
# Force flag bypasses confirmation prompts for non-interactive installation
RUN pwsh -Command "Install-Module -Name powershell-yaml,Posh-ACME -Force -Scope AllUsers"

# ==============================================================================
# Runtime Stage: Minimal production image with agent and dependencies
# ==============================================================================
# NOTE: Using alpine-3.20 (same as build stage) for consistency
FROM mcr.microsoft.com/powershell:7.4-alpine-3.20 AS runtime

# Install Docker CLI for NGINX reload via docker exec and OpenSSL for certificate operations
# - Docker CLI: Required by ServiceReloadController.psm1 to send reload signals (uses Docker socket mounted from host)
# - OpenSSL: Required by CryptoHelper.psm1 to convert PEM to DER format for certificate parsing
RUN apk add --no-cache docker-cli openssl

# Copy installed PowerShell modules from build stage
# Source: AllUsers scope installs to /usr/local/share/powershell/Modules/
# Destination: Same path in runtime image for module auto-discovery
# - powershell-yaml: YAML configuration parsing
# - Posh-ACME: Production-ready ACME client implementation
COPY --from=build /usr/local/share/powershell/Modules/powershell-yaml /usr/local/share/powershell/Modules/powershell-yaml
COPY --from=build /usr/local/share/powershell/Modules/Posh-ACME /usr/local/share/powershell/Modules/Posh-ACME

# Copy common shared modules to /agent/common/ subdirectory
# These modules are used by both ACME and EST agents
# Source: agents/common/*.psm1 (from build context .)
# - Logger.psm1: Structured logging with JSON/console output
# - CryptoHelper.psm1: RSA key generation, CSR creation, certificate parsing
# - CertificateMonitor.psm1: Certificate existence checking and expiry calculation
# - ConfigManager.psm1: YAML configuration loading with env var overrides (requires powershell-yaml)
# - FileOperations.psm1: Atomic file writes and permission management
COPY agents/common/*.psm1 /agent/common/

# Copy JSON Schema for configuration validation
# ConfigManager.psm1 uses this to validate agent configuration
# Source: config/ (from build context .)
# Destination: /config/ (expected by ConfigManager path resolution logic)
COPY config/agent_config_schema.json /config/agent_config_schema.json

# Copy ACME agent scripts and modules to /agent/ directory
# - agent-PoshACME.ps1: Simplified main entry point using Posh-ACME (48.8% code reduction)
# - AcmeClient-PoshACME.psm1: Posh-ACME wrapper maintaining backward compatibility
# - PoshAcmeConfigAdapter.psm1: Configuration adapter for Posh-ACME integration
# - ServiceReloadController.psm1: NGINX reload controller via docker exec
# - agent.ps1: Original script (preserved for fallback)
# Source: agents/acme/ subdirectory (from build context .)
COPY agents/acme/*.ps1 agents/acme/*.psm1 /agent/

# Copy default configuration file (optional but recommended)
# Provides documented defaults that can be overridden by environment variables
# Agent can run without this file using env vars only, but having it improves documentation
# Source: agents/acme/ subdirectory (from build context .)
COPY agents/acme/config.yaml /agent/

# Set working directory to /agent
# - agent.ps1 imports modules using relative paths from $PSScriptRoot
# - Expected structure: /agent/agent.ps1, /agent/common/*.psm1
# - This ensures $PSScriptRoot resolves to /agent when entrypoint runs
WORKDIR /agent

# Set container entrypoint to PowerShell executing simplified agent
# - Array format (exec form) ensures proper signal handling for graceful shutdown
# - SIGTERM signals are delivered directly to pwsh process (PID 1)
# - agent-PoshACME.ps1 uses Posh-ACME with 48.8% code reduction while maintaining full compatibility
# - Registers PowerShell.Exiting event for cleanup on shutdown
# - Using absolute path to ensure $PSScriptRoot is set correctly
ENTRYPOINT ["pwsh", "/agent/agent-PoshACME.ps1"]
