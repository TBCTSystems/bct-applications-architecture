# ==============================================================================
# EstWorkflow.Tests.ps1 - Unit Tests for EST Workflow Module
# ==============================================================================
# Tests for EST certificate lifecycle workflow (Monitor, Decide, Execute, Validate)
# ==============================================================================

#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    # Import Logger module (dependency)
    $loggerPath = Resolve-Path "$PSScriptRoot/../../agents/common/Logger.psm1"
    Import-Module $loggerPath -Force

    # Import WorkflowOrchestrator (dependency)
    $orchestratorPath = Resolve-Path "$PSScriptRoot/../../agents/common/WorkflowOrchestrator.psm1"
    Import-Module $orchestratorPath -Force

    # Import CertificateMonitor (dependency)
    $certMonitorPath = Resolve-Path "$PSScriptRoot/../../agents/common/CertificateMonitor.psm1"
    Import-Module $certMonitorPath -Force

    # Import CrlValidator (dependency)
    $crlValidatorPath = Resolve-Path "$PSScriptRoot/../../agents/common/CrlValidator.psm1"
    Import-Module $crlValidatorPath -Force

    # Import FileOperations (dependency)
    $fileOpsPath = Resolve-Path "$PSScriptRoot/../../agents/common/FileOperations.psm1"
    Import-Module $fileOpsPath -Force

    # Import EstClient (dependency)
    $estClientPath = Resolve-Path "$PSScriptRoot/../../agents/est/EstClient.psm1"
    Import-Module $estClientPath -Force

    # Import BootstrapTokenManager (dependency)
    $tokenManagerPath = Resolve-Path "$PSScriptRoot/../../agents/est/BootstrapTokenManager.psm1"
    Import-Module $tokenManagerPath -Force

    # Import module under test
    $modulePath = Resolve-Path "$PSScriptRoot/../../agents/est/EstWorkflow.psm1"
    Import-Module $modulePath -Force

    # Create test directory
    $script:TestDir = Join-Path $TestDrive "est-workflow-tests"
    New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null

    # Mock Write-Log functions
    Mock -ModuleName EstWorkflow Write-LogInfo { }
    Mock -ModuleName EstWorkflow Write-LogError { }
    Mock -ModuleName EstWorkflow Write-LogDebug { }
    Mock -ModuleName EstWorkflow Write-LogWarning { }
}

AfterAll {
    # Cleanup
    Remove-Module EstWorkflow -Force -ErrorAction SilentlyContinue
    Remove-Module BootstrapTokenManager -Force -ErrorAction SilentlyContinue
    Remove-Module EstClient -Force -ErrorAction SilentlyContinue
    Remove-Module FileOperations -Force -ErrorAction SilentlyContinue
    Remove-Module CrlValidator -Force -ErrorAction SilentlyContinue
    Remove-Module CertificateMonitor -Force -ErrorAction SilentlyContinue
    Remove-Module WorkflowOrchestrator -Force -ErrorAction SilentlyContinue
    Remove-Module Logger -Force -ErrorAction SilentlyContinue
}

