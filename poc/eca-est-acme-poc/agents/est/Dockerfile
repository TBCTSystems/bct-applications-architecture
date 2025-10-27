# ==============================================================================
# EST Agent Dockerfile - Automated Client Certificate Lifecycle Management
# ==============================================================================
#
# This Dockerfile builds the ECA-EST agent container using a multi-stage build
# to optimize image size and security. The agent implements automated certificate
# lifecycle management using the EST protocol (RFC 7030) with bootstrap token-based
# initial enrollment and mTLS-based re-enrollment for client certificate rotation.
#
# Build Context: agents/ (parent directory - required for common modules access)
# Build Command (standalone): docker build -t eca-est-agent:latest -f agents/est/Dockerfile agents/
# Build Command (compose): docker-compose build eca-est-agent
#
# Note: The build context MUST be agents/ (not agents/est/) to allow COPY operations
# to access both est/ and common/ subdirectories. This is configured in docker-compose.yml
# with context: ./agents and dockerfile: est/Dockerfile.
#
# Multi-Stage Build Rationale:
#   - Stage 1 (build): Install PowerShell modules and dependencies
#   - Stage 2 (runtime): Copy only required modules and scripts for minimal image
#   - Benefit: Reduces final image size by ~10-20 MB, excludes package manager cache
#
# Container Initialization Flow:
#   1. Container starts and executes agent.ps1 via PowerShell Core
#   2. Agent loads configuration from /agent/config.yaml with env var overrides
#   3. Loads bootstrap token from file or environment variable (for initial enrollment)
#   4. Enters main event loop:
#      - DETECT: Monitor certificate existence and expiry status
#      - DECIDE: Determine enrollment type (initial vs re-enrollment)
#      - ACT: Execute EST protocol flow (bootstrap token or mTLS authentication)
#      - SLEEP: Wait for next check interval (default: 60 seconds)
#   5. Handles graceful shutdown on SIGTERM
#
# Volume Requirements:
#   - /certs/client: Persistent storage for client certificate and private key
#   - /config: Persistent storage for bootstrap token file (token.txt)
#
# Required Environment Variables:
#   - PKI_URL: step-ca EST server URL (default: https://pki:9000)
#   - DEVICE_NAME: Device identifier for certificate CN (default: client-device-001)
#   - CERT_PATH: Certificate output path (default: /certs/client/client.crt)
#   - KEY_PATH: Private key output path (default: /certs/client/client.key)
#
# Optional Environment Variables:
#   - RENEWAL_THRESHOLD_PCT: Renewal trigger percentage (default: 75)
#   - CHECK_INTERVAL_SEC: Polling interval in seconds (default: 60)
#   - EST_BOOTSTRAP_TOKEN: Bootstrap token (alternative to file-based token)
#   - BOOTSTRAP_TOKEN_PATH: Path to bootstrap token file (default: /config/token.txt)
#
# Dependencies:
#   - powershell-yaml: PowerShell module for YAML configuration parsing
#   - OpenSSL: Command-line tool for PFX creation (mTLS authentication in re-enrollment)
#   - EST-specific modules: EstClient.psm1, BootstrapTokenManager.psm1
#   - Common modules: Logger, CryptoHelper, CertificateMonitor, ConfigManager, FileOperations
#
# ==============================================================================

# ==============================================================================
# Build Stage: Install PowerShell modules and prepare dependencies
# ==============================================================================
# NOTE: Using alpine-3.20 instead of alpine-3.19 specified in requirements
# because 7.4-alpine-3.19 tag does not exist in Microsoft Container Registry.
# The 7.4-alpine-3.20 is the current stable Alpine-based PowerShell 7.4 image.
FROM mcr.microsoft.com/powershell:7.4-alpine-3.20 AS build

# Install powershell-yaml module required by ConfigManager.psm1
# - ConfigManager uses ConvertFrom-Yaml cmdlet provided by this module
# - Install to AllUsers scope for consistent system-wide location
# - Force flag bypasses confirmation prompts for non-interactive installation
RUN pwsh -Command "Install-Module -Name powershell-yaml -Force -Scope AllUsers"

# ==============================================================================
# Runtime Stage: Minimal production image with agent and dependencies
# ==============================================================================
# NOTE: Using alpine-3.20 (same as build stage) for consistency
FROM mcr.microsoft.com/powershell:7.4-alpine-3.20 AS runtime

# Install OpenSSL for PFX creation in re-enrollment workflow
# - EstClient.psm1 uses `openssl pkcs12 -export` to create temporary PFX files
# - Required for mTLS authentication during certificate re-enrollment
# - Alpine base image includes openssl by default, but explicitly ensure it's present
RUN apk add --no-cache openssl

# Copy installed powershell-yaml module from build stage
# Source: AllUsers scope installs to /usr/local/share/powershell/Modules/
# Destination: Same path in runtime image for module auto-discovery
COPY --from=build /usr/local/share/powershell/Modules/powershell-yaml /usr/local/share/powershell/Modules/powershell-yaml

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

# Force cache invalidation for EST client URL fix (2025-10-25)
ARG CACHE_BUST=20251025_205600

# Copy EST agent scripts and modules to /agent/ directory
# - agent.ps1: Main entry point (event-driven lifecycle orchestration)
# - EstClient.psm1: EST protocol implementation (RFC 7030) for initial enrollment and re-enrollment
# - BootstrapTokenManager.psm1: Bootstrap token loading and validation with security redaction
# Source: agents/est/ subdirectory (from build context .)
COPY agents/est/*.ps1 /agent/
COPY agents/est/*.psm1 /agent/

# Copy default configuration file
COPY agents/est/config.yaml /agent/

# Set working directory to /agent
# - agent.ps1 imports modules using relative paths from $PSScriptRoot
# - Expected structure: /agent/agent.ps1, /agent/common/*.psm1
# - This ensures $PSScriptRoot resolves to /agent when entrypoint runs
WORKDIR /agent

# Set container entrypoint to PowerShell executing agent.ps1
# - Array format (exec form) ensures proper signal handling for graceful shutdown
# - SIGTERM signals are delivered directly to pwsh process (PID 1)
# - agent.ps1 registers PowerShell.Exiting event for cleanup on shutdown
# - Using absolute path to ensure $PSScriptRoot is set correctly
ENTRYPOINT ["pwsh", "/agent/agent.ps1"]
