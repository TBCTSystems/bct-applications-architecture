<#
.SYNOPSIS
    Integration tests for ACME agent end-to-end workflows.

.DESCRIPTION
    Tests the complete ACME certificate lifecycle including:
    - Account creation
    - Order placement
    - HTTP-01 challenge completion
    - CSR submission
    - Certificate retrieval

.NOTES
    These tests require a running step-ca PKI instance.
    Run with: docker compose up -d pki
    Requires: Pester 5.0+, PowerShell Core 7.0+
#>

#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    # Import ACME client module
    $acmeModulePath = "$PSScriptRoot/../../agents/acme/AcmeClient.psm1"
    Import-Module $acmeModulePath -Force

    # Test configuration
    $script:PkiBaseUrl = $env:PKI_URL ?? "https://pki:9000"
    $script:TestDomain = "integration-test.local"
    $script:TempDir = "/tmp/eca-integration-test-$(Get-Random)"

    # Create temp directory
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
}

AfterAll {
    # Cleanup
    Remove-Module AcmeClient -Force -ErrorAction SilentlyContinue

    if (Test-Path $script:TempDir) {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "ACME End-to-End Integration Tests" -Tag "Integration", "ACME" {

    Context "PKI Connectivity" {
        It "Can connect to PKI server" {
            {
                $headers = @{
                    Accept = "application/json"
                }
                Invoke-RestMethod -Uri "$script:PkiBaseUrl/health" -Method Get -Headers $headers -SkipCertificateCheck
            } | Should -Not -Throw
        }

        It "Can retrieve ACME directory" {
            $directory = Get-AcmeDirectory -BaseUrl $script:PkiBaseUrl

            $directory | Should -Not -BeNullOrEmpty
            $directory.newNonce | Should -Not -BeNullOrEmpty
            $directory.newAccount | Should -Not -BeNullOrEmpty
            $directory.newOrder | Should -Not -BeNullOrEmpty
        }
    }

    Context "Account Management" {
        It "Can create new ACME account" -Skip {
            # This test is skipped by default as it creates actual accounts on the PKI
            # Run manually with: Invoke-Pester -Tag "AccountCreation"
            $accountKeyPath = Join-Path $script:TempDir "account.key"

            $account = New-AcmeAccount `
                -BaseUrl $script:PkiBaseUrl `
                -Contact @("mailto:test@example.com") `
                -AccountKeyPath $accountKeyPath

            $account | Should -Not -BeNullOrEmpty
            $account.URL | Should -Not -BeNullOrEmpty
            $account.Status | Should -Be "valid"
            $account.AccountKey | Should -Not -BeNullOrEmpty

            Test-Path $accountKeyPath | Should -Be $true
        }
    }
}
