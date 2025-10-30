# ============================================
# ECA Test Runner Docker Image
# ============================================
# Provides a consistent test environment with all dependencies pre-installed.
# Based on Microsoft's official PowerShell image (Ubuntu for better PSGallery support).

FROM mcr.microsoft.com/powershell:lts-ubuntu-22.04

# Metadata
LABEL maintainer="ECA Team"
LABEL description="ECA PoC Test Runner with Pester"
LABEL version="1.0"

# Install dependencies
RUN apt-get update && apt-get install -y \
    bash \
    curl \
    jq \
    openssl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install required PowerShell modules (Pester for testing, Posh-ACME + powershell-yaml for agent parity)
RUN pwsh -Command "\
    \$ErrorActionPreference = 'Stop'; \
    Write-Host 'Checking for PSGallery...'; \
    if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) { \
        Write-Host 'PSGallery not found, registering...'; \
        Register-PSRepository -Default -ErrorAction Stop | Out-Null; \
        Write-Host 'PSGallery registered successfully'; \
    }; \
    Write-Host 'Verifying PSGallery registration...'; \
    \$repo = Get-PSRepository -Name PSGallery -ErrorAction Stop; \
    Write-Host \"Found PSGallery: \$(\$repo.Name) at \$(\$repo.SourceLocation)\"; \
    Write-Host 'Setting PSGallery as trusted...'; \
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop; \
    Write-Host 'Installing Pester...'; \
    Install-Module -Name Pester -MinimumVersion 5.0 -Force -Scope AllUsers -AcceptLicense; \
    Write-Host 'Installing powershell-yaml and Posh-ACME...'; \
    Install-Module -Name powershell-yaml,Posh-ACME -Force -Scope AllUsers -AcceptLicense; \
    Write-Host 'Module installation complete' \
"

# Create working directory
WORKDIR /workspace

# Copy test files and modules
# Note: In practice, these will be mounted as volumes for live updates
COPY . /workspace/

# Default command runs all tests
CMD ["pwsh", "-Command", "\
    Import-Module Pester -Force; \
    $config = New-PesterConfiguration; \
    $config.Run.Path = './tests/unit', './tests/integration'; \
    $config.Run.Exit = $true; \
    $config.Output.Verbosity = 'Normal'; \
    Invoke-Pester -Configuration $config \
"]

# Health check (verifies Pester is available)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=1 \
    CMD pwsh -Command "Get-Module -ListAvailable Pester | Out-Null" || exit 1
