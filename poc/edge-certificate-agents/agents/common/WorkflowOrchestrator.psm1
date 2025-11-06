# ==============================================================================
# WorkflowOrchestrator.psm1 - Generic Workflow Orchestration Module
# ==============================================================================
# This module provides a state-of-the-art workflow orchestration framework
# for autonomous certificate lifecycle management agents.
#
# Architecture Pattern: Thin Orchestration Layer
#   - Separates workflow execution from business logic
#   - Provides reusable state machine for certificate lifecycle
#   - Enables configuration-driven agent behavior
#   - Facilitates testing and maintainability
#
# Functions:
#   - New-WorkflowContext: Creates workflow execution context
#   - Invoke-WorkflowStep: Executes a single workflow step
#   - Start-WorkflowLoop: Main orchestration loop with error handling
#   - Register-WorkflowStep: Registers custom workflow steps
#   - Get-WorkflowMetrics: Returns workflow execution metrics
#
# Usage:
#   Import-Module ./WorkflowOrchestrator.psm1
#   $context = New-WorkflowContext -Config $config
#   Register-WorkflowStep -Name "Monitor" -ScriptBlock { ... }
#   Start-WorkflowLoop -Context $context
# ==============================================================================

using namespace System.Collections.Generic

# ==============================================================================
# Module-level State
# ==============================================================================
$script:RegisteredSteps = @{}
$script:WorkflowMetrics = @{
    TotalIterations = 0
    SuccessfulIterations = 0
    FailedIterations = 0
    StepExecutionTimes = @{}
    LastError = $null
    StartTime = $null
}

# ==============================================================================
# New-WorkflowContext
# ==============================================================================
# Creates a new workflow execution context with configuration and state
#
# Parameters:
#   -Config: Configuration hashtable (from ConfigManager)
#   -Logger: Logger instance (optional, uses Write-Host if not provided)
#   -AdditionalState: Additional state data to include in context
#
# Returns: Hashtable containing workflow context
# ==============================================================================
function New-WorkflowContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter(Mandatory = $false)]
        [object]$Logger = $null,

        [Parameter(Mandatory = $false)]
        [hashtable]$AdditionalState = @{}
    )

    $context = @{
        Config = $Config
        Logger = $Logger
        State = @{
            CurrentStep = $null
            IterationCount = 0
            LastExecutionTime = $null
            CertificateStatus = @{
                Exists = $false
                ExpiryDate = $null
                LifetimePercentage = 0
                RenewalRequired = $false
                Revoked = $false
            }
            WorkflowStatus = "Initializing"
            ErrorCount = 0
            LastError = $null
        }
        Metrics = @{
            StepTimings = [List[object]]::new()
            IterationTimings = [List[object]]::new()
        }
    }

    # Merge additional state
    foreach ($key in $AdditionalState.Keys) {
        $context.State[$key] = $AdditionalState[$key]
    }

    # Initialize metrics start time
    if ($null -eq $script:WorkflowMetrics.StartTime) {
        $script:WorkflowMetrics.StartTime = Get-Date
    }

    Write-Verbose "[Workflow] Context created with config: $($Config.Keys -join ', ')"
    return $context
}

# ==============================================================================
# Register-WorkflowStep
# ==============================================================================
# Registers a workflow step with a name and execution script block
#
# Parameters:
#   -Name: Step name (must be unique)
#   -ScriptBlock: Script block to execute for this step
#   -Description: Optional description of the step
#   -ContinueOnError: Whether to continue workflow if step fails
#
# Returns: None
# ==============================================================================
function Register-WorkflowStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [string]$Description = "",

        [Parameter(Mandatory = $false)]
        [bool]$ContinueOnError = $false
    )

    if ($script:RegisteredSteps.ContainsKey($Name)) {
        Write-Warning "[Workflow] Step '$Name' already registered, overwriting"
    }

    $script:RegisteredSteps[$Name] = @{
        ScriptBlock = $ScriptBlock
        Description = $Description
        ContinueOnError = $ContinueOnError
        ExecutionCount = 0
        LastExecutionTime = $null
        TotalExecutionTime = [TimeSpan]::Zero
    }

    Write-Verbose "[Workflow] Registered step: $Name"
}

