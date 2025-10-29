# ============================================
# ECA Test Runner Docker Image
# ============================================
# Provides a consistent test environment with all dependencies pre-installed.
# Based on Microsoft's official PowerShell image.

FROM mcr.microsoft.com/powershell:lts-alpine-3.20

# Metadata
LABEL maintainer="ECA Team"
LABEL description="ECA PoC Test Runner with Pester"
LABEL version="1.0"

# Install dependencies
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    openssl \
    ca-certificates

# Install required PowerShell modules (Pester for testing, Posh-ACME + powershell-yaml for agent parity)
RUN pwsh -Command "\
    Install-Module -Name Pester -MinimumVersion 5.0 -Force -Scope AllUsers -AcceptLicense; \
    Install-Module -Name powershell-yaml,Posh-ACME -Force -Scope AllUsers -AcceptLicense \
"

# Create working directory
WORKDIR /workspace

# Copy test files and modules
# Note: In practice, these will be mounted as volumes for live updates
COPY . /workspace/

# Default command runs all tests
CMD ["pwsh", "-Command", "\
    $config = New-PesterConfiguration; \
    $config.Run.Path = './tests/unit', './tests/integration'; \
    $config.Run.Exit = $true; \
    $config.Output.Verbosity = 'Normal'; \
    Invoke-Pester -Configuration $config \
"]

# Health check (verifies Pester is available)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=1 \
    CMD pwsh -Command "Get-Module -ListAvailable Pester | Out-Null" || exit 1
