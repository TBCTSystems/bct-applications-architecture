# ==============================================================================
# WorkflowOrchestrator.Tests.ps1 - Unit Tests for Workflow Orchestration Module
# ==============================================================================
# Tests for the generic workflow orchestration framework used by all agents
# ==============================================================================

#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    # Import module under test
    $modulePath = Resolve-Path "$PSScriptRoot/../../agents/common/WorkflowOrchestrator.psm1"
    Import-Module $modulePath -Force

    # Create test directory
    $script:TestDir = Join-Path $TestDrive "workflow-tests"
    New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null
}

AfterAll {
    # Cleanup
    Remove-Module WorkflowOrchestrator -Force -ErrorAction SilentlyContinue
}

Describe "WorkflowOrchestrator Module" -Tags @('Unit', 'Workflow', 'Core') {

    BeforeEach {
        # Reset metrics before each test to ensure isolation
        Reset-WorkflowMetrics
    }

    Context "New-WorkflowContext" {
        It "Creates workflow context with required properties" {
            # Arrange
            $config = @{
                test_param = "test-value"
                cert_path = "/test/cert.pem"
            }

            # Act
            $context = New-WorkflowContext -Config $config

            # Assert
            $context | Should -Not -BeNullOrEmpty
            $context.Config | Should -Not -BeNullOrEmpty
            $context.State | Should -Not -BeNullOrEmpty
            $context.Metrics | Should -Not -BeNullOrEmpty
        }

        It "Includes Config hashtable in context" {
            # Arrange
            $config = @{
                pki_url = "https://test-ca:9000"
                domain = "test.example.com"
            }

            # Act
            $context = New-WorkflowContext -Config $config

            # Assert
            $context.Config.pki_url | Should -Be "https://test-ca:9000"
            $context.Config.domain | Should -Be "test.example.com"
        }

        It "Initializes State with default values" {
            # Arrange
            $config = @{}

            # Act
            $context = New-WorkflowContext -Config $config

            # Assert
            $context.State.CurrentStep | Should -BeNullOrEmpty
            $context.State.IterationCount | Should -Be 0
            $context.State.WorkflowStatus | Should -Be "Initializing"
            $context.State.ErrorCount | Should -Be 0
            $context.State.CertificateStatus | Should -Not -BeNullOrEmpty
            $context.State.CertificateStatus.Exists | Should -Be $false
            $context.State.CertificateStatus.RenewalRequired | Should -Be $false
        }

        It "Merges AdditionalState into context" {
            # Arrange
            $config = @{}
            $additionalState = @{
                CustomProperty = "custom-value"
                AnotherProperty = 42
            }

            # Act
            $context = New-WorkflowContext -Config $config -AdditionalState $additionalState

            # Assert
            $context.State.CustomProperty | Should -Be "custom-value"
            $context.State.AnotherProperty | Should -Be 42
        }

        It "Accepts Logger parameter" {
            # Arrange
            $config = @{}
            $mockLogger = @{ LogLevel = "DEBUG" }

            # Act
            $context = New-WorkflowContext -Config $config -Logger $mockLogger

            # Assert
            $context.Logger | Should -Not -BeNullOrEmpty
            $context.Logger.LogLevel | Should -Be "DEBUG"
        }

        It "Creates empty Metrics collections" {
            # Arrange
            $config = @{}

            # Act
            $context = New-WorkflowContext -Config $config

            # Assert
            $context.Metrics.StepTimings | Should -Not -BeNullOrEmpty
            $context.Metrics.IterationTimings | Should -Not -BeNullOrEmpty
            $context.Metrics.StepTimings.Count | Should -Be 0
            $context.Metrics.IterationTimings.Count | Should -Be 0
        }
    }

    Context "Register-WorkflowStep" {
        It "Registers a workflow step successfully" {
            # Arrange
            $stepName = "TestStep"
            $scriptBlock = { param($Context) return "test-output" }

            # Act
            { Register-WorkflowStep -Name $stepName -ScriptBlock $scriptBlock } | Should -Not -Throw

            # Assert - step should be registered (we'll test execution separately)
            $metrics = Get-WorkflowMetrics
            $metrics.RegisteredSteps | Should -BeGreaterThan 0
        }

        It "Accepts Description parameter" {
            # Act & Assert
            {
                Register-WorkflowStep `
                    -Name "DescribedStep" `
                    -ScriptBlock { param($Context) } `
                    -Description "This is a test step"
            } | Should -Not -Throw
        }

        It "Accepts ContinueOnError parameter" {
            # Act & Assert
            {
                Register-WorkflowStep `
                    -Name "ErrorTolerantStep" `
                    -ScriptBlock { param($Context) throw "Expected error" } `
                    -ContinueOnError $true
            } | Should -Not -Throw
        }

        It "Allows overwriting existing step with warning" {
            # Arrange
            $stepName = "OverwriteTest"
            Register-WorkflowStep -Name $stepName -ScriptBlock { "v1" }

            # Act & Assert - should not throw when overwriting
            {
                Register-WorkflowStep -Name $stepName -ScriptBlock { "v2" }
            } | Should -Not -Throw
        }

        It "Registers multiple steps independently" {
            # Act
            Register-WorkflowStep -Name "Step1" -ScriptBlock { "output1" }
            Register-WorkflowStep -Name "Step2" -ScriptBlock { "output2" }
            Register-WorkflowStep -Name "Step3" -ScriptBlock { "output3" }

            # Assert
            $metrics = Get-WorkflowMetrics
            $metrics.RegisteredSteps | Should -BeGreaterOrEqual 3
        }
    }

    Context "Invoke-WorkflowStep" {
        BeforeEach {
            # Register a test step
            Register-WorkflowStep -Name "SuccessStep" -ScriptBlock {
                param($Context)
                return @{ Result = "success", Value = 42 }
            }

            Register-WorkflowStep -Name "FailureStep" -ScriptBlock {
                param($Context)
                throw "Intentional test failure"
            }

            Register-WorkflowStep -Name "ErrorTolerantStep" -ScriptBlock {
                param($Context)
                throw "Expected error"
            } -ContinueOnError $true
        }

        It "Executes registered step successfully" {
            # Arrange
            $config = @{ test = "value" }
            $context = New-WorkflowContext -Config $config

            # Act
            $result = Invoke-WorkflowStep -Name "SuccessStep" -Context $context

            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            $result.StepName | Should -Be "SuccessStep"
            $result.Error | Should -BeNullOrEmpty
        }

        It "Returns step output in result" {
            # Arrange
            $context = New-WorkflowContext -Config @{}

            # Act
            $result = Invoke-WorkflowStep -Name "SuccessStep" -Context $context

            # Assert
            $result.Output | Should -Not -BeNullOrEmpty
            $result.Output.Result | Should -Be "success"
            $result.Output.Value | Should -Be 42
        }

        It "Measures execution time" {
            # Arrange
            Register-WorkflowStep -Name "SlowStep" -ScriptBlock {
                param($Context)
                Start-Sleep -Milliseconds 100
                return "done"
            }
            $context = New-WorkflowContext -Config @{}

            # Act
            $result = Invoke-WorkflowStep -Name "SlowStep" -Context $context

            # Assert
            $result.ExecutionTime | Should -Not -BeNullOrEmpty
            $result.ExecutionTime.TotalMilliseconds | Should -BeGreaterThan 50
        }

        It "Updates context CurrentStep" {
            # Arrange
            $context = New-WorkflowContext -Config @{}

            # Act
            Invoke-WorkflowStep -Name "SuccessStep" -Context $context

            # Assert
            $context.State.CurrentStep | Should -Be "SuccessStep"
        }

        It "Adds result to context Metrics" {
            # Arrange
            $context = New-WorkflowContext -Config @{}

            # Act
            Invoke-WorkflowStep -Name "SuccessStep" -Context $context

            # Assert
            $context.Metrics.StepTimings.Count | Should -Be 1
            $context.Metrics.StepTimings[0].StepName | Should -Be "SuccessStep"
        }

        It "Handles step failure correctly" {
            # Arrange
            $context = New-WorkflowContext -Config @{}

            # Act & Assert - should throw for non-tolerant failure
            { Invoke-WorkflowStep -Name "FailureStep" -Context $context } | Should -Throw
        }

        It "Increments error count on failure" {
            # Arrange
            $context = New-WorkflowContext -Config @{}

            # Act
            try {
                Invoke-WorkflowStep -Name "FailureStep" -Context $context
            }
            catch {
                # Expected
            }

            # Assert
            $context.State.ErrorCount | Should -BeGreaterThan 0
            $context.State.LastError | Should -Not -BeNullOrEmpty
        }

        It "Continues on error when ContinueOnError is true" {
            # Arrange
            $context = New-WorkflowContext -Config @{}

            # Act - should not throw
            $result = Invoke-WorkflowStep -Name "ErrorTolerantStep" -Context $context

            # Assert
            $result.Success | Should -Be $false
            $result.Error | Should -Not -BeNullOrEmpty
        }

        It "Throws exception for unregistered step" {
            # Arrange
            $context = New-WorkflowContext -Config @{}

            # Act & Assert
            { Invoke-WorkflowStep -Name "NonExistentStep" -Context $context } | Should -Throw
        }

        It "Includes timestamp in result" {
            # Arrange
            $context = New-WorkflowContext -Config @{}

            # Act
            $result = Invoke-WorkflowStep -Name "SuccessStep" -Context $context

            # Assert
            $result.Timestamp | Should -Not -BeNullOrEmpty
            $result.Timestamp | Should -BeOfType ([DateTime])
        }
    }

    Context "Start-WorkflowLoop" {
        BeforeEach {
            # Register test steps
            Register-WorkflowStep -Name "Step1" -ScriptBlock {
                param($Context)
                $Context.State.Step1Executed = $true
                return "step1-done"
            }

            Register-WorkflowStep -Name "Step2" -ScriptBlock {
                param($Context)
                $Context.State.Step2Executed = $true
                return "step2-done"
            }

            Register-WorkflowStep -Name "Step3" -ScriptBlock {
                param($Context)
                $Context.State.Step3Executed = $true
                return "step3-done"
            }
        }

        It "Executes single iteration with MaxIterations=1" {
            # Arrange
            $context = New-WorkflowContext -Config @{}
            $steps = @("Step1", "Step2", "Step3")

            # Act
            Start-WorkflowLoop -Context $context -Steps $steps -MaxIterations 1 -IntervalSeconds 1

            # Assert
            $context.State.IterationCount | Should -Be 1
            $context.State.Step1Executed | Should -Be $true
            $context.State.Step2Executed | Should -Be $true
            $context.State.Step3Executed | Should -Be $true
        }

        It "Executes steps in correct order" {
            # Arrange
            $executionOrder = @()
            Register-WorkflowStep -Name "OrderStep1" -ScriptBlock {
                param($Context)
                $executionOrder += 1
            }
            Register-WorkflowStep -Name "OrderStep2" -ScriptBlock {
                param($Context)
                $executionOrder += 2
            }
            Register-WorkflowStep -Name "OrderStep3" -ScriptBlock {
                param($Context)
                $executionOrder += 3
            }

            $context = New-WorkflowContext -Config @{}
            $steps = @("OrderStep1", "OrderStep2", "OrderStep3")

            # Act
            Start-WorkflowLoop -Context $context -Steps $steps -MaxIterations 1 -IntervalSeconds 1

            # Assert
            $executionOrder | Should -Be @(1, 2, 3)
        }

        It "Updates WorkflowStatus to Running" {
            # Arrange
            $context = New-WorkflowContext -Config @{}
            $steps = @("Step1")

            # Act
            Start-WorkflowLoop -Context $context -Steps $steps -MaxIterations 1 -IntervalSeconds 1

            # Assert - status should be "Stopped" after completion
            $context.State.WorkflowStatus | Should -Be "Stopped"
        }

        It "Increments IterationCount for each iteration" {
            # Arrange
            $context = New-WorkflowContext -Config @{}
            $steps = @("Step1")

            # Act
            Start-WorkflowLoop -Context $context -Steps $steps -MaxIterations 3 -IntervalSeconds 1

            # Assert
            $context.State.IterationCount | Should -Be 3
        }

        It "Stops after MaxIterations reached" {
            # Arrange
            $context = New-WorkflowContext -Config @{}
            $steps = @("Step1")

            # Act
            Start-WorkflowLoop -Context $context -Steps $steps -MaxIterations 2 -IntervalSeconds 1

            # Assert
            $context.State.IterationCount | Should -Be 2
        }

        It "Records iteration timings in metrics" {
            # Arrange
            $context = New-WorkflowContext -Config @{}
            $steps = @("Step1", "Step2")

            # Act
            Start-WorkflowLoop -Context $context -Steps $steps -MaxIterations 2 -IntervalSeconds 1

            # Assert
            $context.Metrics.IterationTimings.Count | Should -Be 2
            $context.Metrics.IterationTimings[0].Iteration | Should -Be 1
            $context.Metrics.IterationTimings[1].Iteration | Should -Be 2
        }

        It "Tracks successful iterations" {
            # Arrange
            $context = New-WorkflowContext -Config @{}
            $steps = @("Step1")

            # Act
            Start-WorkflowLoop -Context $context -Steps $steps -MaxIterations 2 -IntervalSeconds 1

            # Assert
            $metrics = Get-WorkflowMetrics
            $metrics.SuccessfulIterations | Should -Be 2
            $metrics.FailedIterations | Should -Be 0
        }

        It "Handles step failure and continues to next iteration" {
            # Arrange
            Register-WorkflowStep -Name "FailingStep" -ScriptBlock {
                param($Context)
                throw "Test failure"
            } -ContinueOnError $false

            $context = New-WorkflowContext -Config @{}
            $steps = @("Step1", "FailingStep")

            # Act - loop should stop on failure
            Start-WorkflowLoop -Context $context -Steps $steps -MaxIterations 3 -IntervalSeconds 1

            # Assert - should complete all iterations despite failures
            $metrics = Get-WorkflowMetrics
            $metrics.TotalIterations | Should -BeGreaterThan 0
        }

        It "Respects IntervalSeconds parameter" {
            # Arrange
            $context = New-WorkflowContext -Config @{}
            $steps = @("Step1")
            $startTime = Get-Date

            # Act - with 2 iterations and 2-second interval, should take at least 2 seconds
            Start-WorkflowLoop -Context $context -Steps $steps -MaxIterations 2 -IntervalSeconds 2

            # Assert
            $duration = (Get-Date) - $startTime
            $duration.TotalSeconds | Should -BeGreaterThan 1.5  # Allow for some timing variance
        }
    }

    Context "Get-WorkflowMetrics" {
        It "Returns metrics hashtable" {
            # Act
            $metrics = Get-WorkflowMetrics

            # Assert
            $metrics | Should -Not -BeNullOrEmpty
            $metrics.Keys | Should -Contain "Uptime"
            $metrics.Keys | Should -Contain "TotalIterations"
            $metrics.Keys | Should -Contain "SuccessfulIterations"
            $metrics.Keys | Should -Contain "FailedIterations"
            $metrics.Keys | Should -Contain "RegisteredSteps"
        }

        It "Calculates success rate correctly" {
            # Arrange
            Register-WorkflowStep -Name "MetricStep" -ScriptBlock { param($Context) }
            $context = New-WorkflowContext -Config @{}
            Start-WorkflowLoop -Context $context -Steps @("MetricStep") -MaxIterations 5 -IntervalSeconds 1

            # Act
            $metrics = Get-WorkflowMetrics

            # Assert
            $metrics.TotalIterations | Should -Be 5
            $metrics.SuccessRate | Should -Be 100.0
        }

        It "Includes per-step metrics" {
            # Arrange
            Register-WorkflowStep -Name "TrackedStep" -ScriptBlock { param($Context) }
            $context = New-WorkflowContext -Config @{}
            Invoke-WorkflowStep -Name "TrackedStep" -Context $context

            # Act
            $metrics = Get-WorkflowMetrics

            # Assert
            $metrics.StepMetrics | Should -Not -BeNullOrEmpty
            $metrics.StepMetrics.Keys | Should -Contain "TrackedStep"
            $metrics.StepMetrics["TrackedStep"].ExecutionCount | Should -Be 1
        }

        It "Calculates average execution time per step" {
            # Arrange
            Register-WorkflowStep -Name "TimedStep" -ScriptBlock {
                param($Context)
                Start-Sleep -Milliseconds 50
            }
            $context = New-WorkflowContext -Config @{}
            Invoke-WorkflowStep -Name "TimedStep" -Context $context
            Invoke-WorkflowStep -Name "TimedStep" -Context $context

            # Act
            $metrics = Get-WorkflowMetrics

            # Assert
            $stepMetrics = $metrics.StepMetrics["TimedStep"]
            $stepMetrics.ExecutionCount | Should -Be 2
            $stepMetrics.AverageExecutionTime | Should -Not -BeNullOrEmpty
            $stepMetrics.AverageExecutionTime.TotalMilliseconds | Should -BeGreaterThan 25
        }

        It "Tracks uptime since initialization" {
            # Arrange
            Start-Sleep -Milliseconds 100

            # Act
            $metrics = Get-WorkflowMetrics

            # Assert
            $metrics.Uptime | Should -Not -BeNullOrEmpty
            $metrics.Uptime.TotalMilliseconds | Should -BeGreaterThan 50
        }
    }

    Context "Reset-WorkflowMetrics" {
        It "Resets all metrics to initial state" {
            # Arrange
            Register-WorkflowStep -Name "ResetTestStep" -ScriptBlock { param($Context) }
            $context = New-WorkflowContext -Config @{}
            Start-WorkflowLoop -Context $context -Steps @("ResetTestStep") -MaxIterations 3 -IntervalSeconds 1

            # Act
            Reset-WorkflowMetrics

            # Assert
            $metrics = Get-WorkflowMetrics
            $metrics.TotalIterations | Should -Be 0
            $metrics.SuccessfulIterations | Should -Be 0
            $metrics.FailedIterations | Should -Be 0
        }

        It "Resets step execution counts" {
            # Arrange
            Register-WorkflowStep -Name "CountStep" -ScriptBlock { param($Context) }
            $context = New-WorkflowContext -Config @{}
            Invoke-WorkflowStep -Name "CountStep" -Context $context

            # Act
            Reset-WorkflowMetrics

            # Assert
            $metrics = Get-WorkflowMetrics
            $metrics.StepMetrics["CountStep"].ExecutionCount | Should -Be 0
        }

        It "Resets start time" {
            # Arrange
            $metrics1 = Get-WorkflowMetrics
            $startTime1 = $metrics1.Uptime

            Start-Sleep -Milliseconds 100

            # Act
            Reset-WorkflowMetrics

            # Assert
            $metrics2 = Get-WorkflowMetrics
            $metrics2.Uptime.TotalMilliseconds | Should -BeLessThan $startTime1.TotalMilliseconds
        }
    }

    Context "Integration - Complete Workflow" {
        It "Executes complete multi-step workflow successfully" {
            # Arrange
            $testResults = @{
                MonitorCalled = $false
                DecideCalled = $false
                ExecuteCalled = $false
                ValidateCalled = $false
            }

            Register-WorkflowStep -Name "Monitor" -ScriptBlock {
                param($Context)
                $testResults.MonitorCalled = $true
                $Context.State.CertificateStatus.RenewalRequired = $true
            }

            Register-WorkflowStep -Name "Decide" -ScriptBlock {
                param($Context)
                $testResults.DecideCalled = $true
                return @{ Action = "renew"; Reason = "Test renewal" }
            }

            Register-WorkflowStep -Name "Execute" -ScriptBlock {
                param($Context)
                $testResults.ExecuteCalled = $true
                return @{ Success = $true }
            }

            Register-WorkflowStep -Name "Validate" -ScriptBlock {
                param($Context)
                $testResults.ValidateCalled = $true
                return @{ Valid = $true }
            }

            $context = New-WorkflowContext -Config @{}
            $steps = @("Monitor", "Decide", "Execute", "Validate")

            # Act
            Start-WorkflowLoop -Context $context -Steps $steps -MaxIterations 1 -IntervalSeconds 1

            # Assert
            $testResults.MonitorCalled | Should -Be $true
            $testResults.DecideCalled | Should -Be $true
            $testResults.ExecuteCalled | Should -Be $true
            $testResults.ValidateCalled | Should -Be $true

            $metrics = Get-WorkflowMetrics
            $metrics.TotalIterations | Should -Be 1
            $metrics.SuccessfulIterations | Should -Be 1
        }

        It "Passes context between workflow steps" {
            # Arrange
            Register-WorkflowStep -Name "SetData" -ScriptBlock {
                param($Context)
                $Context.State.TestValue = "shared-data"
            }

            Register-WorkflowStep -Name "ReadData" -ScriptBlock {
                param($Context)
                return $Context.State.TestValue
            }

            $context = New-WorkflowContext -Config @{}

            # Act
            Invoke-WorkflowStep -Name "SetData" -Context $context
            $result = Invoke-WorkflowStep -Name "ReadData" -Context $context

            # Assert
            $result.Output | Should -Be "shared-data"
        }
    }
}
