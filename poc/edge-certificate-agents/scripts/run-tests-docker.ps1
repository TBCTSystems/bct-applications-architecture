<#
.SYNOPSIS
    ECA Docker Test Runner Script (PowerShell)

.DESCRIPTION
    Runs all tests inside Docker containers for consistent test environment.
    No local PowerShell installation required (Docker runs pwsh inside container)!

    This is the PowerShell version for Windows developers.

.PARAMETER UnitOnly
    Run only unit tests

.PARAMETER IntegrationOnly
    Run only integration tests

.PARAMETER Coverage
    Generate code coverage report

.PARAMETER Build
    Rebuild test runner Docker image before running tests

.PARAMETER Help
    Show help message

.EXAMPLE
    .\scripts\run-tests-docker.ps1
    Run all tests in Docker

.EXAMPLE
    .\scripts\run-tests-docker.ps1 -UnitOnly
    Run only unit tests in Docker

.EXAMPLE
    .\scripts\run-tests-docker.ps1 -Build
    Rebuild test image and run all tests

.EXAMPLE
    .\scripts\run-tests-docker.ps1 -Coverage
    Run all tests with code coverage report

.NOTES
    Advantages of Docker test runner:
      - No local PowerShell installation needed
      - Consistent test environment across all machines
      - Isolated from host system
      - Works identically in CI/CD and locally

    Requirements:
      - Docker Desktop (for Windows)
      - Docker Compose v2

    Exit Codes:
      0 - All tests passed
      1 - One or more tests failed
      2 - Script error or missing dependencies
#>

[CmdletBinding()]
param(
    [switch]$UnitOnly,
    [switch]$IntegrationOnly,
    [switch]$Coverage,
    [switch]$Build,
    [switch]$Help
)

# ============================================
# Configuration
# ============================================

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
$ProjectDir = Split-Path -Parent $ScriptDir

# ============================================
# Helper Functions
# ============================================

function Write-Header {
    param([string]$Message)

    Write-Host ""
    Write-Host ("=" * 59) -ForegroundColor Blue
    Write-Host $Message -ForegroundColor Blue
    Write-Host ("=" * 59) -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)

    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Failure {
    param([string]$Message)

    Write-Host "✗ $Message" -ForegroundColor Red
}

function Write-Details {
    param([string]$Message)

    Write-Host "  $Message"
}

function Show-Usage {
    $usage = @"
ECA Docker Test Runner Script (PowerShell)

Usage: .\scripts\run-tests-docker.ps1 [OPTIONS]

Options:
  -UnitOnly          Run only unit tests
  -IntegrationOnly   Run only integration tests
  -Coverage          Generate code coverage report
  -Build             Rebuild test runner Docker image
  -Help              Show this help message

Examples:
  .\scripts\run-tests-docker.ps1                  # Run all tests in Docker
  .\scripts\run-tests-docker.ps1 -UnitOnly        # Run only unit tests
  .\scripts\run-tests-docker.ps1 -Build           # Rebuild image and run all tests
  .\scripts\run-tests-docker.ps1 -Coverage        # Run all tests with coverage report

Advantages of Docker test runner:
  - No local PowerShell installation needed
  - Consistent test environment across all machines
  - Isolated from host system
  - Works identically in CI/CD and locally

"@
    Write-Host $usage
}

# ============================================
# Dependency Checks
# ============================================

function Test-Dependencies {
    Write-Header "Checking Dependencies"

    # Check for Docker
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $dockerCmd) {
        Write-Failure "Docker is not installed"
        Write-Host "Please install Docker Desktop from https://docs.docker.com/desktop/install/windows-install/"
        exit 2
    }

    try {
        $dockerVersion = docker --version
        Write-Details "Found: $dockerVersion"
    } catch {
        Write-Failure "Docker is installed but not running"
        Write-Host "Please start Docker Desktop"
        exit 2
    }

    # Check for Docker Compose
    try {
        $composeVersion = docker compose version
        Write-Details "Found: $composeVersion"
    } catch {
        Write-Failure "Docker Compose is not available"
        Write-Host "Please install Docker Compose v2"
        exit 2
    }

    Write-Success "All dependencies present"
}

# ============================================
# Docker Image Management
# ============================================

function Build-TestImage {
    Write-Header "Building Test Runner Image"

    Push-Location $ProjectDir

    try {
        $process = Start-Process -FilePath "docker" -ArgumentList "compose", "build", "test-runner" -NoNewWindow -Wait -PassThru

        if ($process.ExitCode -eq 0) {
            Write-Success "Test runner image built successfully"
        } else {
            Write-Failure "Failed to build test runner image"
            exit 1
        }
    } catch {
        Write-Failure "Failed to build test runner image: $($_.Exception.Message)"
        exit 1
    } finally {
        Pop-Location
    }
}

function Test-TestImage {
    # Check if image exists
    $image = docker images --format "{{.Repository}}" | Where-Object { $_ -match "eca-test-runner" }

    return ($null -ne $image)
}

function Invoke-EnsureTestImage {
    if ($Build) {
        Build-TestImage
    } elseif (-not (Test-TestImage)) {
        Write-Details "Test runner image not found, building..."
        Build-TestImage
    } else {
        Write-Details "Using existing test runner image"
    }
}

# ============================================
# Test Execution
# ============================================