# ==============================================================================
# Invoke-WorkflowStep
# ==============================================================================
# Executes a registered workflow step with error handling and metrics
#
# Parameters:
#   -Name: Step name to execute
#   -Context: Workflow context (passed to script block)
#
# Returns: Hashtable with execution results
# ==============================================================================
function Invoke-WorkflowStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    if (-not $script:RegisteredSteps.ContainsKey($Name)) {
        throw "Workflow step '$Name' is not registered"
    }

    $step = $script:RegisteredSteps[$Name]
    $context.State.CurrentStep = $Name

    $result = @{
        StepName = $Name
        Success = $false
        Output = $null
        Error = $null
        ExecutionTime = $null
        Timestamp = Get-Date
    }

    try {
        Write-Verbose "[Workflow] Executing step: $Name"

        # Measure execution time
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        # Execute step with context
        $stepOutput = & $step.ScriptBlock $Context

        $sw.Stop()
        $result.ExecutionTime = $sw.Elapsed
        $result.Output = $stepOutput
        $result.Success = $true

        # Update step metrics
        $step.ExecutionCount++
        $step.LastExecutionTime = $result.ExecutionTime
        $step.TotalExecutionTime += $result.ExecutionTime

        # Update global metrics
        if (-not $script:WorkflowMetrics.StepExecutionTimes.ContainsKey($Name)) {
            $script:WorkflowMetrics.StepExecutionTimes[$Name] = [List[TimeSpan]]::new()
        }
        $script:WorkflowMetrics.StepExecutionTimes[$Name].Add($result.ExecutionTime)

        Write-Verbose "[Workflow] Step '$Name' completed in $($result.ExecutionTime.TotalMilliseconds)ms"
    }
    catch {
        $sw.Stop()
        $result.ExecutionTime = $sw.Elapsed
        $result.Success = $false
        $result.Error = $_

        $context.State.ErrorCount++
        $context.State.LastError = $_
        $script:WorkflowMetrics.LastError = $_

        if ($step.ContinueOnError) {
            Write-Warning "[Workflow] Step '$Name' failed but continuing: $_"
        } else {
            Write-Error "[Workflow] Step '$Name' failed: $_"
            throw
        }
    }

    # Add to context metrics
    $context.Metrics.StepTimings.Add($result)

    return $result
}

# ==============================================================================
# Start-WorkflowLoop
# ==============================================================================
# Main workflow orchestration loop with error handling and sleep intervals
#
# Parameters:
#   -Context: Workflow execution context
#   -Steps: Array of step names to execute in order
#   -IntervalSeconds: Sleep interval between iterations
#   -MaxIterations: Maximum iterations (0 = infinite)
#
# Returns: None (runs until terminated or max iterations reached)
# ==============================================================================
function Start-WorkflowLoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [string[]]$Steps,

        [Parameter(Mandatory = $false)]
        [int]$IntervalSeconds = 60,

        [Parameter(Mandatory = $false)]
        [int]$MaxIterations = 0
    )

    $context.State.WorkflowStatus = "Running"

    Write-Verbose "[Workflow] Starting workflow loop with steps: $($Steps -join ', ')"
    Write-Verbose "[Workflow] Interval: ${IntervalSeconds}s, Max iterations: $MaxIterations"

    $iterationCount = 0

    while ($true) {
        $iterationCount++
        $context.State.IterationCount = $iterationCount
        $script:WorkflowMetrics.TotalIterations++

        $iterationStartTime = Get-Date
        $iterationSuccess = $true

        try {
            Write-Verbose "[Workflow] ========== Iteration $iterationCount =========="

            # Execute each step in sequence
            foreach ($stepName in $Steps) {
                try {
                    $stepResult = Invoke-WorkflowStep -Name $stepName -Context $Context

                    if (-not $stepResult.Success) {
                        $iterationSuccess = $false

                        # Check if we should stop on this error
                        $step = $script:RegisteredSteps[$stepName]
                        if (-not $step.ContinueOnError) {
                            Write-Error "[Workflow] Critical step failed, stopping iteration"
                            break
                        }
                    }
                }
                catch {
                    Write-Error "[Workflow] Step '$stepName' threw exception: $_"
                    $iterationSuccess = $false
                    break
                }
            }

            # Update iteration metrics
            if ($iterationSuccess) {
                $script:WorkflowMetrics.SuccessfulIterations++
            } else {
                $script:WorkflowMetrics.FailedIterations++
            }

            $iterationEndTime = Get-Date
            $iterationDuration = $iterationEndTime - $iterationStartTime

            $context.Metrics.IterationTimings.Add(@{
                Iteration = $iterationCount
                StartTime = $iterationStartTime
                EndTime = $iterationEndTime
                Duration = $iterationDuration
                Success = $iterationSuccess
            })

            Write-Verbose "[Workflow] Iteration $iterationCount completed in $($iterationDuration.TotalSeconds)s"

            # Check if we've reached max iterations
            if ($MaxIterations -gt 0 -and $iterationCount -ge $MaxIterations) {
                Write-Verbose "[Workflow] Reached max iterations ($MaxIterations), stopping"
                break
            }

            # Sleep before next iteration
            Write-Verbose "[Workflow] Sleeping for ${IntervalSeconds}s..."
            Start-Sleep -Seconds $IntervalSeconds
        }
        catch {
            Write-Error "[Workflow] Iteration $iterationCount failed with exception: $_"
            $script:WorkflowMetrics.FailedIterations++
            $context.State.WorkflowStatus = "Error"

            # Sleep before retry
            Start-Sleep -Seconds $IntervalSeconds
        }
    }

    $context.State.WorkflowStatus = "Stopped"
    Write-Verbose "[Workflow] Workflow loop terminated after $iterationCount iterations"
}

