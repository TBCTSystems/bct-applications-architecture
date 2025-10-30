<#
.SYNOPSIS
    ECA Test Runner Script (PowerShell)

.DESCRIPTION
    Runs all unit and integration tests for the ECA PoC project using Pester.

    This is the native PowerShell version for Windows developers.

.PARAMETER UnitOnly
    Run only unit tests

.PARAMETER IntegrationOnly
    Run only integration tests

.PARAMETER Coverage
    Generate code coverage report

.PARAMETER Verbose
    Show verbose test output

.PARAMETER Help
    Show help message

.EXAMPLE
    .\scripts\run-tests.ps1
    Run all tests

.EXAMPLE
    .\scripts\run-tests.ps1 -UnitOnly
    Run only unit tests

.EXAMPLE
    .\scripts\run-tests.ps1 -Coverage
    Run all tests with code coverage report

.EXAMPLE
    .\scripts\run-tests.ps1 -UnitOnly -Verbose
    Run unit tests with verbose output

.NOTES
    Requires PowerShell 7.0+ and Pester 5.0+

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
    [switch]$AutoStartIntegration,
    [switch]$Help
)

# ============================================
# Configuration
# ============================================

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
$ProjectDir = Split-Path -Parent $ScriptDir
$IntegrationServices = @('pki', 'openxpki-db', 'openxpki-server', 'openxpki-client', 'openxpki-web')

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
ECA Test Runner Script (PowerShell)

Usage: .\scripts\run-tests.ps1 [OPTIONS]

Options:
  -UnitOnly          Run only unit tests
  -IntegrationOnly   Run only integration tests
  -Coverage          Generate code coverage report
  -AutoStartIntegration  Automatically start Docker PKI stack for integration tests
  -Verbose           Show verbose test output
  -Help              Show this help message

Examples:
  .\scripts\run-tests.ps1                    # Run all tests
  .\scripts\run-tests.ps1 -UnitOnly          # Run only unit tests
  .\scripts\run-tests.ps1 -IntegrationOnly   # Run only integration tests
  .\scripts\run-tests.ps1 -Coverage          # Run all tests with coverage report
  .\scripts\run-tests.ps1 -UnitOnly -Verbose # Run unit tests with verbose output

"@
    Write-Host $usage
}

# ============================================
# Dependency Checks
# ============================================

function Test-Dependencies {
    Write-Header "Checking Dependencies"

    # Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -lt 7) {
        Write-Failure "PowerShell 7.0+ is required (current: $psVersion)"
        Write-Host "Please install PowerShell 7.0+ from https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell"
        exit 2
    }
    Write-Details "Found: PowerShell $psVersion"

    # Check for Pester module
    $pesterModule = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1

    if (-not $pesterModule) {
        Write-Failure "Pester module is not installed"
        Write-Host "Installing Pester module..."
        try {
            Install-Module -Name Pester -MinimumVersion 5.0 -Force -Scope CurrentUser -AllowClobber
            Write-Success "Pester module installed successfully"
            $pesterModule = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1
        } catch {
            Write-Failure "Failed to install Pester module: $($_.Exception.Message)"
            exit 2
        }
    }

    if ($pesterModule.Version.Major -lt 5) {
        Write-Failure "Pester 5.0+ is required (current: $($pesterModule.Version))"
        Write-Host "Installing Pester 5.0+..."
        try {
            Install-Module -Name Pester -MinimumVersion 5.0 -Force -Scope CurrentUser -AllowClobber
            Write-Success "Pester module updated successfully"
        } catch {
            Write-Failure "Failed to update Pester module: $($_.Exception.Message)"
            exit 2
        }
    } else {
        Write-Details "Found: Pester $($pesterModule.Version)"
    }

    Write-Success "All dependencies present"
}

function Invoke-DockerCompose {
    param([string[]]$Arguments)

    Push-Location $ProjectDir
    try {
        & docker compose @Arguments
    }
    finally {
        Pop-Location
    }
}

function Ensure-DockerAvailable {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker CLI is required to run integration tests. Install Docker Desktop/Engine."
    }

    try {
        docker compose version | Out-Null
    }
    catch {
        throw "Docker Compose v2 is required to manage integration services."
    }
}

