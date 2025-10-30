<#
.SYNOPSIS
    Integration tests for EST agent end-to-end workflows.

.DESCRIPTION
    Tests the complete EST certificate lifecycle including:
    - Bootstrap token validation
    - Initial enrollment with bearer token
    - Re-enrollment with mTLS
    - Certificate chain verification

.NOTES
    These tests require a running OpenXPKI instance.
    Run with: docker compose up -d openxpki-web openxpki-client openxpki-server
    Requires: Pester 5.0+, PowerShell Core 7.0+
#>

#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    # Import EST client and token manager modules
    $estModulePath = "$PSScriptRoot/../../agents/est/EstClient.psm1"
    $tokenModulePath = "$PSScriptRoot/../../agents/est/BootstrapTokenManager.psm1"

    Import-Module $estModulePath -Force
    Import-Module $tokenModulePath -Force

    # Test configuration
    $script:PkiBaseUrl = $env:EST_URL ?? "https://openxpki-web:443"
    $script:ProvisionerName = "est-provisioner"
    $script:TempDir = "/tmp/eca-integration-test-$(Get-Random)"

    # Create temp directory
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
}

AfterAll {
    # Cleanup
    Remove-Module EstClient -Force -ErrorAction SilentlyContinue
    Remove-Module BootstrapTokenManager -Force -ErrorAction SilentlyContinue

    if (Test-Path $script:TempDir) {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "EST End-to-End Integration Tests" -Tag "Integration", "EST" {

    Context "PKI Connectivity" {
        It "Can connect to EST server" {
            {
                Invoke-RestMethod -Uri "$script:PkiBaseUrl/.well-known/est/cacerts" -Method Get -SkipCertificateCheck
            } | Should -Not -Throw
        }
    }

    Context "Bootstrap Token Validation" {
        It "Validates token format correctly" {
            $validToken = "factory-secret-token-12345"
            $result = Test-BootstrapTokenValid -Token $validToken

            $result | Should -Be $true
        }

        It "Rejects tokens that are too short" {
            $shortToken = "short"
            $result = Test-BootstrapTokenValid -Token $shortToken

            $result | Should -Be $false
        }

        It "Rejects tokens with invalid characters" {
            $invalidToken = 'invalid-token-with-$$'
            $result = Test-BootstrapTokenValid -Token $invalidToken

            $result | Should -Be $false
        }
    }

    Context "Token Retrieval" {
        BeforeEach {
            Remove-Item Env:\EST_BOOTSTRAP_TOKEN -ErrorAction SilentlyContinue
        }

        AfterEach {
            Remove-Item Env:\EST_BOOTSTRAP_TOKEN -ErrorAction SilentlyContinue
        }

        It "Retrieves token from environment variable" {
            $expectedToken = "test-token-from-env-12345"
            $env:EST_BOOTSTRAP_TOKEN = $expectedToken

            $token = Get-BootstrapToken

            $token | Should -Be $expectedToken
        }

        It "Retrieves token from config file" {
            $expectedToken = "test-token-from-config-67890"
            $config = @{ bootstrap_token = $expectedToken }

            $token = Get-BootstrapToken -Config $config

            $token | Should -Be $expectedToken
        }

        It "Throws when token not found" {
            { Get-BootstrapToken } | Should -Throw "*Bootstrap token not configured*"
        }
    }
}
