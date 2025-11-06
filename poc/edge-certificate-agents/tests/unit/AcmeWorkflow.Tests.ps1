# ==============================================================================
# AcmeWorkflow.Tests.ps1 - Unit Tests for ACME Workflow Module
# ==============================================================================
# Tests for ACME certificate lifecycle workflow (Monitor, Decide, Execute, Validate)
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

    # Import module under test
    $modulePath = Resolve-Path "$PSScriptRoot/../../agents/acme/AcmeWorkflow.psm1"
    Import-Module $modulePath -Force

    # Create test directory
    $script:TestDir = Join-Path $TestDrive "acme-workflow-tests"
    New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null

    # Mock Write-Log functions
    Mock -ModuleName AcmeWorkflow Write-LogInfo { }
    Mock -ModuleName AcmeWorkflow Write-LogError { }
    Mock -ModuleName AcmeWorkflow Write-LogDebug { }
    Mock -ModuleName AcmeWorkflow Write-LogWarning { }
}

AfterAll {
    # Cleanup
    Remove-Module AcmeWorkflow -Force -ErrorAction SilentlyContinue
    Remove-Module FileOperations -Force -ErrorAction SilentlyContinue
    Remove-Module CrlValidator -Force -ErrorAction SilentlyContinue
    Remove-Module CertificateMonitor -Force -ErrorAction SilentlyContinue
    Remove-Module WorkflowOrchestrator -Force -ErrorAction SilentlyContinue
    Remove-Module Logger -Force -ErrorAction SilentlyContinue
}

