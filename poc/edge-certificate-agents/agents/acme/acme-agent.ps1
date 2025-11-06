#!/usr/bin/env pwsh
# ==============================================================================
# acme-agent.ps1 - ACME Agent (Modular Architecture)
# ==============================================================================
# This is a thin orchestration layer that coordinates the ACME certificate
# lifecycle workflow using modular PowerShell modules.
#
# Architecture: Thin Orchestration Layer
#   - Loads configuration (ConfigManager module)
#   - Initializes logging (Logger module)
#   - Registers workflow steps (AcmeWorkflow module)
#   - Starts workflow orchestrator (WorkflowOrchestrator module)
#   - NO business logic (all in modules)
#
# Design Benefits:
#   - Testable: Each module can be unit tested independently
#   - Maintainable: Business logic separated from orchestration
#   - Reusable: Modules can be shared across agents
#   - Flexible: Easy to add/remove/modify workflow steps
#   - Observable: Metrics and logging built into orchestrator
#
# Usage:
#   pwsh -File acme-agent.ps1
#
# Environment Variables:
#   - All configuration can be overridden via environment variables
#   - See config.yaml for available settings
# ==============================================================================

#Requires -Version 7.0

# ==============================================================================
# Module Imports
# ==============================================================================
$ErrorActionPreference = "Stop"
Write-Host "[ACME:Debug] Starting agent, PSScriptRoot=[$PSScriptRoot]"
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { "/agent" }
Write-Host "[ACME:Debug] scriptRoot=[$scriptRoot]"
$commonPath = Join-Path $scriptRoot "common"
Write-Host "[ACME:Debug] commonPath=[$commonPath]"

# Import common modules (order matters: Logger first, then dependencies, then higher-level modules)
Write-Host "[ACME:Debug] Importing Logger..."
Import-Module (Join-Path $commonPath "Logger.psm1") -Force
Write-Host "[ACME:Debug] Importing ConfigManager..."
Import-Module (Join-Path $commonPath "ConfigManager.psm1") -Force
Write-Host "[ACME:Debug] Importing CryptoHelper..."
Import-Module (Join-Path $commonPath "CryptoHelper.psm1") -Force
Write-Host "[ACME:Debug] Importing CertificateMonitor..."
Import-Module (Join-Path $commonPath "CertificateMonitor.psm1") -Force
Write-Host "[ACME:Debug] Importing CrlValidator..."
Import-Module (Join-Path $commonPath "CrlValidator.psm1") -Force
Write-Host "[ACME:Debug] Importing FileOperations..."
Import-Module (Join-Path $commonPath "FileOperations.psm1") -Force
Write-Host "[ACME:Debug] Importing WorkflowOrchestrator..."
Import-Module (Join-Path $commonPath "WorkflowOrchestrator.psm1") -Force

# Import Posh-ACME module (required for ACME protocol)
Write-Host "[ACME:Debug] Importing Posh-ACME..."
try {
    Import-Module Posh-ACME -Force -Global
    Write-Host "[ACME:Debug] Posh-ACME imported successfully"
} catch {
    Write-Host "[ACME:Error] Failed to import Posh-ACME: $($_.Exception.Message)" -ForegroundColor Red
    throw "Posh-ACME module is required. It should be installed in the Docker image."
}

# Import ACME-specific workflow module
Write-Host "[ACME:Debug] Importing AcmeWorkflow..."
Import-Module (Join-Path $scriptRoot "AcmeWorkflow.psm1") -Force

# ==============================================================================
# Configuration Loading
# ==============================================================================
Write-Host "[ACME:Main] ====== ACME Agent (Modular Architecture) ======" -ForegroundColor Cyan
Write-Host "[ACME:Main] Starting ACME certificate lifecycle agent..." -ForegroundColor Cyan

# Load configuration from YAML with environment variable overrides
$configPath = Join-Path $scriptRoot "config.yaml"
$config = Read-AgentConfig -ConfigFilePath $configPath

Write-Host "[ACME:Main] Configuration loaded from: $configPath" -ForegroundColor Green
Write-Host "[ACME:Main] Environment: $($config.environment)" -ForegroundColor Green
Write-Host "[ACME:Main] Check interval: $($config.check_interval_sec)s" -ForegroundColor Green
Write-Host "[ACME:Main] CRL enabled: $($config.crl.enabled)" -ForegroundColor Green

# ==============================================================================
# Logging Initialization
# ==============================================================================
# Initialize logger with configuration
$logFormat = $config.log_format ?? "text"
$logLevel = $config.log_level ?? "INFO"

Write-Host "[ACME:Main] Log format: $logFormat, Level: $logLevel" -ForegroundColor Green

# Logger is available globally in modules via Import-Module
# No need to pass logger instance explicitly

# ==============================================================================
# Workflow Initialization
# ==============================================================================
Write-Host "[ACME:Main] Initializing ACME workflow steps..." -ForegroundColor Cyan

# Register all ACME workflow steps
Initialize-AcmeWorkflowSteps

# Create workflow context
$workflowContext = New-WorkflowContext -Config $config

Write-Host "[ACME:Main] Workflow context created" -ForegroundColor Green

# ==============================================================================
# Workflow Execution
# ==============================================================================
# Define workflow steps in execution order
$workflowSteps = @(
    "Monitor",   # Check certificate status
    "Decide",    # Determine action (enroll/renew/skip)
    "Execute",   # Execute ACME protocol
    "Validate"   # Validate deployment and reload service
)

try {
    # Start workflow loop (runs indefinitely)
    # NOTE: Removed Write-Host calls here as they can block with Docker logging driver
    Start-WorkflowLoop `
        -Context $workflowContext `
        -Steps $workflowSteps `
        -IntervalSeconds $config.check_interval_sec `
        -MaxIterations 0  # 0 = infinite
}
catch {
    Write-Error "[ACME:Main] Workflow orchestrator failed: $_"
    exit 1
}
finally {
    # Display final metrics on shutdown
    Write-Host "[ACME:Main] ====== Workflow Metrics ======" -ForegroundColor Cyan
    $metrics = Get-WorkflowMetrics

    Write-Host "Total iterations: $($metrics.TotalIterations)" -ForegroundColor Yellow
    Write-Host "Successful: $($metrics.SuccessfulIterations)" -ForegroundColor Green
    Write-Host "Failed: $($metrics.FailedIterations)" -ForegroundColor Red
    Write-Host "Success rate: $($metrics.SuccessRate)%" -ForegroundColor Yellow
    Write-Host "Uptime: $($metrics.Uptime)" -ForegroundColor Yellow

    if ($metrics.StepMetrics.Count -gt 0) {
        Write-Host "`nStep execution times:" -ForegroundColor Cyan
        foreach ($stepName in $metrics.StepMetrics.Keys) {
            $stepMetric = $metrics.StepMetrics[$stepName]
            Write-Host "  ${stepName}: avg $($stepMetric.AverageExecutionTime.TotalMilliseconds)ms, count $($stepMetric.ExecutionCount)" -ForegroundColor Yellow
        }
    }

    Write-Host "[ACME:Main] Agent stopped" -ForegroundColor Cyan
}
