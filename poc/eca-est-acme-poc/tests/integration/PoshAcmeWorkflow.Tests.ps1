<#
.SYNOPSIS
    Integration tests for native Posh-ACME certificate workflows.

.DESCRIPTION
    Tests the complete certificate lifecycle using native Posh-ACME cmdlets:
    - Server configuration with Set-PAServer
    - Account creation with New-PAAccount
    - Order placement with New-PAOrder
    - HTTP-01 challenge handling
    - Order finalization with Submit-OrderFinalize
    - Certificate retrieval with Complete-PAOrder
    - Certificate and key file management

.NOTES
    These tests require a running step-ca PKI instance.
    Run with: docker compose up -d pki
    Requires: Pester 5.0+, PowerShell Core 7.0+, Posh-ACME 4.29.3+
#>

#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    # Import Posh-ACME module
    Import-Module Posh-ACME -Force

    # Import common modules for file operations
    $commonDir = "$PSScriptRoot/../../agents/common"
    Import-Module "$commonDir/FileOperations.psm1" -Force

    # Test configuration
    $script:PkiBaseUrl = $env:PKI_URL ?? "https://pki:9000"
    $script:TestDomain = "target-server"
    $script:TempDir = "/tmp/eca-native-poshacme-test-$(Get-Random)"
    $script:StateDir = Join-Path $script:TempDir "state"
    $env:POSHACME_HOME = $script:StateDir

    # Helper function to construct directory URL
    function Get-TestDirectoryUrl {
        param([string]$BaseUrl)
        return "$($BaseUrl.TrimEnd('/'))/acme/acme/directory"
    }

    # Create temp directory
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:StateDir -Force | Out-Null
}