function Wait-ServiceReady {
    param(
        [string]$Service,
        [int]$TimeoutSeconds = 240
    )

    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $containerId = Invoke-DockerCompose -Arguments @('ps', '-q', $Service) | Select-Object -First 1
        if ($containerId) {
            $status = docker inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' $containerId 2>$null
            if ($status -match 'healthy' -or $status -match 'running') {
                return $true
            }
        }

        Start-Sleep -Seconds 5
        $elapsed += 5
    }

    return $false
}

function Prepare-IntegrationStack {
    Ensure-DockerAvailable

    $running = @(Invoke-DockerCompose -Arguments @('ps', '--services', '--filter', 'status=running'))
    $missing = @()
    foreach ($svc in $IntegrationServices) {
        if (-not ($running -contains $svc)) {
            $missing += $svc
        }
    }

    if ($missing.Count -eq 0) {
        Write-Details "Integration services already running"
        return $true
    }

    if ($AutoStartIntegration) {
        Write-Details "Starting integration services via docker compose up -d $($IntegrationServices -join ' ')"
        Invoke-DockerCompose -Arguments (@('up', '-d') + $IntegrationServices) | Out-Null

        foreach ($svc in $IntegrationServices) {
            if (-not (Wait-ServiceReady -Service $svc)) {
                Write-Failure "Service $svc did not become ready"
                return $false
            }
        }

        Write-Success "Integration services ready"
        return $true
    }

    Write-Failure "Integration services are not running: $($missing -join ', ')"
    Write-Host "Start them with: docker compose up -d $($IntegrationServices -join ' ')"
    Write-Host "Or rerun this script with -AutoStartIntegration"
    return $false
}

# ============================================
# Test Execution
# ============================================

function Invoke-UnitTests {
    Write-Header "Running Unit Tests"

    Push-Location $ProjectDir

    try {
        $config = New-PesterConfiguration

        $config.Run.Path = './tests/unit'
        $config.Run.Exit = $false
        $config.Run.PassThru = $true
        $config.Output.Verbosity = if ($VerbosePreference -eq 'Continue') { 'Detailed' } else { 'Normal' }

        if ($Coverage) {
            Write-Details "Generating code coverage report..."

            $config.CodeCoverage.Enabled = $true
            $config.CodeCoverage.Path = @(
                './agents/acme/AcmeClient.psm1',
                './agents/est/EstClient.psm1',
                './agents/est/BootstrapTokenManager.psm1'
            )
            $config.CodeCoverage.OutputFormat = 'JaCoCo'
            $config.CodeCoverage.OutputPath = './tests/coverage.xml'
        }

        # Temporarily allow errors during test execution
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"

        $result = Invoke-Pester -Configuration $config

        $ErrorActionPreference = $previousErrorActionPreference

        if ($null -ne $result -and $result.FailedCount -eq 0) {
            Write-Success "Unit tests passed"
            return 0
        } else {
            $failedCount = if ($null -ne $result) { $result.FailedCount } else { "unknown" }
            Write-Failure "Unit tests failed (FailedCount: $failedCount)"
            return 1
        }
    } catch {
        Write-Failure "Unit tests failed with error: $($_.Exception.Message)"
        return 1
    } finally {
        Pop-Location
    }
}

function Invoke-IntegrationTests {
    Write-Header "Running Integration Tests"

    Push-Location $ProjectDir

    try {
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
    }
    finally {
        Pop-Location
    }

    if (-not (Prepare-IntegrationStack)) {
        return 1
    }

    $verbosity = if ($VerbosePreference -eq 'Continue') { 'Detailed' } else { 'Normal' }
    $pesterScript = @'
$config = New-PesterConfiguration
$config.Run.Path = './tests/integration'
$config.Run.Exit = $true
$config.Output.Verbosity = '__VERBOSITY__'

Invoke-Pester -Configuration $config
'@
    $pesterScript = $pesterScript -replace '__VERBOSITY__', $verbosity

    Invoke-DockerCompose -Arguments @('run', '--rm', 'test-runner', 'pwsh', '-Command', $pesterScript) | Out-Null
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Success "Integration tests passed"
        return 0
    }

    Write-Failure "Integration tests failed (exit code: $exitCode)"
    return 1
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
    Write-Header "ECA Test Suite"
    Write-Host "Testing PowerShell modules with Pester"

    # Check dependencies
    Test-Dependencies

    $unitResult = 0
    $integrationResult = 0

    # Run unit tests
    if ($runUnitTests) {
        $unitResult = Invoke-UnitTests
    }

    # Run integration tests
    if ($runIntegrationTests) {
        $integrationResult = Invoke-IntegrationTests
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
