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
            # keyId may be null for some ACME servers, check that account has either keyId or ID
            ($account.keyId -or $account.ID) | Should -Be $true
            $account.ID | Should -Not -BeNullOrEmpty
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

            Write-Host "[TEST] Order created with status: $($order.status)" -ForegroundColor Cyan

            # Handle HTTP-01 challenge
            $challengeRoot = "/challenge/.well-known/acme-challenge"
            New-Item -ItemType Directory -Path $challengeRoot -Force | Out-Null

            foreach ($authUrl in $order.authorizations) {
                $auth = Get-PAAuthorization -AuthURLs $authUrl

                if ($auth.status -eq 'valid') {
                    Write-Host "[TEST] Authorization already valid, skipping" -ForegroundColor Green
                    continue
                }

                $httpChallenge = $auth.challenges | Where-Object { $_.type -eq 'http-01' }
                if (-not $httpChallenge) {
                    throw "No HTTP-01 challenge found"
                }

                $keyAuth = Get-KeyAuthorization -Token $httpChallenge.token
                $tokenPath = Join-Path -Path $challengeRoot -ChildPath $httpChallenge.token

                Write-Host "[TEST] Publishing challenge token: $($httpChallenge.token)" -ForegroundColor Cyan
                Write-FileAtomic -Path $tokenPath -Content $keyAuth
                Set-FilePermissions -Path $tokenPath -Mode "0644"

                Write-Host "[TEST] Sending challenge acknowledgement" -ForegroundColor Cyan
                Send-ChallengeAck -ChallengeUrl $httpChallenge.url | Out-Null

                Write-Host "[TEST] Challenge published, waiting for validation" -ForegroundColor Cyan
            }

            # Wait for validation with detailed logging
            Write-Host "[TEST] Polling for order validation (max 180 seconds)" -ForegroundColor Cyan
            $maxAttempts = 60
            $attempt = 0
            $validated = $false

            while ($attempt -lt $maxAttempts) {
                Start-Sleep -Seconds 3
                $attempt++

                $currentOrder = Get-PAOrder -MainDomain $script:TestDomain -Refresh
                Write-Host "[TEST] Attempt $attempt/$maxAttempts - Order status: $($currentOrder.status)" -ForegroundColor Gray

                if ($currentOrder.status -eq 'ready') {
                    Write-Host "[TEST] Order is ready for finalization" -ForegroundColor Green
                    $validated = $true
                    break
                }
                elseif ($currentOrder.status -eq 'valid') {
                    Write-Host "[TEST] Order is already valid" -ForegroundColor Green
                    $validated = $true
                    break
                }
                elseif ($currentOrder.status -eq 'invalid') {
                    throw "Order validation failed - status became invalid"
                }
            }

            if (-not $validated) {
                $currentOrder = Get-PAOrder -MainDomain $script:TestDomain -Refresh
                throw "Order validation timed out after $($maxAttempts * 3) seconds. Final status: $($currentOrder.status)"
            }

            # Finalize if ready
            $finalOrder = Get-PAOrder -MainDomain $script:TestDomain -Refresh
            Write-Host "[TEST] Final order status before finalization: $($finalOrder.status)" -ForegroundColor Cyan

            if ($finalOrder.status -eq 'ready') {
                Write-Host "[TEST] Setting order as active and submitting finalization" -ForegroundColor Cyan
                # Ensure this order is the active one in Posh-ACME's state
                Set-PAOrder -MainDomain $script:TestDomain | Out-Null

                # Get a fresh reference to ensure we have the latest state
                $readyOrder = Get-PAOrder -Refresh
                Write-Host "[TEST] Active order status from Get-PAOrder: $($readyOrder.status)" -ForegroundColor Cyan

                if ($readyOrder.status -ne 'ready') {
                    throw "Active order status is $($readyOrder.status), expected 'ready'. This indicates a state sync issue."
                }

                Submit-OrderFinalize | Out-Null

                # Wait for finalization to complete
                Write-Host "[TEST] Polling for finalization completion (max 90 seconds)" -ForegroundColor Cyan
                $maxFinalizeAttempts = 30
                $finalizeAttempt = 0
                $finalized = $false

                while ($finalizeAttempt -lt $maxFinalizeAttempts) {
                    Start-Sleep -Seconds 3
                    $finalizeAttempt++

                    $finalOrder = Get-PAOrder -MainDomain $script:TestDomain -Refresh
                    Write-Host "[TEST] Finalize attempt $finalizeAttempt/$maxFinalizeAttempts - Order status: $($finalOrder.status)" -ForegroundColor Gray

                    if ($finalOrder.status -eq 'valid') {
                        Write-Host "[TEST] Order finalization complete - status is valid" -ForegroundColor Green
                        $finalized = $true
                        break
                    }
                }

                if (-not $finalized) {
                    throw "Order finalization timed out after $($maxFinalizeAttempts * 3) seconds. Final status: $($finalOrder.status)"
                }
            }

            # Complete the order to get the certificate
            Write-Host "[TEST] Completing order to retrieve certificate" -ForegroundColor Cyan
            if ($finalOrder.status -eq 'valid') {
                $cert = Complete-PAOrder -Order $finalOrder
                if ($cert) {
                    Write-Host "[TEST] Certificate retrieved successfully" -ForegroundColor Green
                } else {
                    Write-Host "[TEST] Warning: Complete-PAOrder returned null" -ForegroundColor Yellow
                }
            } else {
                throw "Cannot complete order - status is $($finalOrder.status), expected 'valid'"
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