AfterAll {
    # Cleanup
    Remove-Item Env:POSHACME_HOME -ErrorAction SilentlyContinue

    if (Test-Path $script:TempDir) {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Native Posh-ACME Integration Tests" -Tag "Integration", "Posh-ACME", "Native" {

    Context "Posh-ACME Server Configuration" {
        It "Can configure Posh-ACME server with Set-PAServer" {
            {
                $directoryUrl = Get-TestDirectoryUrl -BaseUrl $script:PkiBaseUrl
                Set-PAServer -DirectoryUrl $directoryUrl -SkipCertificateCheck
            } | Should -Not -Throw
        }

        It "Posh-ACME server configuration persists" {
            $server = Get-PAServer
            $server | Should -Not -BeNullOrEmpty
            $server.location | Should -BeLike "*acme/directory*"
        }

        It "Can retrieve server directory information" {
            $server = Get-PAServer
            $server.nonce | Should -Not -BeNullOrEmpty
            $server.newAccount | Should -Not -BeNullOrEmpty
            $server.newOrder | Should -Not -BeNullOrEmpty
        }
    }

    Context "Account Management with Native Posh-ACME" {
        BeforeAll {
            # Ensure server is configured
            $directoryUrl = Get-TestDirectoryUrl -BaseUrl $script:PkiBaseUrl
            Set-PAServer -DirectoryUrl $directoryUrl -SkipCertificateCheck
        }

        It "Can create Posh-ACME account with New-PAAccount" {
            {
                $account = New-PAAccount -AcceptTOS -Force
                $account | Should -Not -BeNullOrEmpty
                $account.ID | Should -Not -BeNullOrEmpty
                $account.status | Should -Be "valid"
            } | Should -Not -Throw
        }

        It "Can retrieve existing account with Get-PAAccount" {
            $account = Get-PAAccount
            $account | Should -Not -BeNullOrEmpty
            $account.ID | Should -Not -BeNullOrEmpty
            $account.status | Should -Be "valid"
        }

        It "Account has valid key identifier" {
            $account = Get-PAAccount
            $account.keyId | Should -Not -BeNullOrEmpty
        }
    }

    Context "Order Management with Native Posh-ACME" {
        BeforeAll {
            # Ensure server and account are configured
            $directoryUrl = Get-TestDirectoryUrl -BaseUrl $script:PkiBaseUrl
            Set-PAServer -DirectoryUrl $directoryUrl -SkipCertificateCheck

            $account = Get-PAAccount
            if (-not $account) {
                New-PAAccount -AcceptTOS -Force | Out-Null
            }
        }

        It "Can create order with New-PAOrder" {
            {
                $order = New-PAOrder -Domain $script:TestDomain -Force
                $order | Should -Not -BeNullOrEmpty
                $order.MainDomain | Should -Be $script:TestDomain
                $order.status | Should -BeIn @("pending", "ready")
            } | Should -Not -Throw
        }

        It "Order contains authorizations" {
            $order = New-PAOrder -Domain $script:TestDomain -Force
            $order.authorizations | Should -Not -BeNullOrEmpty
            $order.authorizations.Count | Should -BeGreaterThan 0
        }

        It "Can set active order with Set-PAOrder" {
            $order = New-PAOrder -Domain $script:TestDomain -Force
            {
                Set-PAOrder -MainDomain $script:TestDomain | Out-Null
            } | Should -Not -Throw
        }

        It "Can retrieve order with Get-PAOrder" {
            New-PAOrder -Domain $script:TestDomain -Force | Out-Null
            $order = Get-PAOrder -MainDomain $script:TestDomain
            $order | Should -Not -BeNullOrEmpty
            $order.MainDomain | Should -Be $script:TestDomain
        }
    }

    Context "Challenge Handling with Native Posh-ACME" {
        BeforeAll {
            # Ensure server and account are configured
            $directoryUrl = Get-TestDirectoryUrl -BaseUrl $script:PkiBaseUrl
            Set-PAServer -DirectoryUrl $directoryUrl -SkipCertificateCheck

            $account = Get-PAAccount
            if (-not $account) {
                New-PAAccount -AcceptTOS -Force | Out-Null
            }

            # Create fresh order
            $script:TestOrder = New-PAOrder -Domain $script:TestDomain -Force
            Set-PAOrder -MainDomain $script:TestDomain | Out-Null
        }

        It "Can retrieve authorizations with Get-PAAuthorization" {
            $auth = Get-PAAuthorization -AuthURLs $script:TestOrder.authorizations[0]
            $auth | Should -Not -BeNullOrEmpty
            $auth.identifier | Should -Not -BeNullOrEmpty
            $auth.challenges | Should -Not -BeNullOrEmpty
        }

        It "Authorization contains HTTP-01 challenge" {
            $auth = Get-PAAuthorization -AuthURLs $script:TestOrder.authorizations[0]
            $httpChallenge = $auth.challenges | Where-Object { $_.type -eq 'http-01' }
            $httpChallenge | Should -Not -BeNullOrEmpty
            $httpChallenge.token | Should -Not -BeNullOrEmpty
        }

        It "Can generate key authorization with Get-KeyAuthorization" {
            $auth = Get-PAAuthorization -AuthURLs $script:TestOrder.authorizations[0]
            $httpChallenge = $auth.challenges | Where-Object { $_.type -eq 'http-01' }

            $keyAuth = Get-KeyAuthorization -Token $httpChallenge.token
            $keyAuth | Should -Not -BeNullOrEmpty
            $keyAuth | Should -Match "^\S+\.\S+$"  # Format: token.thumbprint
        }

        It "Can publish challenge and send acknowledgement" {
            $auth = Get-PAAuthorization -AuthURLs $script:TestOrder.authorizations[0]
            $httpChallenge = $auth.challenges | Where-Object { $_.type -eq 'http-01' }

            # Publish challenge token
            $challengeRoot = "/challenge/.well-known/acme-challenge"
            New-Item -ItemType Directory -Path $challengeRoot -Force | Out-Null

            $keyAuth = Get-KeyAuthorization -Token $httpChallenge.token
            $tokenPath = Join-Path -Path $challengeRoot -ChildPath $httpChallenge.token

            {
                Write-FileAtomic -Path $tokenPath -Content $keyAuth
                Set-FilePermissions -Path $tokenPath -Mode "0644"
                Send-ChallengeAck -ChallengeUrl $httpChallenge.url | Out-Null
            } | Should -Not -Throw

            # Cleanup
            if (Test-Path $tokenPath) {
                Remove-Item $tokenPath -Force
            }
        }
    }

    Context "Order Finalization and Certificate Retrieval" {
        BeforeAll {
            # Ensure server and account are configured
            $directoryUrl = Get-TestDirectoryUrl -BaseUrl $script:PkiBaseUrl
            Set-PAServer -DirectoryUrl $directoryUrl -SkipCertificateCheck

            $account = Get-PAAccount
            if (-not $account) {
                New-PAAccount -AcceptTOS -Force | Out-Null
            }

            # Create and complete order
            $order = New-PAOrder -Domain $script:TestDomain -Force
            Set-PAOrder -MainDomain $script:TestDomain | Out-Null

            # Handle HTTP-01 challenge
            $challengeRoot = "/challenge/.well-known/acme-challenge"
            New-Item -ItemType Directory -Path $challengeRoot -Force | Out-Null

            foreach ($authUrl in $order.authorizations) {
                $auth = Get-PAAuthorization -AuthURLs $authUrl
                $httpChallenge = $auth.challenges | Where-Object { $_.type -eq 'http-01' }

                $keyAuth = Get-KeyAuthorization -Token $httpChallenge.token
                $tokenPath = Join-Path -Path $challengeRoot -ChildPath $httpChallenge.token
                Write-FileAtomic -Path $tokenPath -Content $keyAuth
                Set-FilePermissions -Path $tokenPath -Mode "0644"
                Send-ChallengeAck -ChallengeUrl $httpChallenge.url | Out-Null
            }

            # Wait for validation (increased timeout)
            $deadline = (Get-Date).AddSeconds(120)
            while ((Get-Date) -lt $deadline) {
                $currentOrder = Get-PAOrder -MainDomain $script:TestDomain -Refresh
                if ($currentOrder.status -in @('ready', 'valid')) {
                    break
                }
                Start-Sleep -Seconds 3
            }

            # Verify order reached ready/valid state
            $currentOrder = Get-PAOrder -MainDomain $script:TestDomain -Refresh
            if ($currentOrder.status -notin @('ready', 'valid')) {
                throw "Order validation timed out. Current status: $($currentOrder.status)"
            }

            # Finalize if ready
            $finalOrder = Get-PAOrder -MainDomain $script:TestDomain -Refresh
            if ($finalOrder.status -eq 'ready') {
                Submit-OrderFinalize | Out-Null

                # Wait for finalization (increased timeout and poll interval)
                $deadline = (Get-Date).AddSeconds(60)
                while ((Get-Date) -lt $deadline) {
                    Start-Sleep -Seconds 3
                    $finalOrder = Get-PAOrder -MainDomain $script:TestDomain -Refresh
                    if ($finalOrder.status -eq 'valid') {
                        break
                    }
                }
            }

            # Complete the order to get the certificate
            if ($finalOrder.status -eq 'valid') {
                Complete-PAOrder -Order $finalOrder | Out-Null
            }

            $script:FinalOrder = $finalOrder
        }

        It "Order status becomes valid after finalization" {
            $script:FinalOrder.status | Should -Be "valid"
        }

        It "Can complete order with Complete-PAOrder" {
            {
                $cert = Complete-PAOrder -Order $script:FinalOrder
                $cert | Should -Not -BeNullOrEmpty
            } | Should -Not -Throw
        }

        It "Certificate has correct properties" {
            $cert = Get-PACertificate
            $cert | Should -Not -BeNullOrEmpty
            $cert.Subject | Should -Match $script:TestDomain
            $cert.NotBefore | Should -Not -BeNullOrEmpty
            $cert.NotAfter | Should -Not -BeNullOrEmpty
        }

        It "Certificate files exist in Posh-ACME state" {
            $cert = Get-PACertificate
            Test-Path $cert.CertFile | Should -Be $true
            Test-Path $cert.KeyFile | Should -Be $true
            Test-Path $cert.FullChainFile | Should -Be $true
        }

        It "Certificate content is valid PEM" {
            $cert = Get-PACertificate
            $certContent = Get-Content $cert.CertFile -Raw
            $certContent | Should -Match "-----BEGIN CERTIFICATE-----"
            $certContent | Should -Match "-----END CERTIFICATE-----"
        }

        It "Full chain contains multiple certificates" {
            $cert = Get-PACertificate
            $fullChain = Get-Content $cert.FullChainFile -Raw
            $leafCert = Get-Content $cert.CertFile -Raw

            $fullChain.Length | Should -BeGreaterThan $leafCert.Length
        }

        It "Can save certificate to custom paths" {
            $cert = Get-PACertificate
            $customCertPath = Join-Path $script:TempDir "custom-cert.crt"
            $customKeyPath = Join-Path $script:TempDir "custom-key.key"

            {
                $certContent = Get-Content -LiteralPath $cert.CertFile -Raw
                $keyContent = Get-Content -LiteralPath $cert.KeyFile -Raw

                Write-FileAtomic -Path $customCertPath -Content $certContent
                Write-FileAtomic -Path $customKeyPath -Content $keyContent
            } | Should -Not -Throw

            Test-Path $customCertPath | Should -Be $true
            Test-Path $customKeyPath | Should -Be $true
        }
    }

    Context "Certificate Renewal" {
        It "Can force renewal of existing certificate" {
            # Get current certificate
            $oldCert = Get-PACertificate
            $oldCert | Should -Not -BeNullOrEmpty

            {
                # Create new order (force renewal)
                $newOrder = New-PAOrder -Domain $script:TestDomain -Force
                $newOrder | Should -Not -BeNullOrEmpty
            } | Should -Not -Throw
        }
    }

    Context "Error Handling" {
        It "Handles invalid directory URL gracefully" {
            {
                Set-PAServer -DirectoryUrl "https://invalid:9999/directory" -SkipCertificateCheck
            } | Should -Throw
        }

        It "Handles empty domain in order" {
            $directoryUrl = Get-TestDirectoryUrl -BaseUrl $script:PkiBaseUrl
            Set-PAServer -DirectoryUrl $directoryUrl -SkipCertificateCheck

            # Ensure account exists
            $account = Get-PAAccount
            if (-not $account) {
                New-PAAccount -AcceptTOS -Force | Out-Null
            }

            {
                # Try to create order with empty domain (should fail parameter validation)
                New-PAOrder -Domain "" -Force
            } | Should -Throw
        }
    }
}
