#!/usr/bin/env pwsh
# ==============================================================================
# est-agent.ps1 - EST Agent (Modular Architecture)
# ==============================================================================
# This is a thin orchestration layer that coordinates the EST certificate
# lifecycle workflow using modular PowerShell modules.
#
# Architecture: Thin Orchestration Layer
#   - Loads configuration (ConfigManager module)
#   - Initializes logging (Logger module)
#   - Registers workflow steps (EstWorkflow module)
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
#   pwsh -File est-agent.ps1
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
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { "/agent" }
$commonPath = Join-Path $scriptRoot "common"

# Import common modules (order matters: Logger first, then dependencies, then higher-level modules)
Import-Module (Join-Path $commonPath "Logger.psm1") -Force
Import-Module (Join-Path $commonPath "ConfigManager.psm1") -Force
Import-Module (Join-Path $commonPath "CryptoHelper.psm1") -Force
Import-Module (Join-Path $commonPath "CertificateMonitor.psm1") -Force
Import-Module (Join-Path $commonPath "CrlValidator.psm1") -Force
Import-Module (Join-Path $commonPath "FileOperations.psm1") -Force
Import-Module (Join-Path $commonPath "WorkflowOrchestrator.psm1") -Force

# Import EST-specific modules (required for EST protocol)
Import-Module (Join-Path $scriptRoot "EstClient.psm1") -Force -Global
Import-Module (Join-Path $scriptRoot "BootstrapTokenManager.psm1") -Force -Global

# Import EST-specific workflow module
Import-Module (Join-Path $scriptRoot "EstWorkflow.psm1") -Force

# ==============================================================================
# Configuration Loading
# ==============================================================================
Write-Host "[EST:Main] ====== EST Agent (Modular Architecture) ======" -ForegroundColor Cyan
Write-Host "[EST:Main] Starting EST certificate lifecycle agent..." -ForegroundColor Cyan

# Load configuration from YAML with environment variable overrides
$configPath = Join-Path $scriptRoot "config.yaml"
$config = Read-AgentConfig -ConfigFilePath $configPath

Write-Host "[EST:Main] Configuration loaded from: $configPath" -ForegroundColor Green
Write-Host "[EST:Main] Environment: $($config.environment)" -ForegroundColor Green
Write-Host "[EST:Main] Check interval: $($config.check_interval_sec)s" -ForegroundColor Green
Write-Host "[EST:Main] CRL enabled: $($config.crl.enabled)" -ForegroundColor Green
Write-Host "[EST:Main] Device name: $($config.device.name)" -ForegroundColor Green

# ==============================================================================
# Logging Initialization
# ==============================================================================
# Initialize logger with configuration
$logFormat = $config.log_format ?? "text"
$logLevel = $config.log_level ?? "INFO"

Write-Host "[EST:Main] Log format: $logFormat, Level: $logLevel" -ForegroundColor Green

# Logger is available globally in modules via Import-Module
# No need to pass logger instance explicitly

# ==============================================================================
# Workflow Initialization
# ==============================================================================
Write-Host "[EST:Main] Initializing EST workflow steps..." -ForegroundColor Cyan

# Register all EST workflow steps
Initialize-EstWorkflowSteps

# Create workflow context
$workflowContext = New-WorkflowContext -Config $config

Write-Host "[EST:Main] Workflow context created" -ForegroundColor Green

# ==============================================================================
# Workflow Execution
# ==============================================================================
Write-Host "[EST:Main] Starting workflow orchestrator..." -ForegroundColor Cyan
Write-Host "[EST:Main] Press Ctrl+C to stop" -ForegroundColor Yellow

# Define workflow steps in execution order
$workflowSteps = @(
    "Monitor",   # Check certificate status
    "Decide",    # Determine action (enroll/reenroll/skip)
    "Execute",   # Execute EST protocol
    "Validate"   # Validate deployment
)

try {
    # Start workflow loop (runs indefinitely)
    Start-WorkflowLoop `
        -Context $workflowContext `
        -Steps $workflowSteps `
        -IntervalSeconds $config.check_interval_sec `
        -MaxIterations 0  # 0 = infinite
}
catch {
    Write-Error "[EST:Main] Workflow orchestrator failed: $_"
    exit 1
}
finally {
    # Display final metrics on shutdown
    Write-Host "[EST:Main] ====== Workflow Metrics ======" -ForegroundColor Cyan
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

    Write-Host "[EST:Main] Agent stopped" -ForegroundColor Cyan
}