function Invoke-UnitTestsDocker {
    Write-Header "Running Unit Tests (Docker)"

    Push-Location $ProjectDir

    try {
        $coverageArg = if ($Coverage) { "-e", "GENERATE_COVERAGE=true" } else { @() }

        $pesterCommand = @'
$config = New-PesterConfiguration
$config.Run.Path = './tests/unit'
$config.Run.Exit = $true
$config.Output.Verbosity = 'Normal'

if ($env:GENERATE_COVERAGE -eq 'true') {
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = @(
        './agents/acme/AcmeClient.psm1',
        './agents/est/EstClient.psm1',
        './agents/est/BootstrapTokenManager.psm1'
    )
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
    $config.CodeCoverage.OutputPath = './tests/coverage.xml'
}

Invoke-Pester -Configuration $config
'@

        $dockerArgs = @(
            "compose", "run", "--rm"
        ) + $coverageArg + @(
            "test-runner", "pwsh", "-Command", $pesterCommand
        )

        $process = Start-Process -FilePath "docker" -ArgumentList $dockerArgs -NoNewWindow -Wait -PassThru

        if ($process.ExitCode -eq 0) {
            Write-Success "Unit tests passed"
            return 0
        } else {
            Write-Failure "Unit tests failed"
            return 1
        }
    } catch {
        Write-Failure "Failed to run unit tests: $($_.Exception.Message)"
        return 1
    } finally {
        Pop-Location
    }
}

function Invoke-IntegrationTestsDocker {
    Write-Header "Running Integration Tests (Docker)"

    Push-Location $ProjectDir

    try {
        # Ensure PKI services are running
        Write-Details "Starting PKI infrastructure..."
        docker compose up -d pki openxpki-web openxpki-client openxpki-server | Out-Null

        # Wait for services to be healthy
        Write-Details "Waiting for PKI services to be healthy..."
        $maxWait = 60
        $elapsed = 0

        while ($elapsed -lt $maxWait) {
            $pkiStatus = docker compose ps | Select-String "eca-pki.*healthy"
            if ($pkiStatus) {
                break
            }
            Start-Sleep -Seconds 5
            $elapsed += 5
            Write-Details "Waiting... ($elapsed s/$maxWait s)"
        }

        # Check if integration tests exist
        if (-not (Test-Path './tests/integration')) {
            Write-Details "No integration tests directory found (./tests/integration)"
            Write-Details "Skipping integration tests"
            return 0
        }

        $integrationTests = Get-ChildItem -Path './tests/integration' -Filter '*.Tests.ps1' -ErrorAction SilentlyContinue

        if ($integrationTests.Count -eq 0) {
            Write-Details "No integration tests found (./tests/integration/*.Tests.ps1)"
            Write-Details "Skipping integration tests"
            return 0
        }

        $pesterCommand = @'
$config = New-PesterConfiguration
$config.Run.Path = './tests/integration'
$config.Run.Exit = $true
$config.Output.Verbosity = 'Normal'

Invoke-Pester -Configuration $config
'@

        $dockerArgs = @(
            "compose", "run", "--rm",
            "test-runner", "pwsh", "-Command", $pesterCommand
        )

        $process = Start-Process -FilePath "docker" -ArgumentList $dockerArgs -NoNewWindow -Wait -PassThru

        if ($process.ExitCode -eq 0) {
            Write-Success "Integration tests passed"
            return 0
        } else {
            Write-Failure "Integration tests failed"
            return 1
        }
    } catch {
        Write-Failure "Failed to run integration tests: $($_.Exception.Message)"
        return 1
    } finally {
        Pop-Location
    }
}

# ============================================
# Main Execution
# ============================================

function Main {
    if ($Help) {
        Show-Usage
        exit 0
    }

    # Determine which tests to run
    $runUnitTests = $true
    $runIntegrationTests = $true

    if ($UnitOnly) {
        $runIntegrationTests = $false
    }

    if ($IntegrationOnly) {
        $runUnitTests = $false
    }

    # Start tests
    Write-Header "ECA Docker Test Suite"
    Write-Host "Running tests in isolated Docker containers"

    # Check dependencies
    Test-Dependencies

    # Ensure test image exists
    Invoke-EnsureTestImage

    $unitResult = 0
    $integrationResult = 0

    # Run unit tests
    if ($runUnitTests) {
        $unitResult = Invoke-UnitTestsDocker
    }

    # Run integration tests
    if ($runIntegrationTests) {
        $integrationResult = Invoke-IntegrationTestsDocker
    }

    # Summary
    Write-Header "Test Summary"

    if ($runUnitTests) {
        if ($unitResult -eq 0) {
            Write-Success "Unit Tests: PASSED"
        } else {
            Write-Failure "Unit Tests: FAILED"
        }
    }

    if ($runIntegrationTests) {
        if ($integrationResult -eq 0) {
            Write-Success "Integration Tests: PASSED"
        } else {
            Write-Failure "Integration Tests: FAILED"
        }
    }

    if ($Coverage -and (Test-Path "$ProjectDir/tests/coverage.xml")) {
        Write-Host ""
        Write-Details "Coverage report generated: tests/coverage.xml"
    } elseif ($Coverage) {
        Write-Host ""
        Write-Details "Coverage report not found (may need to extract from container)"
    }

    # Exit with appropriate code
    if (($unitResult -ne 0) -or ($integrationResult -ne 0)) {
        Write-Host ""
        Write-Failure "Some tests failed. Please review output above."
        exit 1
    } else {
        Write-Host ""
        Write-Success "All tests passed!"
        exit 0
    }
}

# Run main function
Main