Describe "AcmeWorkflow Module" -Tags @('Unit', 'ACME', 'Workflow') {

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
            Mock -ModuleName AcmeWorkflow Get-CertificateInfo {
                return @{
                    ExpiryDate = (Get-Date).AddDays(30)
                    LifetimePercentage = 75
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
            Should -Invoke -ModuleName AcmeWorkflow Get-CertificateInfo -Times 1 -ParameterFilter {
                $Path -eq $script:TestCertPath
            }
        }

        It "Sets ExpiryDate and LifetimePercentage from CertificateInfo" {
            # Arrange
            $expectedExpiry = (Get-Date).AddDays(45)
            Mock -ModuleName AcmeWorkflow Get-CertificateInfo {
                return @{
                    ExpiryDate = $expectedExpiry
                    LifetimePercentage = 60
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
            Mock -ModuleName AcmeWorkflow Get-CertificateInfo {
                return @{
                    ExpiryDate = (Get-Date).AddDays(60)
                    LifetimePercentage = 50
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
            Mock -ModuleName AcmeWorkflow Get-CertificateInfo {
                return @{
                    ExpiryDate = (Get-Date).AddDays(10)
                    LifetimePercentage = 85
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

            Mock -ModuleName AcmeWorkflow Get-CertificateInfo {
                return @{
                    ExpiryDate = (Get-Date).AddDays(30)
                    LifetimePercentage = 50
                }
            }

            Mock -ModuleName AcmeWorkflow Update-CrlCache {
                return @{ Updated = $true }
            }

            Mock -ModuleName AcmeWorkflow Test-CertificateRevoked {
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
            Should -Invoke -ModuleName AcmeWorkflow Update-CrlCache -Times 0
            Should -Invoke -ModuleName AcmeWorkflow Test-CertificateRevoked -Times 0
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
            Should -Invoke -ModuleName AcmeWorkflow Update-CrlCache -Times 1 -ParameterFilter {
                $Url -eq "http://ca.example.com/crl" -and
                $CachePath -eq "/tmp/crl.crl" -and
                $MaxAgeHours -eq 24
            }
        }

        It "Calls Test-CertificateRevoked when CRL updated" {
            # Arrange
            Mock -ModuleName AcmeWorkflow Update-CrlCache {
                return @{ Updated = $true }
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
            Step-MonitorCertificate -Context $context

            # Assert
            Should -Invoke -ModuleName AcmeWorkflow Test-CertificateRevoked -Times 1
        }

        It "Sets Revoked status when certificate is revoked" {
            # Arrange
            Mock -ModuleName AcmeWorkflow Test-CertificateRevoked {
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
            Mock -ModuleName AcmeWorkflow Get-CertificateInfo {
                return @{
                    ExpiryDate = (Get-Date).AddDays(60)
                    LifetimePercentage = 30  # Well under threshold
                }
            }

            Mock -ModuleName AcmeWorkflow Test-CertificateRevoked {
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
        }

        It "Decides 'renew' when certificate is revoked" {
            # Arrange
            $config = @{}
            $context = New-WorkflowContext -Config $config
            $context.State.CertificateStatus.Exists = $true
            $context.State.CertificateStatus.Revoked = $true
            $context.State.CertificateStatus.RenewalRequired = $true

            # Act
            $decision = Step-DecideAction -Context $context

            # Assert
            $decision.Action | Should -Be "renew"
            $decision.Reason | Should -Match "revoked"
        }

        It "Decides 'renew' when renewal required (over threshold)" {
            # Arrange
            $config = @{}
            $context = New-WorkflowContext -Config $config
            $context.State.CertificateStatus.Exists = $true
            $context.State.CertificateStatus.Revoked = $false
            $context.State.CertificateStatus.RenewalRequired = $true

            # Act
            $decision = Step-DecideAction -Context $context

            # Assert
            $decision.Action | Should -Be "renew"
            $decision.Reason | Should -Match "threshold"
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

        It "Returns hashtable with Action and Reason" {
            # Arrange
            $config = @{}
            $context = New-WorkflowContext -Config $config
            $context.State.CertificateStatus.Exists = $false

            # Act
            $decision = Step-DecideAction -Context $context

            # Assert
            $decision.Keys | Should -Contain "Action"
            $decision.Keys | Should -Contain "Reason"
        }
    }

    Context "Step-ExecuteAcmeProtocol - Skip Action" {
        It "Returns skip result when action is skip" {
            # Arrange
            $config = @{
                domain_name = "test.example.com"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{
                Action = "skip"
            }

            # Act
            $result = Step-ExecuteAcmeProtocol -Context $context

            # Assert
            $result.Action | Should -Be "skip"
            $result.Success | Should -Be $true
        }

        It "Does not call Posh-ACME cmdlets when skipping" {
            # Arrange
            Mock -ModuleName AcmeWorkflow Set-PAServer { }
            Mock -ModuleName AcmeWorkflow New-PACertificate { }

            $config = @{
                domain_name = "test.example.com"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{
                Action = "skip"
            }

            # Act
            Step-ExecuteAcmeProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName AcmeWorkflow Set-PAServer -Times 0
            Should -Invoke -ModuleName AcmeWorkflow New-PACertificate -Times 0
        }
    }

    Context "Step-ExecuteAcmeProtocol - Posh-ACME Initialization" {
        BeforeEach {
            # Mock Posh-ACME cmdlets
            Mock -ModuleName AcmeWorkflow Set-PAServer { }
            Mock -ModuleName AcmeWorkflow Get-PAAccount {
                return @{
                    ID = "test-account"
                    status = "valid"
                }
            }
            Mock -ModuleName AcmeWorkflow New-PAAccount {
                return @{
                    ID = "new-account"
                    status = "valid"
                }
            }
            Mock -ModuleName AcmeWorkflow New-PACertificate {
                return @{
                    Subject = "CN=test.example.com"
                    NotAfter = (Get-Date).AddDays(90)
                    CertFile = (Join-Path $script:TestDir "cert.pem")
                    KeyFile = (Join-Path $script:TestDir "key.pem")
                    FullChainFile = (Join-Path $script:TestDir "fullchain.pem")
                    ChainFile = (Join-Path $script:TestDir "chain.pem")
                }
            }

            # Create mock certificate files
            "MOCK CERT" | Out-File (Join-Path $script:TestDir "cert.pem")
            "MOCK KEY" | Out-File (Join-Path $script:TestDir "key.pem")
            "MOCK FULLCHAIN" | Out-File (Join-Path $script:TestDir "fullchain.pem")
            "MOCK CHAIN" | Out-File (Join-Path $script:TestDir "chain.pem")

            # Mock file operations
            Mock -ModuleName AcmeWorkflow Write-FileAtomic { }
            Mock -ModuleName AcmeWorkflow Set-FilePermissions { }
        }

        It "Calls Set-PAServer with correct directory URL" {
            # Arrange
            $config = @{
                domain_name = "test.example.com"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/certs/cert.pem"
                key_path = "/certs/key.pem"
                environment = "production"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{ Action = "enroll" }

            # Act
            Step-ExecuteAcmeProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName AcmeWorkflow Set-PAServer -Times 1 -ParameterFilter {
                $DirectoryUrl -like "*/acme/acme/directory"
            }
        }

        It "Calls Get-PAAccount to check for existing account" {
            # Arrange
            $config = @{
                domain_name = "test.example.com"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/certs/cert.pem"
                key_path = "/certs/key.pem"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{ Action = "enroll" }

            # Act
            Step-ExecuteAcmeProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName AcmeWorkflow Get-PAAccount -Times 1
        }

        It "Creates new account when none exists" {
            # Arrange
            Mock -ModuleName AcmeWorkflow Get-PAAccount {
                return $null
            }

            $config = @{
                domain_name = "test.example.com"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/certs/cert.pem"
                key_path = "/certs/key.pem"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{ Action = "enroll" }

            # Act
            Step-ExecuteAcmeProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName AcmeWorkflow New-PAAccount -Times 1 -ParameterFilter {
                $AcceptTOS -eq $true
            }
        }

        It "Uses existing account when available" {
            # Arrange - Get-PAAccount returns valid account (mocked in BeforeEach)
            $config = @{
                domain_name = "test.example.com"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/certs/cert.pem"
                key_path = "/certs/key.pem"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{ Action = "enroll" }

            # Act
            Step-ExecuteAcmeProtocol -Context $context

            # Assert - should not create new account
            Should -Invoke -ModuleName AcmeWorkflow New-PAAccount -Times 0
        }
    }

    Context "Step-ExecuteAcmeProtocol - Certificate Request" {
        BeforeEach {
            Mock -ModuleName AcmeWorkflow Set-PAServer { }
            Mock -ModuleName AcmeWorkflow Get-PAAccount {
                return @{ ID = "test-account"; status = "valid" }
            }
            Mock -ModuleName AcmeWorkflow New-PACertificate {
                return @{
                    Subject = "CN=test.example.com"
                    NotAfter = (Get-Date).AddDays(90)
                    CertFile = (Join-Path $script:TestDir "cert.pem")
                    KeyFile = (Join-Path $script:TestDir "key.pem")
                    FullChainFile = (Join-Path $script:TestDir "fullchain.pem")
                    ChainFile = (Join-Path $script:TestDir "chain.pem")
                }
            }

            "MOCK CERT" | Out-File (Join-Path $script:TestDir "cert.pem")
            "MOCK KEY" | Out-File (Join-Path $script:TestDir "key.pem")
            "MOCK FULLCHAIN" | Out-File (Join-Path $script:TestDir "fullchain.pem")
            "MOCK CHAIN" | Out-File (Join-Path $script:TestDir "chain.pem")

            Mock -ModuleName AcmeWorkflow Write-FileAtomic { }
            Mock -ModuleName AcmeWorkflow Set-FilePermissions { }
        }

        It "Calls New-PACertificate with correct domain" {
            # Arrange
            $config = @{
                domain_name = "test.example.com"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/certs/cert.pem"
                key_path = "/certs/key.pem"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{ Action = "enroll" }

            # Act
            Step-ExecuteAcmeProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName AcmeWorkflow New-PACertificate -Times 1 -ParameterFilter {
                $Domain -contains "test.example.com"
            }
        }

        It "Requests certificate with Force parameter for renewal" {
            # Arrange
            $config = @{
                domain_name = "test.example.com"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/certs/cert.pem"
                key_path = "/certs/key.pem"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{ Action = "renew" }

            # Act
            Step-ExecuteAcmeProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName AcmeWorkflow New-PACertificate -Times 1 -ParameterFilter {
                $Force -eq $true
            }
        }

        It "Configures WebRoot plugin for HTTP-01 challenge" {
            # Arrange
            $config = @{
                domain_name = "test.example.com"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/certs/cert.pem"
                key_path = "/certs/key.pem"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{ Action = "enroll" }

            # Act
            Step-ExecuteAcmeProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName AcmeWorkflow New-PACertificate -Times 1 -ParameterFilter {
                $Plugin -eq 'WebRoot'
            }
        }

        It "Saves certificate to configured path" {
            # Arrange
            $config = @{
                domain_name = "test.example.com"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/output/cert.pem"
                key_path = "/output/key.pem"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{ Action = "enroll" }

            # Act
            Step-ExecuteAcmeProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName AcmeWorkflow Write-FileAtomic -Times 1 -ParameterFilter {
                $Path -eq "/output/cert.pem"
            }
        }

        It "Saves private key to configured path" {
            # Arrange
            $config = @{
                domain_name = "test.example.com"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/output/cert.pem"
                key_path = "/output/key.pem"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{ Action = "enroll" }

            # Act
            Step-ExecuteAcmeProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName AcmeWorkflow Write-FileAtomic -Times 1 -ParameterFilter {
                $Path -eq "/output/key.pem"
            }
        }

        It "Sets key file permissions to 0600" {
            # Arrange
            $config = @{
                domain_name = "test.example.com"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/output/cert.pem"
                key_path = "/output/key.pem"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{ Action = "enroll" }

            # Act
            Step-ExecuteAcmeProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName AcmeWorkflow Set-FilePermissions -Times 1 -ParameterFilter {
                $Path -eq "/output/key.pem" -and $Mode -eq "0600"
            }
        }

        It "Sets certificate file permissions to 0644" {
            # Arrange
            $config = @{
                domain_name = "test.example.com"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/output/cert.pem"
                key_path = "/output/key.pem"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{ Action = "enroll" }

            # Act
            Step-ExecuteAcmeProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName AcmeWorkflow Set-FilePermissions -Times 1 -ParameterFilter {
                $Path -eq "/output/cert.pem" -and $Mode -eq "0644"
            }
        }

        It "Returns success result with certificate details" {
            # Arrange
            $config = @{
                domain_name = "test.example.com"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/output/cert.pem"
                key_path = "/output/key.pem"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{ Action = "enroll" }

            # Act
            $result = Step-ExecuteAcmeProtocol -Context $context

            # Assert
            $result.Success | Should -Be $true
            $result.CertificatePath | Should -Be "/output/cert.pem"
            $result.KeyPath | Should -Be "/output/key.pem"
            $result.Subject | Should -Not -BeNullOrEmpty
        }
    }

    Context "Step-ExecuteAcmeProtocol - Certificate Chain Handling" {
        BeforeEach {
            Mock -ModuleName AcmeWorkflow Set-PAServer { }
            Mock -ModuleName AcmeWorkflow Get-PAAccount {
                return @{ ID = "test-account"; status = "valid" }
            }
            Mock -ModuleName AcmeWorkflow New-PACertificate {
                return @{
                    Subject = "CN=test.example.com"
                    NotAfter = (Get-Date).AddDays(90)
                    CertFile = (Join-Path $script:TestDir "cert.pem")
                    KeyFile = (Join-Path $script:TestDir "key.pem")
                    FullChainFile = (Join-Path $script:TestDir "fullchain.pem")
                    ChainFile = (Join-Path $script:TestDir "chain.pem")
                }
            }

            "MOCK CERT" | Out-File (Join-Path $script:TestDir "cert.pem")
            "MOCK KEY" | Out-File (Join-Path $script:TestDir "key.pem")
            "MOCK FULLCHAIN" | Out-File (Join-Path $script:TestDir "fullchain.pem")
            "MOCK CHAIN" | Out-File (Join-Path $script:TestDir "chain.pem")

            Mock -ModuleName AcmeWorkflow Write-FileAtomic { }
            Mock -ModuleName AcmeWorkflow Set-FilePermissions { }
        }

        It "Saves full chain when configured" {
            # Arrange
            $config = @{
                domain_name = "test.example.com"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/output/cert.pem"
                key_path = "/output/key.pem"
                certificate_chain = @{
                    enabled = $true
                    installation = @{
                        install_full_chain_to_cert_path = $false
                        create_separate_chain_files = $true
                    }
                    full_chain_path = "/output/fullchain.pem"
                    intermediates_path = "/output/chain.pem"
                }
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{ Action = "enroll" }

            # Act
            Step-ExecuteAcmeProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName AcmeWorkflow Write-FileAtomic -ParameterFilter {
                $Path -eq "/output/fullchain.pem"
            }
        }

        It "Saves intermediates file when configured" {
            # Arrange
            $config = @{
                domain_name = "test.example.com"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/output/cert.pem"
                key_path = "/output/key.pem"
                certificate_chain = @{
                    enabled = $true
                    installation = @{
                        install_full_chain_to_cert_path = $false
                        create_separate_chain_files = $true
                    }
                    full_chain_path = "/output/fullchain.pem"
                    intermediates_path = "/output/chain.pem"
                }
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{ Action = "enroll" }

            # Act
            Step-ExecuteAcmeProtocol -Context $context

            # Assert
            Should -Invoke -ModuleName AcmeWorkflow Write-FileAtomic -ParameterFilter {
                $Path -eq "/output/chain.pem"
            }
        }
    }

    Context "Step-ExecuteAcmeProtocol - Error Handling" {
        BeforeEach {
            Mock -ModuleName AcmeWorkflow Set-PAServer { }
            Mock -ModuleName AcmeWorkflow Get-PAAccount {
                return @{ ID = "test-account"; status = "valid" }
            }
        }

        It "Returns failure result when New-PACertificate throws" {
            # Arrange
            Mock -ModuleName AcmeWorkflow New-PACertificate {
                throw "ACME protocol error: Invalid challenge response"
            }

            $config = @{
                domain_name = "test.example.com"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/output/cert.pem"
                key_path = "/output/key.pem"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{ Action = "enroll" }

            # Act
            $result = Step-ExecuteAcmeProtocol -Context $context

            # Assert
            $result.Success | Should -Be $false
            $result.Error | Should -Not -BeNullOrEmpty
        }

        It "Returns failure result when New-PACertificate returns null" {
            # Arrange
            Mock -ModuleName AcmeWorkflow New-PACertificate {
                return $null
            }

            $config = @{
                domain_name = "test.example.com"
                pki_url = "https://pki.example.com:9000"
                cert_path = "/output/cert.pem"
                key_path = "/output/key.pem"
            }
            $context = New-WorkflowContext -Config $config
            $context.State.LastDecision = @{ Action = "enroll" }

            # Act
            $result = Step-ExecuteAcmeProtocol -Context $context

            # Assert
            $result.Success | Should -Be $false
            $result.Message | Should -Match "no certificate returned"
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

    Context "Initialize-AcmeWorkflowSteps" {
        BeforeEach {
            # Reset workflow metrics to clear any registered steps
            Reset-WorkflowMetrics
        }

        It "Registers all workflow steps" {
            # Act
            Initialize-AcmeWorkflowSteps

            # Assert
            $metrics = Get-WorkflowMetrics
            $metrics.RegisteredSteps | Should -BeGreaterOrEqual 4
        }

        It "Registers Monitor step" {
            # Act
            Initialize-AcmeWorkflowSteps

            # Assert
            $metrics = Get-WorkflowMetrics
            $metrics.StepMetrics.Keys | Should -Contain "Monitor"
        }

        It "Registers Decide step" {
            # Act
            Initialize-AcmeWorkflowSteps

            # Assert
            $metrics = Get-WorkflowMetrics
            $metrics.StepMetrics.Keys | Should -Contain "Decide"
        }

        It "Registers Execute step" {
            # Act
            Initialize-AcmeWorkflowSteps

            # Assert
            $metrics = Get-WorkflowMetrics
            $metrics.StepMetrics.Keys | Should -Contain "Execute"
        }

        It "Registers Validate step" {
            # Act
            Initialize-AcmeWorkflowSteps

            # Assert
            $metrics = Get-WorkflowMetrics
            $metrics.StepMetrics.Keys | Should -Contain "Validate"
        }

        It "Allows registered steps to be executed" {
            # Arrange
            Initialize-AcmeWorkflowSteps

            Mock -ModuleName AcmeWorkflow Get-CertificateInfo {
                return @{
                    ExpiryDate = (Get-Date).AddDays(30)
                    LifetimePercentage = 50
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