Describe "EstWorkflow Module" -Tags @('Unit', 'EST', 'Workflow') {

    Context "Step-MonitorCertificate - Certificate Does Not Exist" {
        It "Sets CertificateStatus.Exists to false when cert doesn't exist" {
            # Arrange
            $config = @{
                cert_path = "/nonexistent/cert.pem"
                crl = @{
                    enabled = $false
                }
            }
            $context = New-WorkflowContext -Config $config

            # Act
            $result = Step-MonitorCertificate -Context $context

            # Assert
            $context.State.CertificateStatus.Exists | Should -Be $false
            $result.CertificateExists | Should -Be $false
        }

        It "Sets RenewalRequired to true when cert doesn't exist" {
            # Arrange
            $config = @{
                cert_path = "/nonexistent/cert.pem"
                crl = @{ enabled = $false }
            }
            $context = New-WorkflowContext -Config $config

            # Act
            $result = Step-MonitorCertificate -Context $context

            # Assert
            $context.State.CertificateStatus.RenewalRequired | Should -Be $true
            $result.RenewalRequired | Should -Be $true
        }
    }

    Context "Step-MonitorCertificate - Certificate Exists" {
        BeforeEach {
            # Create a test certificate file
            $script:TestCertPath = Join-Path $script:TestDir "test-cert.pem"
            @"
-----BEGIN CERTIFICATE-----
MIICljCCAX4CCQDnYw3fKHVQqDANBgkqhkiG9w0BAQsFADANMQswCQYDVQQGEwJV
-----END CERTIFICATE-----
"@ | Out-File $script:TestCertPath

            # Mock Get-CertificateInfo
            Mock -ModuleName EstWorkflow Get-CertificateInfo {
                return @{
                    ExpiryDate = (Get-Date).AddDays(30)
                    LifetimePercentage = 75
                    Subject = "CN=test-device"
                }
            }
        }

        It "Sets CertificateStatus.Exists to true when cert exists" {
            # Arrange
            $config = @{
                cert_path = $script:TestCertPath
                renewal_threshold_pct = 80
                crl = @{ enabled = $false }
            }
            $context = New-WorkflowContext -Config $config

            # Act
            $result = Step-MonitorCertificate -Context $context

            # Assert
            $context.State.CertificateStatus.Exists | Should -Be $true
            $result.CertificateExists | Should -Be $true
        }

        It "Calls Get-CertificateInfo with correct path" {
            # Arrange
            $config = @{
                cert_path = $script:TestCertPath
                renewal_threshold_pct = 80
                crl = @{ enabled = $false }
            }
            $context = New-WorkflowContext -Config $config

            # Act
            Step-MonitorCertificate -Context $context

            # Assert
            Should -Invoke -ModuleName EstWorkflow Get-CertificateInfo -Times 1 -ParameterFilter {
                $Path -eq $script:TestCertPath
            }
        }

        It "Sets ExpiryDate and LifetimePercentage from CertificateInfo" {
            # Arrange
            $expectedExpiry = (Get-Date).AddDays(45)
            Mock -ModuleName EstWorkflow Get-CertificateInfo {
                return @{
                    ExpiryDate = $expectedExpiry
                    LifetimePercentage = 60
                    Subject = "CN=test-device"
                }
            }

            $config = @{
                cert_path = $script:TestCertPath
                renewal_threshold_pct = 80
                crl = @{ enabled = $false }
            }
            $context = New-WorkflowContext -Config $config

            # Act
            Step-MonitorCertificate -Context $context

            # Assert
            $context.State.CertificateStatus.ExpiryDate | Should -Be $expectedExpiry
            $context.State.CertificateStatus.LifetimePercentage | Should -Be 60
        }

        It "Sets RenewalRequired to false when under threshold" {
            # Arrange
            Mock -ModuleName EstWorkflow Get-CertificateInfo {
                return @{
                    ExpiryDate = (Get-Date).AddDays(60)
                    LifetimePercentage = 50
                    Subject = "CN=test-device"
                }
            }

            $config = @{
                cert_path = $script:TestCertPath
                renewal_threshold_pct = 80
                crl = @{ enabled = $false }
            }
            $context = New-WorkflowContext -Config $config

            # Act
            $result = Step-MonitorCertificate -Context $context

            # Assert
            $context.State.CertificateStatus.RenewalRequired | Should -Be $false
            $result.RenewalRequired | Should -Be $false
        }

        It "Sets RenewalRequired to true when over threshold" {
            # Arrange
            Mock -ModuleName EstWorkflow Get-CertificateInfo {
                return @{
                    ExpiryDate = (Get-Date).AddDays(10)
                    LifetimePercentage = 85
                    Subject = "CN=test-device"
                }
            }

            $config = @{
                cert_path = $script:TestCertPath
                renewal_threshold_pct = 80
                crl = @{ enabled = $false }
            }
            $context = New-WorkflowContext -Config $config

            # Act
            $result = Step-MonitorCertificate -Context $context

            # Assert
            $context.State.CertificateStatus.RenewalRequired | Should -Be $true
            $result.RenewalRequired | Should -Be $true
        }
    }

    Context "Step-MonitorCertificate - CRL Validation" {
        BeforeEach {
            $script:TestCertPath = Join-Path $script:TestDir "crl-test-cert.pem"
            "MOCK CERT" | Out-File $script:TestCertPath

            Mock -ModuleName EstWorkflow Get-CertificateInfo {
                return @{
                    ExpiryDate = (Get-Date).AddDays(30)
                    LifetimePercentage = 50
                    Subject = "CN=test-device"
                }
            }

            Mock -ModuleName EstWorkflow Update-CrlCache {
                return @{ Updated = $true }
            }

            Mock -ModuleName EstWorkflow Test-CertificateRevoked {
                return $false
            }
        }

        It "Skips CRL check when disabled" {
            # Arrange
            $config = @{
                cert_path = $script:TestCertPath
                renewal_threshold_pct = 80
                crl = @{ enabled = $false }
            }
            $context = New-WorkflowContext -Config $config

            # Act
            Step-MonitorCertificate -Context $context

            # Assert
            Should -Invoke -ModuleName EstWorkflow Update-CrlCache -Times 0
            Should -Invoke -ModuleName EstWorkflow Test-CertificateRevoked -Times 0
        }

        It "Calls Update-CrlCache when CRL enabled" {
            # Arrange
            $config = @{
                cert_path = $script:TestCertPath
                renewal_threshold_pct = 80
                crl = @{
                    enabled = $true
                    url = "http://ca.example.com/crl"
                    cache_path = "/tmp/crl.crl"
                    max_age_hours = 24
                }
            }
            $context = New-WorkflowContext -Config $config

            # Act
            Step-MonitorCertificate -Context $context

            # Assert
            Should -Invoke -ModuleName EstWorkflow Update-CrlCache -Times 1 -ParameterFilter {
                $Url -eq "http://ca.example.com/crl" -and
                $CachePath -eq "/tmp/crl.crl" -and
                $MaxAgeHours -eq 24
            }
        }

        It "Sets Revoked status when certificate is revoked" {
            # Arrange
            Mock -ModuleName EstWorkflow Test-CertificateRevoked {
                return $true
            }

            $crlCachePath = Join-Path $script:TestDir "crl.crl"
            "MOCK CRL" | Out-File $crlCachePath

            $config = @{
                cert_path = $script:TestCertPath
                renewal_threshold_pct = 80
                crl = @{
                    enabled = $true
                    url = "http://ca.example.com/crl"
                    cache_path = $crlCachePath
                    max_age_hours = 24
                }
            }
            $context = New-WorkflowContext -Config $config

            # Act
            $result = Step-MonitorCertificate -Context $context

            # Assert
            $context.State.CertificateStatus.Revoked | Should -Be $true
            $result.Revoked | Should -Be $true
        }

        It "Sets RenewalRequired when certificate is revoked" {
            # Arrange
            Mock -ModuleName EstWorkflow Get-CertificateInfo {
                return @{
                    ExpiryDate = (Get-Date).AddDays(60)
                    LifetimePercentage = 30  # Well under threshold
                    Subject = "CN=test-device"
                }
            }

            Mock -ModuleName EstWorkflow Test-CertificateRevoked {
                return $true
            }

            $crlCachePath = Join-Path $script:TestDir "crl.crl"
            "MOCK CRL" | Out-File $crlCachePath

            $config = @{
                cert_path = $script:TestCertPath
                renewal_threshold_pct = 80
                crl = @{
                    enabled = $true
                    url = "http://ca.example.com/crl"
                    cache_path = $crlCachePath
                    max_age_hours = 24
                }
            }
            $context = New-WorkflowContext -Config $config

            # Act
            $result = Step-MonitorCertificate -Context $context

            # Assert - should require renewal despite being under threshold
            $context.State.CertificateStatus.RenewalRequired | Should -Be $true
            $result.RenewalRequired | Should -Be $true
        }
    }

    Context "Step-DecideAction" {
        It "Decides 'enroll' when certificate doesn't exist" {
            # Arrange
            $config = @{}
            $context = New-WorkflowContext -Config $config
            $context.State.CertificateStatus.Exists = $false

            # Act
            $decision = Step-DecideAction -Context $context

            # Assert
            $decision.Action | Should -Be "enroll"
            $decision.Reason | Should -Match "does not exist"
            $decision.AuthMode | Should -Be "bootstrap"
        }

        It "Decides 'reenroll' with bootstrap when certificate is revoked" {
            # Arrange
            $config = @{}
            $context = New-WorkflowContext -Config $config
            $context.State.CertificateStatus.Exists = $true
            $context.State.CertificateStatus.Revoked = $true
            $context.State.CertificateStatus.RenewalRequired = $true

            # Act
            $decision = Step-DecideAction -Context $context

            # Assert
            $decision.Action | Should -Be "reenroll"
            $decision.Reason | Should -Match "revoked"
            $decision.AuthMode | Should -Be "bootstrap"
        }

        It "Decides 'reenroll' with mtls when renewal required (over threshold)" {
            # Arrange
            $config = @{}
            $context = New-WorkflowContext -Config $config
            $context.State.CertificateStatus.Exists = $true
            $context.State.CertificateStatus.Revoked = $false
            $context.State.CertificateStatus.RenewalRequired = $true

            # Act
            $decision = Step-DecideAction -Context $context

            # Assert
            $decision.Action | Should -Be "reenroll"
            $decision.Reason | Should -Match "threshold"
            $decision.AuthMode | Should -Be "mtls"
        }

        It "Decides 'skip' when certificate is valid" {
            # Arrange
            $config = @{}
            $context = New-WorkflowContext -Config $config
            $context.State.CertificateStatus.Exists = $true
            $context.State.CertificateStatus.Revoked = $false
            $context.State.CertificateStatus.RenewalRequired = $false

            # Act
            $decision = Step-DecideAction -Context $context

            # Assert
            $decision.Action | Should -Be "skip"
            $decision.Reason | Should -Match "valid"
        }

        It "Returns hashtable with Action, Reason, and AuthMode" {
            # Arrange
            $config = @{}
            $context = New-WorkflowContext -Config $config
            $context.State.CertificateStatus.Exists = $false

            # Act
            $decision = Step-DecideAction -Context $context

            # Assert
            $decision.Keys | Should -Contain "Action"
            $decision.Keys | Should -Contain "Reason"
            $decision.Keys | Should -Contain "AuthMode"
        }
    }

    Context "Step-ExecuteEstProtocol - Skip Action" {
        It "Returns skip result when action is skip" {
            # Arrange
            $config = @{
                device_name = "test-device"
                pki_url = "https://pki.example.com:9000"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{
                Action = "skip"
            }

            # Act
            $result = Step-ExecuteEstProtocol -Context $context

            # Assert
            $result.Action | Should -Be "skip"
            $result.Success | Should -Be $true
        }

        It "Does not call EST functions when skipping" {
            # Arrange
            Mock -ModuleName EstWorkflow Invoke-EstEnrollment { }
            Mock -ModuleName EstWorkflow Invoke-EstReenrollment { }

            $config = @{
                device_name = "test-device"
                pki_url = "https://pki.example.com:9000"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{
                Action = "skip"
            }

            # Act
            Step-ExecuteEstProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName EstWorkflow Invoke-EstEnrollment -Times 0
            Should -Invoke -ModuleName EstWorkflow Invoke-EstReenrollment -Times 0
        }
    }

    Context "Step-ExecuteEstProtocol - Initial Enrollment" {
        BeforeEach {
            # Mock EST functions
            Mock -ModuleName EstWorkflow Get-BootstrapToken {
                return "mock-bootstrap-token"
            }

            Mock -ModuleName EstWorkflow New-CertificateRequest {
                return "-----BEGIN CERTIFICATE REQUEST-----`nMOCK CSR`n-----END CERTIFICATE REQUEST-----"
            }

            Mock -ModuleName EstWorkflow Invoke-EstEnrollment {
                return "-----BEGIN CERTIFICATE-----`nMOCK CERT`n-----END CERTIFICATE-----"
            }

            Mock -ModuleName EstWorkflow Export-PrivateKey {
                return "-----BEGIN PRIVATE KEY-----`nMOCK KEY`n-----END PRIVATE KEY-----"
            }

            Mock -ModuleName EstWorkflow Write-FileAtomic { }
            Mock -ModuleName EstWorkflow Set-FilePermissions { }

            # Mock X509Certificate2 parsing
            Mock -ModuleName EstWorkflow New-Object {
                param($TypeName, $ArgumentList)
                if ($TypeName -eq "System.Security.Cryptography.X509Certificates.X509Certificate2") {
                    return @{
                        Subject = "CN=test-device"
                        NotAfter = (Get-Date).AddDays(90)
                    }
                }
                throw "Unexpected New-Object call"
            } -ParameterFilter {
                $TypeName -eq "System.Security.Cryptography.X509Certificates.X509Certificate2"
            }

            Mock -ModuleName EstWorkflow Remove-Item { }
        }

        It "Calls Get-BootstrapToken for initial enrollment" {
            # Arrange
            $config = @{
                device_name = "test-device"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/output/cert.pem"
                key_path = "/output/key.pem"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{
                Action = "enroll"
                AuthMode = "bootstrap"
            }

            # Act
            Step-ExecuteEstProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName EstWorkflow Get-BootstrapToken -Times 1
        }

        It "Calls New-CertificateRequest with device name" {
            # Arrange
            $config = @{
                device_name = "my-iot-device"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/output/cert.pem"
                key_path = "/output/key.pem"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{
                Action = "enroll"
                AuthMode = "bootstrap"
            }

            # Act
            Step-ExecuteEstProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName EstWorkflow New-CertificateRequest -Times 1 -ParameterFilter {
                $SubjectDN -eq "CN=my-iot-device"
            }
        }

        It "Calls Invoke-EstEnrollment with correct parameters" {
            # Arrange
            $config = @{
                device_name = "test-device"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/output/cert.pem"
                key_path = "/output/key.pem"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{
                Action = "enroll"
                AuthMode = "bootstrap"
            }

            # Act
            Step-ExecuteEstProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName EstWorkflow Invoke-EstEnrollment -Times 1 -ParameterFilter {
                $PkiUrl -eq "https://pki.example.com:9000" -and
                $ProvisionerName -eq "default" -and
                $BootstrapToken -eq "mock-bootstrap-token"
            }
        }

        It "Saves certificate to configured path" {
            # Arrange
            $config = @{
                device_name = "test-device"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/output/device.crt"
                key_path = "/output/device.key"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{
                Action = "enroll"
                AuthMode = "bootstrap"
            }

            # Act
            Step-ExecuteEstProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName EstWorkflow Write-FileAtomic -Times 1 -ParameterFilter {
                $Path -eq "/output/device.crt"
            }
        }

        It "Saves private key to configured path" {
            # Arrange
            $config = @{
                device_name = "test-device"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/output/device.crt"
                key_path = "/output/device.key"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{
                Action = "enroll"
                AuthMode = "bootstrap"
            }

            # Act
            Step-ExecuteEstProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName EstWorkflow Write-FileAtomic -Times 1 -ParameterFilter {
                $Path -eq "/output/device.key"
            }
        }

        It "Sets key file permissions to 0600" {
            # Arrange
            $config = @{
                device_name = "test-device"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/output/device.crt"
                key_path = "/output/device.key"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{
                Action = "enroll"
                AuthMode = "bootstrap"
            }

            # Act
            Step-ExecuteEstProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName EstWorkflow Set-FilePermissions -Times 1 -ParameterFilter {
                $Path -eq "/output/device.key" -and $Mode -eq "0600"
            }
        }

        It "Sets certificate file permissions to 0644" {
            # Arrange
            $config = @{
                device_name = "test-device"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/output/device.crt"
                key_path = "/output/device.key"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{
                Action = "enroll"
                AuthMode = "bootstrap"
            }

            # Act
            Step-ExecuteEstProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName EstWorkflow Set-FilePermissions -Times 1 -ParameterFilter {
                $Path -eq "/output/device.crt" -and $Mode -eq "0644"
            }
        }

        It "Returns success result with certificate details" {
            # Arrange
            $config = @{
                device_name = "test-device"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/output/device.crt"
                key_path = "/output/device.key"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{
                Action = "enroll"
                AuthMode = "bootstrap"
            }

            # Act
            $result = Step-ExecuteEstProtocol -Context $context

            # Assert
            $result.Success | Should -Be $true
            $result.Action | Should -Be "enroll"
            $result.AuthMode | Should -Be "bootstrap"
            $result.CertificatePath | Should -Be "/output/device.crt"
            $result.KeyPath | Should -Be "/output/device.key"
        }
    }

    Context "Step-ExecuteEstProtocol - Re-enrollment with mTLS" {
        BeforeEach {
            Mock -ModuleName EstWorkflow New-CertificateRequest {
                return "-----BEGIN CERTIFICATE REQUEST-----`nMOCK CSR`n-----END CERTIFICATE REQUEST-----"
            }

            Mock -ModuleName EstWorkflow Invoke-EstReenrollment {
                return "-----BEGIN CERTIFICATE-----`nMOCK NEW CERT`n-----END CERTIFICATE-----"
            }

            Mock -ModuleName EstWorkflow Export-PrivateKey {
                return "-----BEGIN PRIVATE KEY-----`nMOCK NEW KEY`n-----END PRIVATE KEY-----"
            }

            Mock -ModuleName EstWorkflow Get-CertificateInfo {
                return @{
                    Subject = "CN=existing-device"
                    ExpiryDate = (Get-Date).AddDays(30)
                    LifetimePercentage = 80
                }
            }

            Mock -ModuleName EstWorkflow Write-FileAtomic { }
            Mock -ModuleName EstWorkflow Set-FilePermissions { }
            Mock -ModuleName EstWorkflow Move-Item { }

            Mock -ModuleName EstWorkflow New-Object {
                param($TypeName, $ArgumentList)
                if ($TypeName -eq "System.Security.Cryptography.X509Certificates.X509Certificate2") {
                    return @{
                        Subject = "CN=existing-device"
                        NotAfter = (Get-Date).AddDays(90)
                    }
                }
                throw "Unexpected New-Object call"
            } -ParameterFilter {
                $TypeName -eq "System.Security.Cryptography.X509Certificates.X509Certificate2"
            }

            Mock -ModuleName EstWorkflow Remove-Item { }
        }

        It "Calls Invoke-EstReenrollment with mTLS" {
            # Arrange
            $config = @{
                device_name = "test-device"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/certs/device.crt"
                key_path = "/certs/device.key"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{
                Action = "reenroll"
                AuthMode = "mtls"
            }

            # Act
            Step-ExecuteEstProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName EstWorkflow Invoke-EstReenrollment -Times 1 -ParameterFilter {
                $PkiUrl -eq "https://pki.example.com:9000" -and
                $ExistingCertPath -eq "/certs/device.crt" -and
                $ExistingKeyPath -eq "/certs/device.key"
            }
        }

        It "Uses existing certificate subject for CSR" {
            # Arrange
            Mock -ModuleName EstWorkflow Get-CertificateInfo {
                return @{
                    Subject = "CN=my-specific-device"
                    ExpiryDate = (Get-Date).AddDays(30)
                    LifetimePercentage = 85
                }
            }

            $config = @{
                device_name = "test-device"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/certs/device.crt"
                key_path = "/certs/device.key"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{
                Action = "reenroll"
                AuthMode = "mtls"
            }

            # Act
            Step-ExecuteEstProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName EstWorkflow New-CertificateRequest -Times 1 -ParameterFilter {
                $SubjectDN -eq "CN=my-specific-device"
            }
        }

        It "Writes to temporary files before atomic move" {
            # Arrange
            $config = @{
                device_name = "test-device"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/certs/device.crt"
                key_path = "/certs/device.key"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{
                Action = "reenroll"
                AuthMode = "mtls"
            }

            # Act
            Step-ExecuteEstProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName EstWorkflow Write-FileAtomic -ParameterFilter {
                $Path -eq "/certs/device.crt.new"
            }
            Should -Invoke -ModuleName EstWorkflow Write-FileAtomic -ParameterFilter {
                $Path -eq "/certs/device.key.new"
            }
        }

        It "Performs atomic move after writing temp files" {
            # Arrange
            $config = @{
                device_name = "test-device"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/certs/device.crt"
                key_path = "/certs/device.key"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{
                Action = "reenroll"
                AuthMode = "mtls"
            }

            # Act
            Step-ExecuteEstProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName EstWorkflow Move-Item -Times 1 -ParameterFilter {
                $Path -eq "/certs/device.crt.new" -and
                $Destination -eq "/certs/device.crt" -and
                $Force -eq $true
            }
            Should -Invoke -ModuleName EstWorkflow Move-Item -Times 1 -ParameterFilter {
                $Path -eq "/certs/device.key.new" -and
                $Destination -eq "/certs/device.key" -and
                $Force -eq $true
            }
        }

        It "Returns success with mtls auth mode" {
            # Arrange
            $config = @{
                device_name = "test-device"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/certs/device.crt"
                key_path = "/certs/device.key"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{
                Action = "reenroll"
                AuthMode = "mtls"
            }

            # Act
            $result = Step-ExecuteEstProtocol -Context $context

            # Assert
            $result.Success | Should -Be $true
            $result.Action | Should -Be "reenroll"
            $result.AuthMode | Should -Be "mtls"
        }
    }

    Context "Step-ExecuteEstProtocol - Re-enrollment with Bootstrap Token" {
        BeforeEach {
            Mock -ModuleName EstWorkflow Get-BootstrapToken {
                return "mock-bootstrap-token"
            }

            Mock -ModuleName EstWorkflow New-CertificateRequest {
                return "-----BEGIN CERTIFICATE REQUEST-----`nMOCK CSR`n-----END CERTIFICATE REQUEST-----"
            }

            Mock -ModuleName EstWorkflow Invoke-EstEnrollment {
                return "-----BEGIN CERTIFICATE-----`nMOCK NEW CERT`n-----END CERTIFICATE-----"
            }

            Mock -ModuleName EstWorkflow Export-PrivateKey {
                return "-----BEGIN PRIVATE KEY-----`nMOCK NEW KEY`n-----END PRIVATE KEY-----"
            }

            Mock -ModuleName EstWorkflow Get-CertificateInfo {
                return @{
                    Subject = "CN=revoked-device"
                    ExpiryDate = (Get-Date).AddDays(30)
                    LifetimePercentage = 50
                }
            }

            Mock -ModuleName EstWorkflow Write-FileAtomic { }
            Mock -ModuleName EstWorkflow Set-FilePermissions { }
            Mock -ModuleName EstWorkflow Move-Item { }

            Mock -ModuleName EstWorkflow New-Object {
                param($TypeName, $ArgumentList)
                if ($TypeName -eq "System.Security.Cryptography.X509Certificates.X509Certificate2") {
                    return @{
                        Subject = "CN=revoked-device"
                        NotAfter = (Get-Date).AddDays(90)
                    }
                }
                throw "Unexpected New-Object call"
            } -ParameterFilter {
                $TypeName -eq "System.Security.Cryptography.X509Certificates.X509Certificate2"
            }

            Mock -ModuleName EstWorkflow Remove-Item { }
        }

        It "Uses bootstrap token when authMode is bootstrap" {
            # Arrange
            $config = @{
                device_name = "test-device"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/certs/device.crt"
                key_path = "/certs/device.key"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{
                Action = "reenroll"
                AuthMode = "bootstrap"  # Use bootstrap for revoked cert
            }

            # Act
            Step-ExecuteEstProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName EstWorkflow Get-BootstrapToken -Times 1
            Should -Invoke -ModuleName EstWorkflow Invoke-EstEnrollment -Times 1
            Should -Invoke -ModuleName EstWorkflow Invoke-EstReenrollment -Times 0
        }
    }

    Context "Step-ExecuteEstProtocol - Error Handling" {
        BeforeEach {
            Mock -ModuleName EstWorkflow Get-BootstrapToken {
                return "mock-token"
            }

            Mock -ModuleName EstWorkflow New-CertificateRequest {
                return "MOCK CSR"
            }
        }

        It "Returns failure result when Invoke-EstEnrollment throws" {
            # Arrange
            Mock -ModuleName EstWorkflow Invoke-EstEnrollment {
                throw "EST protocol error: Server unreachable"
            }

            $config = @{
                device_name = "test-device"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/output/cert.pem"
                key_path = "/output/key.pem"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{
                Action = "enroll"
                AuthMode = "bootstrap"
            }

            # Act
            $result = Step-ExecuteEstProtocol -Context $context

            # Assert
            $result.Success | Should -Be $false
            $result.Error | Should -Not -BeNullOrEmpty
        }

        It "Returns failure result when Get-BootstrapToken fails" {
            # Arrange
            Mock -ModuleName EstWorkflow Get-BootstrapToken {
                throw "Bootstrap token not configured"
            }

            $config = @{
                device_name = "test-device"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/output/cert.pem"
                key_path = "/output/key.pem"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{
                Action = "enroll"
                AuthMode = "bootstrap"
            }

            # Act
            $result = Step-ExecuteEstProtocol -Context $context

            # Assert
            $result.Success | Should -Be $false
            $result.Message | Should -Match "failed"
        }
    }

    Context "Step-ValidateDeployment" {
        It "Returns success when certificate and key exist" {
            # Arrange
            $certPath = Join-Path $script:TestDir "valid-cert.pem"
            $keyPath = Join-Path $script:TestDir "valid-key.pem"
            "CERT" | Out-File $certPath
            "KEY" | Out-File $keyPath

            $config = @{
                cert_path = $certPath
                key_path = $keyPath
            }
            $context = New-WorkflowContext -Config $config

            # Act
            $result = Step-ValidateDeployment -Context $context

            # Assert
            $result.CertificateValid | Should -Be $true
            $result.KeyValid | Should -Be $true
            $result.Message | Should -Match "success"
        }

        It "Returns failure when certificate doesn't exist" {
            # Arrange
            $keyPath = Join-Path $script:TestDir "exists-key.pem"
            "KEY" | Out-File $keyPath

            $config = @{
                cert_path = "/nonexistent/cert.pem"
                key_path = $keyPath
            }
            $context = New-WorkflowContext -Config $config

            # Act
            $result = Step-ValidateDeployment -Context $context

            # Assert
            $result.CertificateValid | Should -Be $false
            $result.Message | Should -Match "not found"
        }

        It "Returns failure when key doesn't exist" {
            # Arrange
            $certPath = Join-Path $script:TestDir "exists-cert.pem"
            "CERT" | Out-File $certPath

            $config = @{
                cert_path = $certPath
                key_path = "/nonexistent/key.pem"
            }
            $context = New-WorkflowContext -Config $config

            # Act
            $result = Step-ValidateDeployment -Context $context

            # Assert
            $result.KeyValid | Should -Be $false
            $result.Message | Should -Match "not found"
        }
    }

    Context "Initialize-EstWorkflowSteps" {
        BeforeEach {
            # Reset workflow metrics to clear any registered steps
            Reset-WorkflowMetrics
        }

        It "Registers all workflow steps" {
            # Act
            Initialize-EstWorkflowSteps

            # Assert
            $metrics = Get-WorkflowMetrics
            $metrics.RegisteredSteps | Should -BeGreaterOrEqual 4
        }

        It "Registers Monitor step" {
            # Act
            Initialize-EstWorkflowSteps

            # Assert
            $metrics = Get-WorkflowMetrics
            $metrics.StepMetrics.Keys | Should -Contain "Monitor"
        }

        It "Registers Decide step" {
            # Act
            Initialize-EstWorkflowSteps

            # Assert
            $metrics = Get-WorkflowMetrics
            $metrics.StepMetrics.Keys | Should -Contain "Decide"
        }

        It "Registers Execute step" {
            # Act
            Initialize-EstWorkflowSteps

            # Assert
            $metrics = Get-WorkflowMetrics
            $metrics.StepMetrics.Keys | Should -Contain "Execute"
        }

        It "Registers Validate step" {
            # Act
            Initialize-EstWorkflowSteps

            # Assert
            $metrics = Get-WorkflowMetrics
            $metrics.StepMetrics.Keys | Should -Contain "Validate"
        }

        It "Allows registered steps to be executed" {
            # Arrange
            Initialize-EstWorkflowSteps

            Mock -ModuleName EstWorkflow Get-CertificateInfo {
                return @{
                    ExpiryDate = (Get-Date).AddDays(30)
                    LifetimePercentage = 50
                    Subject = "CN=test-device"
                }
            }

            $testCertPath = Join-Path $script:TestDir "registered-cert.pem"
            "CERT" | Out-File $testCertPath

            $config = @{
                cert_path = $testCertPath
                renewal_threshold_pct = 80
                crl = @{ enabled = $false }
            }
            $context = New-WorkflowContext -Config $config

            # Act & Assert - should not throw
            { Invoke-WorkflowStep -Name "Monitor" -Context $context } | Should -Not -Throw
        }
    }
}
