# ==============================================================================
# ServiceReloadController.Tests.ps1 - Unit Tests for NGINX Reload Controller
# ==============================================================================
# Tests for zero-downtime NGINX configuration reload functionality
# ==============================================================================

#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    # Import Logger module (dependency)
    $loggerPath = Resolve-Path "$PSScriptRoot/../../agents/common/Logger.psm1"
    Import-Module $loggerPath -Force

    # Import module under test
    $modulePath = Resolve-Path "$PSScriptRoot/../../agents/acme/ServiceReloadController.psm1"
    Import-Module $modulePath -Force

    # Create test directory
    $script:TestDir = Join-Path $TestDrive "reload-tests"
    New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null

    # Mock Write-LogInfo, Write-LogError, Write-LogDebug to prevent actual logging
    Mock -ModuleName ServiceReloadController Write-LogInfo { }
    Mock -ModuleName ServiceReloadController Write-LogError { }
    Mock -ModuleName ServiceReloadController Write-LogDebug { }
}

AfterAll {
    # Cleanup
    Remove-Module ServiceReloadController -Force -ErrorAction SilentlyContinue
    Remove-Module Logger -Force -ErrorAction SilentlyContinue
}

Describe "ServiceReloadController Module" -Tags @('Unit', 'ACME', 'ServiceReload') {

    Context "Invoke-NginxReload - Parameter Validation" {
        It "Accepts ContainerName parameter" {
            # Arrange
            Mock -ModuleName ServiceReloadController Start-Process {
                param($FilePath, $ArgumentList, $NoNewWindow, $PassThru, $RedirectStandardError)
                $process = New-Object PSObject -Property @{
                    ExitCode = 0
                    HasExited = $true
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name WaitForExit -Value {
                    param($Timeout)
                    return $true
                }
                return $process
            }

            # Act & Assert
            { Invoke-NginxReload -ContainerName "custom-nginx" } | Should -Not -Throw
        }

        It "Uses default container name when not specified" {
            # Arrange
            $capturedArgs = $null
            Mock -ModuleName ServiceReloadController Start-Process {
                param($FilePath, $ArgumentList, $NoNewWindow, $PassThru, $RedirectStandardError)
                $script:capturedArgs = $ArgumentList
                $process = New-Object PSObject -Property @{
                    ExitCode = 0
                    HasExited = $true
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name WaitForExit -Value {
                    param($Timeout)
                    return $true
                }
                return $process
            }

            # Act
            Invoke-NginxReload

            # Assert
            $capturedArgs | Should -Contain "eca-target-server"
        }

        It "Accepts TimeoutSeconds parameter" {
            # Arrange
            Mock -ModuleName ServiceReloadController Start-Process {
                $process = New-Object PSObject -Property @{
                    ExitCode = 0
                    HasExited = $true
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name WaitForExit -Value {
                    param($Timeout)
                    return $true
                }
                return $process
            }

            # Act & Assert
            { Invoke-NginxReload -TimeoutSeconds 30 } | Should -Not -Throw
        }

        It "Validates TimeoutSeconds range (1-300)" {
            # Act & Assert
            { Invoke-NginxReload -TimeoutSeconds 0 } | Should -Throw
            { Invoke-NginxReload -TimeoutSeconds 301 } | Should -Throw
            { Invoke-NginxReload -TimeoutSeconds 150 } | Should -Not -Throw
        }

        It "Rejects null or empty ContainerName" {
            # Act & Assert
            { Invoke-NginxReload -ContainerName "" } | Should -Throw
            { Invoke-NginxReload -ContainerName $null } | Should -Throw
        }
    }

    Context "Invoke-NginxReload - Successful Reload" {
        BeforeEach {
            # Create temporary stderr file
            $script:TempStderrFile = Join-Path $script:TestDir "stderr_$([guid]::NewGuid().ToString()).tmp"
            "" | Out-File $script:TempStderrFile
        }

        AfterEach {
            if (Test-Path $script:TempStderrFile) {
                Remove-Item $script:TempStderrFile -Force -ErrorAction SilentlyContinue
            }
        }

        It "Returns true on successful reload (exit code 0)" {
            # Arrange
            Mock -ModuleName ServiceReloadController Start-Process {
                param($FilePath, $ArgumentList, $NoNewWindow, $PassThru, $RedirectStandardError)
                "" | Out-File $RedirectStandardError
                $process = New-Object PSObject -Property @{
                    ExitCode = 0
                    HasExited = $true
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name WaitForExit -Value {
                    param($Timeout)
                    return $true
                }
                return $process
            }

            # Act
            $result = Invoke-NginxReload

            # Assert
            $result | Should -Be $true
        }

        It "Executes docker exec with correct arguments" {
            # Arrange
            $capturedArgs = $null
            Mock -ModuleName ServiceReloadController Start-Process {
                param($FilePath, $ArgumentList, $NoNewWindow, $PassThru, $RedirectStandardError)
                $script:capturedArgs = $ArgumentList
                "" | Out-File $RedirectStandardError
                $process = New-Object PSObject -Property @{
                    ExitCode = 0
                    HasExited = $true
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name WaitForExit -Value {
                    param($Timeout)
                    return $true
                }
                return $process
            }

            # Act
            Invoke-NginxReload -ContainerName "test-nginx"

            # Assert
            $capturedArgs | Should -Contain "exec"
            $capturedArgs | Should -Contain "test-nginx"
            $capturedArgs | Should -Contain "nginx"
            $capturedArgs | Should -Contain "-s"
            $capturedArgs | Should -Contain "reload"
        }

        It "Calls Write-LogInfo on success" {
            # Arrange
            Mock -ModuleName ServiceReloadController Start-Process {
                param($FilePath, $ArgumentList, $NoNewWindow, $PassThru, $RedirectStandardError)
                "" | Out-File $RedirectStandardError
                $process = New-Object PSObject -Property @{
                    ExitCode = 0
                    HasExited = $true
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name WaitForExit -Value {
                    param($Timeout)
                    return $true
                }
                return $process
            }

            Mock -ModuleName ServiceReloadController Write-LogInfo { } -Verifiable

            # Act
            Invoke-NginxReload

            # Assert
            Should -Invoke -ModuleName ServiceReloadController Write-LogInfo -Times 1
        }

        It "Cleans up temporary stderr file" {
            # Arrange
            $stderrFiles = @()
            Mock -ModuleName ServiceReloadController Start-Process {
                param($FilePath, $ArgumentList, $NoNewWindow, $PassThru, $RedirectStandardError)
                $stderrFiles += $RedirectStandardError
                "" | Out-File $RedirectStandardError
                $process = New-Object PSObject -Property @{
                    ExitCode = 0
                    HasExited = $true
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name WaitForExit -Value {
                    param($Timeout)
                    return $true
                }
                return $process
            }

            # Act
            Invoke-NginxReload

            # Assert - file should not exist after function completes
            Start-Sleep -Milliseconds 100  # Brief delay to ensure cleanup
            foreach ($file in $stderrFiles) {
                Test-Path $file | Should -Be $false
            }
        }
    }

    Context "Invoke-NginxReload - Failure Scenarios" {
        It "Returns false on non-zero exit code" {
            # Arrange
            Mock -ModuleName ServiceReloadController Start-Process {
                param($FilePath, $ArgumentList, $NoNewWindow, $PassThru, $RedirectStandardError)
                "nginx: configuration file /etc/nginx/nginx.conf test failed" | Out-File $RedirectStandardError
                $process = New-Object PSObject -Property @{
                    ExitCode = 1
                    HasExited = $true
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name WaitForExit -Value {
                    param($Timeout)
                    return $true
                }
                return $process
            }

            # Act
            $result = Invoke-NginxReload

            # Assert
            $result | Should -Be $false
        }

        It "Calls Write-LogError on failure" {
            # Arrange
            Mock -ModuleName ServiceReloadController Start-Process {
                param($FilePath, $ArgumentList, $NoNewWindow, $PassThru, $RedirectStandardError)
                "Error: container not found" | Out-File $RedirectStandardError
                $process = New-Object PSObject -Property @{
                    ExitCode = 1
                    HasExited = $true
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name WaitForExit -Value {
                    param($Timeout)
                    return $true
                }
                return $process
            }

            Mock -ModuleName ServiceReloadController Write-LogError { } -Verifiable

            # Act
            Invoke-NginxReload

            # Assert
            Should -Invoke -ModuleName ServiceReloadController Write-LogError -Times 1
        }

        It "Detects 'container not found' error type" {
            # Arrange
            $errorContext = $null
            Mock -ModuleName ServiceReloadController Start-Process {
                param($FilePath, $ArgumentList, $NoNewWindow, $PassThru, $RedirectStandardError)
                "Error: No such container: missing-nginx" | Out-File $RedirectStandardError
                $process = New-Object PSObject -Property @{
                    ExitCode = 1
                    HasExited = $true
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name WaitForExit -Value {
                    param($Timeout)
                    return $true
                }
                return $process
            }

            Mock -ModuleName ServiceReloadController Write-LogError {
                param($Message, $Context)
                $script:errorContext = $Context
            }

            # Act
            Invoke-NginxReload

            # Assert
            $errorContext.error_type | Should -Be "container_not_found"
        }

        It "Detects NGINX validation failure error type" {
            # Arrange
            $errorContext = $null
            Mock -ModuleName ServiceReloadController Start-Process {
                param($FilePath, $ArgumentList, $NoNewWindow, $PassThru, $RedirectStandardError)
                "nginx: [emerg] invalid parameter" | Out-File $RedirectStandardError
                $process = New-Object PSObject -Property @{
                    ExitCode = 1
                    HasExited = $true
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name WaitForExit -Value {
                    param($Timeout)
                    return $true
                }
                return $process
            }

            Mock -ModuleName ServiceReloadController Write-LogError {
                param($Message, $Context)
                $script:errorContext = $Context
            }

            # Act
            Invoke-NginxReload

            # Assert
            $errorContext.error_type | Should -Be "nginx_validation_failed"
        }

        It "Detects Docker exec failure error type" {
            # Arrange
            $errorContext = $null
            Mock -ModuleName ServiceReloadController Start-Process {
                param($FilePath, $ArgumentList, $NoNewWindow, $PassThru, $RedirectStandardError)
                "docker: command failed" | Out-File $RedirectStandardError
                $process = New-Object PSObject -Property @{
                    ExitCode = 1
                    HasExited = $true
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name WaitForExit -Value {
                    param($Timeout)
                    return $true
                }
                return $process
            }

            Mock -ModuleName ServiceReloadController Write-LogError {
                param($Message, $Context)
                $script:errorContext = $Context
            }

            # Act
            Invoke-NginxReload

            # Assert
            $errorContext.error_type | Should -Be "docker_exec_failed"
        }
    }

    Context "Invoke-NginxReload - Timeout Handling" {
        It "Returns false when timeout is exceeded" {
            # Arrange
            Mock -ModuleName ServiceReloadController Start-Process {
                param($FilePath, $ArgumentList, $NoNewWindow, $PassThru, $RedirectStandardError)
                "" | Out-File $RedirectStandardError
                $process = New-Object PSObject -Property @{
                    ExitCode = -1
                    HasExited = $false
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name WaitForExit -Value {
                    param($Timeout)
                    return $false  # Simulate timeout
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name Kill -Value { }
                return $process
            }

            # Act
            $result = Invoke-NginxReload -TimeoutSeconds 1

            # Assert
            $result | Should -Be $false
        }

        It "Attempts to kill process on timeout" {
            # Arrange
            $killCalled = $false
            Mock -ModuleName ServiceReloadController Start-Process {
                param($FilePath, $ArgumentList, $NoNewWindow, $PassThru, $RedirectStandardError)
                "" | Out-File $RedirectStandardError
                $process = New-Object PSObject -Property @{
                    ExitCode = -1
                    HasExited = $false
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name WaitForExit -Value {
                    param($Timeout)
                    return $false
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name Kill -Value {
                    $script:killCalled = $true
                }
                return $process
            }

            # Act
            Invoke-NginxReload -TimeoutSeconds 1

            # Assert
            $killCalled | Should -Be $true
        }

        It "Logs timeout error with correct context" {
            # Arrange
            $loggedContext = $null
            Mock -ModuleName ServiceReloadController Start-Process {
                param($FilePath, $ArgumentList, $NoNewWindow, $PassThru, $RedirectStandardError)
                "" | Out-File $RedirectStandardError
                $process = New-Object PSObject -Property @{
                    ExitCode = -1
                    HasExited = $false
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name WaitForExit -Value {
                    param($Timeout)
                    return $false
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name Kill -Value { }
                return $process
            }

            Mock -ModuleName ServiceReloadController Write-LogError {
                param($Message, $Context)
                if ($Message -match "timeout") {
                    $script:loggedContext = $Context
                }
            }

            # Act
            Invoke-NginxReload -TimeoutSeconds 5

            # Assert
            $loggedContext | Should -Not -BeNullOrEmpty
            $loggedContext.timeout_seconds | Should -Be 5
        }

        It "Handles kill failure gracefully" {
            # Arrange
            Mock -ModuleName ServiceReloadController Start-Process {
                param($FilePath, $ArgumentList, $NoNewWindow, $PassThru, $RedirectStandardError)
                "" | Out-File $RedirectStandardError
                $process = New-Object PSObject -Property @{
                    ExitCode = -1
                    HasExited = $false
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name WaitForExit -Value {
                    param($Timeout)
                    return $false
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name Kill -Value {
                    throw "Process already exited"
                }
                return $process
            }

            # Act & Assert - should not throw even if kill fails
            { Invoke-NginxReload -TimeoutSeconds 1 } | Should -Not -Throw
        }
    }

    Context "Invoke-NginxReload - Exception Handling" {
        It "Returns false on Start-Process exception" {
            # Arrange
            Mock -ModuleName ServiceReloadController Start-Process {
                throw "docker command not found"
            }

            # Act
            $result = Invoke-NginxReload

            # Assert
            $result | Should -Be $false
        }

        It "Logs exception error with context" {
            # Arrange
            $loggedContext = $null
            Mock -ModuleName ServiceReloadController Start-Process {
                throw "Permission denied: /var/run/docker.sock"
            }

            Mock -ModuleName ServiceReloadController Write-LogError {
                param($Message, $Context)
                $script:loggedContext = $Context
            }

            # Act
            Invoke-NginxReload

            # Assert
            $loggedContext | Should -Not -BeNullOrEmpty
            $loggedContext.error_type | Should -Be "exception"
            $loggedContext.error | Should -Match "Permission denied"
        }

        It "Cleans up stderr file even on exception" {
            # Arrange
            $stderrFiles = @()
            Mock -ModuleName ServiceReloadController Start-Process {
                param($FilePath, $ArgumentList, $NoNewWindow, $PassThru, $RedirectStandardError)
                $stderrFiles += $RedirectStandardError
                "" | Out-File $RedirectStandardError
                throw "Simulated exception"
            }

            # Act
            Invoke-NginxReload

            # Assert
            Start-Sleep -Milliseconds 100
            foreach ($file in $stderrFiles) {
                if ($file -and (Test-Path $file)) {
                    # Cleanup should have happened even with exception
                    Test-Path $file | Should -Be $false
                }
            }
        }
    }

    Context "Invoke-NginxReload - Output Type" {
        It "Returns boolean type" {
            # Arrange
            Mock -ModuleName ServiceReloadController Start-Process {
                param($FilePath, $ArgumentList, $NoNewWindow, $PassThru, $RedirectStandardError)
                "" | Out-File $RedirectStandardError
                $process = New-Object PSObject -Property @{
                    ExitCode = 0
                    HasExited = $true
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name WaitForExit -Value {
                    param($Timeout)
                    return $true
                }
                return $process
            }

            # Act
            $result = Invoke-NginxReload

            # Assert
            $result | Should -BeOfType ([bool])
        }

        It "Returns only true or false (no other values)" {
            # Arrange
            Mock -ModuleName ServiceReloadController Start-Process {
                param($FilePath, $ArgumentList, $NoNewWindow, $PassThru, $RedirectStandardError)
                "" | Out-File $RedirectStandardError
                $process = New-Object PSObject -Property @{
                    ExitCode = 0
                    HasExited = $true
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name WaitForExit -Value {
                    param($Timeout)
                    return $true
                }
                return $process
            }

            # Act
            $result = Invoke-NginxReload

            # Assert
            ($result -eq $true -or $result -eq $false) | Should -Be $true
        }
    }

    Context "Invoke-NginxReload - Logging Integration" {
        It "Calls Write-LogDebug before starting process" {
            # Arrange
            Mock -ModuleName ServiceReloadController Start-Process {
                param($FilePath, $ArgumentList, $NoNewWindow, $PassThru, $RedirectStandardError)
                "" | Out-File $RedirectStandardError
                $process = New-Object PSObject -Property @{
                    ExitCode = 0
                    HasExited = $true
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name WaitForExit -Value {
                    param($Timeout)
                    return $true
                }
                return $process
            }

            Mock -ModuleName ServiceReloadController Write-LogDebug { } -Verifiable

            # Act
            Invoke-NginxReload

            # Assert
            Should -Invoke -ModuleName ServiceReloadController Write-LogDebug -Times 1
        }

        It "Includes container name in log context" {
            # Arrange
            $logContext = $null
            Mock -ModuleName ServiceReloadController Start-Process {
                param($FilePath, $ArgumentList, $NoNewWindow, $PassThru, $RedirectStandardError)
                "" | Out-File $RedirectStandardError
                $process = New-Object PSObject -Property @{
                    ExitCode = 0
                    HasExited = $true
                }
                Add-Member -InputObject $process -MemberType ScriptMethod -Name WaitForExit -Value {
                    param($Timeout)
                    return $true
                }
                return $process
            }

            Mock -ModuleName ServiceReloadController Write-LogInfo {
                param($Message, $Context)
                $script:logContext = $Context
            }

            # Act
            Invoke-NginxReload -ContainerName "custom-container"

            # Assert
            $logContext.container | Should -Be "custom-container"
        }
    }
}