# ==============================================================================
# Get-WorkflowMetrics
# ==============================================================================
# Returns aggregated workflow execution metrics
#
# Parameters: None
#
# Returns: Hashtable containing workflow metrics
# ==============================================================================
function Get-WorkflowMetrics {
    [CmdletBinding()]
    param()

    $uptime = if ($script:WorkflowMetrics.StartTime) {
        (Get-Date) - $script:WorkflowMetrics.StartTime
    } else {
        [TimeSpan]::Zero
    }

    $metrics = @{
        Uptime = $uptime
        TotalIterations = $script:WorkflowMetrics.TotalIterations
        SuccessfulIterations = $script:WorkflowMetrics.SuccessfulIterations
        FailedIterations = $script:WorkflowMetrics.FailedIterations
        SuccessRate = if ($script:WorkflowMetrics.TotalIterations -gt 0) {
            [math]::Round(($script:WorkflowMetrics.SuccessfulIterations / $script:WorkflowMetrics.TotalIterations) * 100, 2)
        } else {
            0
        }
        RegisteredSteps = $script:RegisteredSteps.Count
        StepMetrics = @{}
        LastError = $script:WorkflowMetrics.LastError
    }

    # Add per-step metrics
    foreach ($stepName in $script:RegisteredSteps.Keys) {
        $step = $script:RegisteredSteps[$stepName]
        $metrics.StepMetrics[$stepName] = @{
            ExecutionCount = $step.ExecutionCount
            TotalExecutionTime = $step.TotalExecutionTime
            AverageExecutionTime = if ($step.ExecutionCount -gt 0) {
                [TimeSpan]::FromTicks($step.TotalExecutionTime.Ticks / $step.ExecutionCount)
            } else {
                [TimeSpan]::Zero
            }
            LastExecutionTime = $step.LastExecutionTime
        }
    }

    return $metrics
}

# ==============================================================================
# Reset-WorkflowMetrics
# ==============================================================================
# Resets all workflow metrics (useful for testing)
#
# Parameters: None
#
# Returns: None
# ==============================================================================
function Reset-WorkflowMetrics {
    [CmdletBinding()]
    param()

    $script:WorkflowMetrics = @{
        TotalIterations = 0
        SuccessfulIterations = 0
        FailedIterations = 0
        StepExecutionTimes = @{}
        LastError = $null
        StartTime = Get-Date
    }

    foreach ($stepName in $script:RegisteredSteps.Keys) {
        $script:RegisteredSteps[$stepName].ExecutionCount = 0
        $script:RegisteredSteps[$stepName].TotalExecutionTime = [TimeSpan]::Zero
        $script:RegisteredSteps[$stepName].LastExecutionTime = $null
    }

    Write-Verbose "[Workflow] Metrics reset"
}

# ==============================================================================
# Export module functions
# ==============================================================================
Export-ModuleMember -Function @(
    'New-WorkflowContext',
    'Register-WorkflowStep',
    'Invoke-WorkflowStep',
    'Start-WorkflowLoop',
    'Get-WorkflowMetrics',
    'Reset-WorkflowMetrics'
)
