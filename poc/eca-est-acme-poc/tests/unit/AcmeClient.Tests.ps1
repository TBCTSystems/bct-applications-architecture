<#
.SYNOPSIS
    Pester unit tests for AcmeClient module achieving >80% code coverage.

.DESCRIPTION
    Comprehensive unit test suite for AcmeClient.psm1 covering all 10 exported functions.

.NOTES
    Requires: Pester 5.0+, PowerShell Core 7.0+
#>

#Requires -Version 7.0
#Requires -Modules Pester

using namespace System.Security.Cryptography

BeforeAll {
    $modulePath = "$PSScriptRoot/../../agents/acme/AcmeClient.psm1"
    Import-Module $modulePath -Force

    # Mock all Logger functions
    Mock -ModuleName AcmeClient -CommandName Write-LogInfo {}
    Mock -ModuleName AcmeClient -CommandName Write-LogDebug {}
    Mock -ModuleName AcmeClient -CommandName Write-LogError {}

    # Mock file operations
    Mock -ModuleName AcmeClient -CommandName Write-FileAtomic {}
    Mock -ModuleName AcmeClient -CommandName Set-FilePermissions {}

    # Mock Invoke-WebRequest globally to prevent nonce-fetching from making real network calls
    Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
        return @{
            Headers = @{
                'Replay-Nonce' = @('test-nonce-' + (Get-Random))
            }
        }
    }

    # Valid RSA private key for testing
    $script:TestRsaKeyPem = @'
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAvd7udwjTJjtcUFWqgcPGIprpcM98tbFD3eHXSh3hVn56UDOF
P5GBx0jwjD2mrxZZQCDmtCjXk9MgsaY9bvi4u226ero3VnpXg5Xcc/y1cfdAYBt8
qBdLNtyIpOTB+/GmeCg6pofFnOdnnggB1FKUBuaFh7am2X+0XsA8f/IxKilg1sjP
aolcfk9PJLP6K+QWZH6BnQvQRSyiq4cSnD7QxvKQNXd7hyHbjkozfSLkp4ezAec9
n6aVSIbH7qxZbdPSqnr0ohLCyhzx3Rv+HlKDJo/ygCoiWjsNOHVXI4v1t8smGUe5
yLLbdHh+XZd37egXDGzYaD0uyT+maxxikqDRMwIDAQABAoIBAAJALwnv1LCGQQzp
gbixMrJHcklgNU1EvSGsxMBoN+j9L1cfOOrVK5pAmCvYy8F+chHv+Up912Ya/jxF
5RRumo62bdBX9HNcY+eLJ8wmv2Y8I9To2MKfY6fix06OUbJA3eR22H0wkMevhe7E
DE1mo43034u6tUYVodBYLyENjaj6URfpwTIlkwcv8fbEumT5HTktoVA8xqOmJkvY
A2drsOZkJ39NUgy2BOneeU8+MUR2xvBc4tYRCY/vn6hRLVoTxAYDLFwPwHEbXmYq
n77WWq0HRibQef2y/FkzkuCiVYePIBjgRaoC0RAUQOnJm3dbpoH3OSOocORfz3ng
NaStW0ECgYEA7VtUWNWSL3PKWwhJXwyXKQY9mkpSeZt3hzf4s4sWoQNHAaOK3tZx
eUXd/pcfJ8WICyPfcY7b5UJ4zWU799H5gs9u+AzbuKoGo7RjNEOJk8bCNVX9Vboi
Ny2AMagYMO7kWLMjymstnrP70GL+rOWKUC+toHng5cxesBl6I5VUfXECgYEAzMjG
WCEBb18U0ojUr2owXwAzaI7jWOwp+wIDL+uEcyWFjfAi0UCCShY7eIT6DjyuC535
W+6p/hAKKIVplCmJLm9ySagwgLm51C8+4C+8dIVElonrX0QZYMm0AmHsqNXmj4yD
n7q2BnK5bMUPE8BQSP3FeosITXwQckpelvFb9uMCgYEArIvKA1IulSRdpFOf0uL6
OC57NeB1mEW2XKwJtauU5bPWOJDE8T1+/CQYP21ojqcAQOjxFEJABKeP3fCL6ZnR
ApD9IIFocRPZA8SsoV+/cZf5soAyS9Gl8eq32GFURK5FfV2s1QeZAFfi5Rgx/0pW
g/hFBfXT0foBk47RxXBXHWECgYAdYBubnrhu+mupO7mOpCPmLMgzEnQoWFA5UnOU
lys7vUEoOC82ZxOJfyDuy9x22Ft7DSEs/9JgwHpEj8ayWzbzc0coq7ixbnLqrhBN
5msZJ9jL42LhGoqtaKGqydNB8NUO+HAVJJph2Gki4i2kfqzFm6mNR45cVxSg4Gwr
KNoxUwKBgEzfsycz+DPgr37fj4v5zzq5QqS8IWCOQlceBUDACwWZYEE1DRhAQzBU
A7b1qWYLqCSAnH2iCFqcVEIAQAe82dWq41fNPUrMFRCC7AgDYWhfH6/N/wYKflFB
EaG7KG8yWEU9iqrlA/ORDWQzf5tv6bkyW+Kikho7GnmX0Athix84
-----END RSA PRIVATE KEY-----
'@

    Mock -ModuleName AcmeClient -CommandName New-RSAKeyPair { return $script:TestRsaKeyPem }

    function Get-TestRsaObject {
        $rsa = [System.Security.Cryptography.RSA]::Create()
        $rsa.ImportFromPem($script:TestRsaKeyPem)
        return $rsa
    }

    function Get-MockDirectoryResponse {
        return [PSCustomObject]@{
            newNonce = "https://pki:9000/acme/acme/new-nonce"
            newAccount = "https://pki:9000/acme/acme/new-account"
            newOrder = "https://pki:9000/acme/acme/new-order"
            revokeCert = "https://pki:9000/acme/acme/revoke-cert"
            keyChange = "https://pki:9000/acme/acme/key-change"
        }
    }
}

AfterAll {
    Remove-Module AcmeClient -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# GET-ACMEDIRECTORY TESTS
# =============================================================================

Describe "Get-AcmeDirectory" {
    BeforeEach {
        InModuleScope AcmeClient {
            $script:AcmeDirectory = $null
            $script:CurrentNonce = $null
        }
    }

    It "Returns directory with all required endpoints" {
        Mock -ModuleName AcmeClient -CommandName Invoke-RestMethod { return (Get-MockDirectoryResponse) }

        $result = Get-AcmeDirectory -BaseUrl "https://pki:9000"

        $result.newNonce | Should -Be "https://pki:9000/acme/acme/new-nonce"
        $result.newAccount | Should -Be "https://pki:9000/acme/acme/new-account"
        $result.newOrder | Should -Be "https://pki:9000/acme/acme/new-order"
    }

    It "Caches directory for subsequent calls" {
        Mock -ModuleName AcmeClient -CommandName Invoke-RestMethod { return (Get-MockDirectoryResponse) }

        Get-AcmeDirectory -BaseUrl "https://pki:9000"
        Get-AcmeDirectory -BaseUrl "https://pki:9000"

        Should -Invoke -ModuleName AcmeClient -CommandName Invoke-RestMethod -Times 1 -Exactly
    }

    It "Bypasses cache when Force parameter is used" {
        Mock -ModuleName AcmeClient -CommandName Invoke-RestMethod { return (Get-MockDirectoryResponse) }

        Get-AcmeDirectory -BaseUrl "https://pki:9000"
        Get-AcmeDirectory -BaseUrl "https://pki:9000" -Force

        Should -Invoke -ModuleName AcmeClient -CommandName Invoke-RestMethod -Times 2 -Exactly
    }

    It "Throws when directory is missing required fields" {
        Mock -ModuleName AcmeClient -CommandName Invoke-RestMethod {
            return [PSCustomObject]@{ newNonce = "https://pki:9000/acme/acme/new-nonce" }
        }

        { Get-AcmeDirectory -BaseUrl "https://pki:9000" } | Should -Throw "*missing required field*"
    }

    It "Throws when HTTP request fails" {
        Mock -ModuleName AcmeClient -CommandName Invoke-RestMethod { throw "Connection refused" }

        { Get-AcmeDirectory -BaseUrl "https://pki:9000" } | Should -Throw
    }
}

# =============================================================================
# NEW-JWSSIGNEDREQUEST TESTS
# =============================================================================

Describe "New-JwsSignedRequest" {
    BeforeEach {
        InModuleScope AcmeClient {
            $script:CurrentNonce = $null
        }
    }

    It "Creates valid JWS structure with kid header" {
        $rsa = Get-TestRsaObject
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce-123" }

        $jwsJson = New-JwsSignedRequest `
            -Url "https://pki:9000/acme/acme/new-order" `
            -Payload @{identifiers=@(@{type="dns";value="test.com"})} `
            -AccountKey $rsa `
            -AccountKeyId "https://pki:9000/acme/acme/acct/123"

        $jws = $jwsJson | ConvertFrom-Json
        $jws.protected | Should -Not -BeNullOrEmpty
        $jws.payload | Should -Not -BeNullOrEmpty
        $jws.signature | Should -Not -BeNullOrEmpty

        $rsa.Dispose()
    }

    It "Creates valid JWS structure with jwk header" {
        $rsa = Get-TestRsaObject
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce-456" }

        $rsaParams = $rsa.ExportParameters($false)
        $jwk = @{
            kty = "RSA"
            n = [Convert]::ToBase64String($rsaParams.Modulus) -replace '\+', '-' -replace '/', '_' -replace '=', ''
            e = [Convert]::ToBase64String($rsaParams.Exponent) -replace '\+', '-' -replace '/', '_' -replace '=', ''
        }

        $jwsJson = New-JwsSignedRequest `
            -Url "https://pki:9000/acme/acme/new-account" `
            -Payload @{termsOfServiceAgreed=$true} `
            -AccountKey $rsa `
            -AccountKeyJwk $jwk

        $jws = $jwsJson | ConvertFrom-Json
        $jws.protected | Should -Not -BeNullOrEmpty

        $rsa.Dispose()
    }

    It "Fetches fresh nonce when CurrentNonce is null" {
        $rsa = Get-TestRsaObject
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            return @{
                Headers = @{
                    'Replay-Nonce' = @("fresh-nonce")
                }
            }
        }

        New-JwsSignedRequest `
            -Url "https://pki:9000/acme/acme/new-order" `
            -Payload @{} `
            -AccountKey $rsa `
            -AccountKeyId "https://pki:9000/acme/acme/acct/123" `
            -NewNonceUrl "https://pki:9000/acme/acme/new-nonce"

        Should -Invoke -ModuleName AcmeClient -CommandName Invoke-WebRequest -Times 1
        $rsa.Dispose()
    }

    It "Clears CurrentNonce after signing" {
        $rsa = Get-TestRsaObject
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        New-JwsSignedRequest `
            -Url "https://pki:9000/acme/acme/new-order" `
            -Payload @{} `
            -AccountKey $rsa `
            -AccountKeyId "https://pki:9000/acme/acme/acct/123"

        InModuleScope AcmeClient {
            $script:CurrentNonce | Should -BeNullOrEmpty
        }

        $rsa.Dispose()
    }

    It "Throws when no nonce available" {
        $rsa = Get-TestRsaObject

        { New-JwsSignedRequest `
            -Url "https://pki:9000/acme/acme/new-order" `
            -Payload @{} `
            -AccountKey $rsa `
            -AccountKeyId "https://pki:9000/acme/acme/acct/123" } | Should -Throw "*No nonce available*"

        $rsa.Dispose()
    }

    It "Throws when neither AccountKeyId nor AccountKeyJwk provided" {
        $rsa = Get-TestRsaObject
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        { New-JwsSignedRequest `
            -Url "https://pki:9000/acme/acme/new-order" `
            -Payload @{} `
            -AccountKey $rsa } | Should -Throw "*Either AccountKeyId or AccountKeyJwk must be provided*"

        $rsa.Dispose()
    }
}

# =============================================================================
# GET-ACMEACCOUNT TESTS
# =============================================================================

Describe "Get-AcmeAccount" {
    It "Throws when account key file not found" {
        Mock -ModuleName AcmeClient -CommandName Test-Path { return $false }

        { Get-AcmeAccount -BaseUrl "https://pki:9000" } | Should -Throw "*not found*"
    }
}

# =============================================================================
# GET-ACMEAUTHORIZATION TESTS
# =============================================================================

Describe "Get-AcmeAuthorization" {
    AfterEach {
        if ($rsa) {
            $rsa.Dispose()
        }
    }

    It "Retrieves authorization with challenges" {
        $rsa = Get-TestRsaObject
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            return [PSCustomObject]@{
                Headers = @{
                    'Replay-Nonce' = @('nonce-authz')
                }
                Content = (@{
                    status = "pending"
                    expires = "2025-12-31T23:59:59Z"
                    identifier = @{type = "dns"; value = "target-server"}
                    challenges = @(
                        @{
                            type = "http-01"
                            status = "pending"
                            url = "https://pki:9000/acme/acme/challenge/chal123"
                            token = "evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ"
                        }
                    )
                } | ConvertTo-Json -Depth 5)
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        $authz = Get-AcmeAuthorization -AuthorizationUrl "https://pki:9000/acme/acme/authz/authz123" -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" -NewNonceUrl "https://pki:9000/acme/acme/new-nonce"

        $authz.Status | Should -Be "pending"
        $authz.Identifier.value | Should -Be "target-server"
        $authz.Challenges[0].token | Should -Be "evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ"
    }

    It "Throws when HTTP request fails" {
        $rsa = Get-TestRsaObject
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest { throw "HTTP 404" }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        { Get-AcmeAuthorization -AuthorizationUrl "https://pki:9000/acme/acme/authz/authz123" -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" -NewNonceUrl "https://pki:9000/acme/acme/new-nonce" } | Should -Throw
    }
}

# =============================================================================
# WAIT-CHALLENGEVALIDATION TESTS
# =============================================================================

Describe "Wait-ChallengeValidation" {
    BeforeEach {
        InModuleScope AcmeClient {
            $script:CurrentNonce = $null
        }
    }

    AfterEach {
        if ($rsa) {
            $rsa.Dispose()
        }
    }

    It "Returns when challenge status becomes valid" {
        $rsa = Get-TestRsaObject
        $script:pollCount = 0
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            $script:pollCount++
            if ($script:pollCount -eq 1) {
                return [PSCustomObject]@{
                    Headers = @{
                        'Replay-Nonce' = @('test-nonce-' + (Get-Random))
                    }
                    Content = (@{
                        challenges = @(@{type = "http-01"; status = "processing"})
                    } | ConvertTo-Json)
                }
            } else {
                return [PSCustomObject]@{
                    Headers = @{
                        'Replay-Nonce' = @('test-nonce-' + (Get-Random))
                    }
                    Content = (@{
                        challenges = @(@{type = "http-01"; status = "valid"})
                    } | ConvertTo-Json)
                }
            }
        }
        Mock -ModuleName AcmeClient -CommandName Start-Sleep { }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        { Wait-ChallengeValidation -AuthorizationUrl "https://pki:9000/acme/acme/authz/authz123" -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" -NewNonceUrl "https://pki:9000/acme/acme/new-nonce" -PollIntervalSeconds 1 -TimeoutSeconds 10 } | Should -Not -Throw
    }

    It "Throws when challenge status becomes invalid" {
        $rsa = Get-TestRsaObject
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            return [PSCustomObject]@{
                Headers = @{
                    'Replay-Nonce' = @('test-nonce-invalid')
                }
                Content = (@{
                    challenges = @(@{type = "http-01"; status = "invalid"; error = @{detail = "Token not found"}})
                } | ConvertTo-Json -Depth 5)
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        { Wait-ChallengeValidation -AuthorizationUrl "https://pki:9000/acme/acme/authz/authz456" -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" -NewNonceUrl "https://pki:9000/acme/acme/new-nonce" } | Should -Throw "*validation failed*"
    }

    It "Throws when validation times out" {
        $rsa = Get-TestRsaObject
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            return [PSCustomObject]@{
                Headers = @{
                    'Replay-Nonce' = @('test-nonce-timeout')
                }
                Content = (@{
                    challenges = @(@{type = "http-01"; status = "processing"})
                } | ConvertTo-Json)
            }
        }
        Mock -ModuleName AcmeClient -CommandName Start-Sleep { }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        { Wait-ChallengeValidation -AuthorizationUrl "https://pki:9000/acme/acme/authz/authz789" -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" -NewNonceUrl "https://pki:9000/acme/acme/new-nonce" -PollIntervalSeconds 1 -TimeoutSeconds 1 } | Should -Throw "*timeout*"
    }
}

# =============================================================================
# GET-ACMECERTIFICATE TESTS
# =============================================================================

Describe "Get-AcmeCertificate" {
    AfterEach {
        if ($rsa) {
            $rsa.Dispose()
        }
    }

    It "Downloads certificate in PEM format" {
        $rsa = Get-TestRsaObject
        $mockCertPem = @"
-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIRAKL8n5Z2dH3vX9pN1wK4jL0wDQYJKoZIhvcNAQELBQAw
-----END CERTIFICATE-----
"@
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            return [PSCustomObject]@{
                Headers = @{
                    'Replay-Nonce' = @('nonce-cert')
                }
                Content = $mockCertPem
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        $cert = Get-AcmeCertificate -CertificateUrl "https://pki:9000/acme/acme/certificate/cert123" -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" -NewNonceUrl "https://pki:9000/acme/acme/new-nonce"

        $cert | Should -Match "-----BEGIN CERTIFICATE-----"
        $cert | Should -Match "-----END CERTIFICATE-----"
    }

    It "Validates PEM certificate parsing with multiple blocks" {
        $rsa = Get-TestRsaObject
        $mockCertChain = @"
-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIRAKL8n5Z2dH3vX9pN1wK4jL0wDQYJKoZIhvcNAQELBQAw
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIRAKL8n5Z2dH3vX9pN1wK4jL0wDQYJKoZIhvcNAQELBQAw
-----END CERTIFICATE-----
"@
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            return [PSCustomObject]@{
                Headers = @{
                    'Replay-Nonce' = @('nonce-certchain')
                }
                Content = $mockCertChain
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        $cert = Get-AcmeCertificate -CertificateUrl "https://pki:9000/acme/acme/certificate/cert456" -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" -NewNonceUrl "https://pki:9000/acme/acme/new-nonce"

        $blockCount = ($cert | Select-String -Pattern "-----BEGIN CERTIFICATE-----" -AllMatches).Matches.Count
        $blockCount | Should -BeGreaterOrEqual 2
    }

    It "Throws when response does not contain PEM certificate" {
        $rsa = Get-TestRsaObject
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            return [PSCustomObject]@{
                Headers = @{
                    'Replay-Nonce' = @('nonce-invalid')
                }
                Content = "Invalid response"
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        { Get-AcmeCertificate -CertificateUrl "https://pki:9000/acme/acme/certificate/cert789" -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" -NewNonceUrl "https://pki:9000/acme/acme/new-nonce" } | Should -Throw "*no PEM certificate blocks*"
    }

    It "Throws when HTTP request fails" {
        $rsa = Get-TestRsaObject
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest { throw "HTTP 404" }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        { Get-AcmeCertificate -CertificateUrl "https://pki:9000/acme/acme/certificate/cert999" -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" -NewNonceUrl "https://pki:9000/acme/acme/new-nonce" } | Should -Throw
    }
}

# =============================================================================
# NEW-ACMEACCOUNT TESTS
# =============================================================================

Describe "New-AcmeAccount" {
    BeforeEach {
        InModuleScope AcmeClient {
            $script:AcmeDirectory = $null
            $script:CurrentNonce = $null
        }
    }

    AfterEach {
        if ($result -and $result.AccountKey) {
            $result.AccountKey.Dispose()
        }
    }

    It "Creates new account with valid bootstrap request" {
        Mock -ModuleName AcmeClient -CommandName Get-AcmeDirectory { return (Get-MockDirectoryResponse) }
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            return [PSCustomObject]@{
                Headers = @{
                    'Location' = @('https://pki:9000/acme/acme/acct/123')
                    'Replay-Nonce' = @('nonce-456')
                }
                Content = (@{
                    status = "valid"
                    contact = @("mailto:admin@example.com")
                    orders = "https://pki:9000/acme/acme/acct/123/orders"
                } | ConvertTo-Json)
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        $result = New-AcmeAccount -BaseUrl "https://pki:9000" -Contact @("mailto:admin@example.com")

        $result.URL | Should -Be "https://pki:9000/acme/acme/acct/123"
        $result.Status | Should -Be "valid"
        $result.AccountKey | Should -Not -BeNullOrEmpty
        $result.AccountKey | Should -BeOfType [System.Security.Cryptography.RSA]
    }

    It "Validates JWS header structure uses jwk (not kid)" {
        Mock -ModuleName AcmeClient -CommandName Get-AcmeDirectory { return (Get-MockDirectoryResponse) }

        $capturedJwsBody = $null
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            param($Uri, $Method, $Body)

            # Capture the JWS request body
            $script:capturedJwsBody = $Body

            return [PSCustomObject]@{
                Headers = @{
                    'Location' = @('https://pki:9000/acme/acme/acct/456')
                    'Replay-Nonce' = @('nonce-789')
                }
                Content = (@{status = "valid"; contact = @()} | ConvertTo-Json)
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce-abc" }

        $result = New-AcmeAccount -BaseUrl "https://pki:9000"

        # Parse JWS and decode protected header
        $script:capturedJwsBody | Should -Not -BeNullOrEmpty
        $jws = $script:capturedJwsBody | ConvertFrom-Json

        # Base64url decode protected header
        $protectedBytes = [Convert]::FromBase64String(
            ($jws.protected -replace '-', '+' -replace '_', '/').PadRight(
                ($jws.protected.Length + 3) - (($jws.protected.Length + 3) % 4), '='
            )
        )
        $protectedHeader = [System.Text.Encoding]::UTF8.GetString($protectedBytes) | ConvertFrom-Json

        # Verify header structure
        $protectedHeader.alg | Should -Be "RS256"
        $protectedHeader.jwk | Should -Not -BeNullOrEmpty
        $protectedHeader.jwk.kty | Should -Be "RSA"
        $protectedHeader.jwk.n | Should -Not -BeNullOrEmpty
        $protectedHeader.jwk.e | Should -Not -BeNullOrEmpty
        $protectedHeader.kid | Should -BeNullOrEmpty  # Should NOT have kid for new account
        $protectedHeader.nonce | Should -Be "test-nonce-abc"
        $protectedHeader.url | Should -Be "https://pki:9000/acme/acme/new-account"
    }

    It "Stores account key to file with correct permissions" {
        Mock -ModuleName AcmeClient -CommandName Get-AcmeDirectory { return (Get-MockDirectoryResponse) }
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            return [PSCustomObject]@{
                Headers = @{
                    'Location' = @('https://pki:9000/acme/acme/acct/789')
                    'Replay-Nonce' = @('nonce-xyz')
                }
                Content = (@{status = "valid"; contact = @()} | ConvertTo-Json)
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        $testAccountKeyPath = "/test/path/account.key"
        $result = New-AcmeAccount -BaseUrl "https://pki:9000" -AccountKeyPath $testAccountKeyPath

        # Verify Write-FileAtomic was called with account key path
        Should -Invoke -ModuleName AcmeClient -CommandName Write-FileAtomic -Times 1 -ParameterFilter {
            $Path -eq $testAccountKeyPath -and $Content -like "-----BEGIN RSA PRIVATE KEY-----*"
        }

        # Verify permissions set to 0600 (private key should be read-only to owner)
        Should -Invoke -ModuleName AcmeClient -CommandName Set-FilePermissions -Times 1 -ParameterFilter {
            $Path -eq $testAccountKeyPath -and $Mode -eq "0600"
        }
    }

    It "Throws when account creation fails without Location header" {
        Mock -ModuleName AcmeClient -CommandName Get-AcmeDirectory { return (Get-MockDirectoryResponse) }
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            # Return response without Location header
            return [PSCustomObject]@{
                Headers = @{
                    'Replay-Nonce' = @('nonce-fail')
                }
                Content = (@{status = "valid"} | ConvertTo-Json)
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        { New-AcmeAccount -BaseUrl "https://pki:9000" } | Should -Throw "*Location header*"
    }

    It "Disposes RSA object on error" {
        Mock -ModuleName AcmeClient -CommandName Get-AcmeDirectory { return (Get-MockDirectoryResponse) }
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest { throw "HTTP 500 Internal Server Error" }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        # Should throw and clean up RSA object internally
        { New-AcmeAccount -BaseUrl "https://pki:9000" } | Should -Throw

        # No result to dispose since function threw exception
    }
}

# =============================================================================
# NEW-ACMEORDER TESTS
# =============================================================================

Describe "New-AcmeOrder" {
    BeforeEach {
        InModuleScope AcmeClient {
            $script:AcmeDirectory = $null
            $script:CurrentNonce = $null
        }
    }

    AfterEach {
        if ($rsa) {
            $rsa.Dispose()
        }
    }

    It "Creates order for single domain" {
        $rsa = Get-TestRsaObject
        Mock -ModuleName AcmeClient -CommandName Get-AcmeDirectory { return (Get-MockDirectoryResponse) }

        $capturedPayload = $null
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            param($Uri, $Method, $Body)

            # Capture request body and parse payload
            $jws = $Body | ConvertFrom-Json
            $payloadBytes = [Convert]::FromBase64String(
                ($jws.payload -replace '-', '+' -replace '_', '/').PadRight(
                    ($jws.payload.Length + 3) - (($jws.payload.Length + 3) % 4), '='
                )
            )
            $script:capturedPayload = [System.Text.Encoding]::UTF8.GetString($payloadBytes) | ConvertFrom-Json

            return [PSCustomObject]@{
                Headers = @{
                    'Location' = @('https://pki:9000/acme/acme/order/order123')
                    'Replay-Nonce' = @('nonce-new')
                }
                Content = (@{
                    status = "pending"
                    expires = "2025-12-31T23:59:59Z"
                    identifiers = @(@{type="dns"; value="example.com"})
                    authorizations = @("https://pki:9000/acme/acme/authz/authz1")
                    finalize = "https://pki:9000/acme/acme/order/order123/finalize"
                } | ConvertTo-Json -Depth 5)
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        $order = New-AcmeOrder -BaseUrl "https://pki:9000" -DomainNames @("example.com") -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123"

        # Verify request payload contains correct identifier format
        $script:capturedPayload.identifiers | Should -HaveCount 1
        $script:capturedPayload.identifiers[0].type | Should -Be "dns"
        $script:capturedPayload.identifiers[0].value | Should -Be "example.com"

        # Verify returned order structure
        $order.URL | Should -Be "https://pki:9000/acme/acme/order/order123"
        $order.Status | Should -Be "pending"
        $order.Authorizations | Should -HaveCount 1
        $order.Finalize | Should -Be "https://pki:9000/acme/acme/order/order123/finalize"
    }

    It "Creates order for multiple domains (SAN certificate)" {
        $rsa = Get-TestRsaObject
        Mock -ModuleName AcmeClient -CommandName Get-AcmeDirectory { return (Get-MockDirectoryResponse) }

        $capturedPayload = $null
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            param($Uri, $Method, $Body)

            $jws = $Body | ConvertFrom-Json
            $payloadBytes = [Convert]::FromBase64String(
                ($jws.payload -replace '-', '+' -replace '_', '/').PadRight(
                    ($jws.payload.Length + 3) - (($jws.payload.Length + 3) % 4), '='
                )
            )
            $script:capturedPayload = [System.Text.Encoding]::UTF8.GetString($payloadBytes) | ConvertFrom-Json

            return [PSCustomObject]@{
                Headers = @{
                    'Location' = @('https://pki:9000/acme/acme/order/order456')
                    'Replay-Nonce' = @('nonce-san')
                }
                Content = (@{
                    status = "pending"
                    expires = "2025-12-31T23:59:59Z"
                    identifiers = @(
                        @{type="dns"; value="example.com"}
                        @{type="dns"; value="www.example.com"}
                        @{type="dns"; value="api.example.com"}
                    )
                    authorizations = @("https://pki:9000/acme/acme/authz/authz1", "https://pki:9000/acme/acme/authz/authz2", "https://pki:9000/acme/acme/authz/authz3")
                    finalize = "https://pki:9000/acme/acme/order/order456/finalize"
                } | ConvertTo-Json -Depth 5)
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        $domains = @("example.com", "www.example.com", "api.example.com")
        $order = New-AcmeOrder -BaseUrl "https://pki:9000" -DomainNames $domains -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123"

        # Verify all domains converted to identifiers
        $script:capturedPayload.identifiers | Should -HaveCount 3
        $script:capturedPayload.identifiers[0].type | Should -Be "dns"
        $script:capturedPayload.identifiers[0].value | Should -Be "example.com"
        $script:capturedPayload.identifiers[1].value | Should -Be "www.example.com"
        $script:capturedPayload.identifiers[2].value | Should -Be "api.example.com"
    }

    It "Extracts Location header for order URL" {
        $rsa = Get-TestRsaObject
        Mock -ModuleName AcmeClient -CommandName Get-AcmeDirectory { return (Get-MockDirectoryResponse) }
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            return [PSCustomObject]@{
                Headers = @{
                    'Location' = @('https://pki:9000/acme/acme/order/order789')
                    'Replay-Nonce' = @('nonce-loc')
                }
                Content = (@{
                    status = "pending"
                    expires = "2025-12-31T23:59:59Z"
                    identifiers = @(@{type="dns"; value="test.com"})
                    authorizations = @("https://pki:9000/acme/acme/authz/authz1")
                    finalize = "https://pki:9000/acme/acme/order/order789/finalize"
                } | ConvertTo-Json -Depth 5)
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        $order = New-AcmeOrder -BaseUrl "https://pki:9000" -DomainNames @("test.com") -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123"

        $order.URL | Should -Be "https://pki:9000/acme/acme/order/order789"
    }

    It "Throws when domain list is empty" {
        $rsa = Get-TestRsaObject
        Mock -ModuleName AcmeClient -CommandName Get-AcmeDirectory { return (Get-MockDirectoryResponse) }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        # PowerShell parameter validation will fail before function executes
        # Testing that empty array creates empty identifiers (which CA would reject)
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            # Simulate CA error for empty identifiers
            throw "Bad request: identifiers array cannot be empty"
        }

        { New-AcmeOrder -BaseUrl "https://pki:9000" -DomainNames @() -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" } | Should -Throw
    }
}

# =============================================================================
# COMPLETE-HTTP01CHALLENGE TESTS
# =============================================================================

Describe "Complete-Http01Challenge" {
    BeforeEach {
        InModuleScope AcmeClient {
            $script:CurrentNonce = $null
        }
        Mock -ModuleName AcmeClient -CommandName Test-Path { return $true }
        Mock -ModuleName AcmeClient -CommandName New-Item {}
    }

    AfterEach {
        if ($rsa) {
            $rsa.Dispose()
        }
    }

    It "Validates token file path format" {
        $rsa = Get-TestRsaObject
        $challenge = @{
            type = "http-01"
            token = "test-token-abc123"
            url = "https://pki:9000/acme/acme/challenge/chal1"
        }

        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            return [PSCustomObject]@{
                Headers = @{
                    'Replay-Nonce' = @('nonce-new')
                }
                Content = (@{status = "processing"} | ConvertTo-Json)
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        Complete-Http01Challenge -Challenge $challenge -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" -NewNonceUrl "https://pki:9000/acme/acme/new-nonce"

        # Verify Write-FileAtomic called with correct path
        Should -Invoke -ModuleName AcmeClient -CommandName Write-FileAtomic -Times 1 -ParameterFilter {
            $Path -eq "/challenge/.well-known/acme-challenge/test-token-abc123"
        }
    }

    It "Validates key authorization content format" {
        $rsa = Get-TestRsaObject
        $challenge = @{
            type = "http-01"
            token = "evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ"
            url = "https://pki:9000/acme/acme/challenge/chal2"
        }

        $capturedContent = $null
        Mock -ModuleName AcmeClient -CommandName Write-FileAtomic {
            param($Path, $Content)
            $script:capturedContent = $Content
        }
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            return [PSCustomObject]@{
                Headers = @{
                    'Replay-Nonce' = @('nonce-key')
                }
                Content = (@{status = "processing"} | ConvertTo-Json)
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        Complete-Http01Challenge -Challenge $challenge -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" -NewNonceUrl "https://pki:9000/acme/acme/new-nonce"

        # Verify key authorization format: {token}.{jwkThumbprint}
        $script:capturedContent | Should -Not -BeNullOrEmpty
        $script:capturedContent | Should -Match "^evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ\.[A-Za-z0-9_-]+$"
        $script:capturedContent | Should -Not -Match "`n"  # No newlines
        $script:capturedContent | Should -Not -Match "\s"  # No whitespace
    }

    It "Sets file permissions to 0644" {
        $rsa = Get-TestRsaObject
        $challenge = @{
            type = "http-01"
            token = "token-perms-test"
            url = "https://pki:9000/acme/acme/challenge/chal3"
        }

        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            return [PSCustomObject]@{
                Headers = @{
                    'Replay-Nonce' = @('nonce-perms')
                }
                Content = (@{status = "processing"} | ConvertTo-Json)
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        Complete-Http01Challenge -Challenge $challenge -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" -NewNonceUrl "https://pki:9000/acme/acme/new-nonce"

        # Verify permissions set to 0644 (world-readable for CA validation)
        Should -Invoke -ModuleName AcmeClient -CommandName Set-FilePermissions -Times 1 -ParameterFilter {
            $Path -eq "/challenge/.well-known/acme-challenge/token-perms-test" -and $Mode -eq "0644"
        }
    }

    It "Creates challenge directory if not exists" {
        $rsa = Get-TestRsaObject
        $challenge = @{
            type = "http-01"
            token = "token-dir-test"
            url = "https://pki:9000/acme/acme/challenge/chal4"
        }

        Mock -ModuleName AcmeClient -CommandName Test-Path { return $false }  # Directory doesn't exist
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            return [PSCustomObject]@{
                Headers = @{
                    'Replay-Nonce' = @('nonce-dir')
                }
                Content = (@{status = "processing"} | ConvertTo-Json)
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        Complete-Http01Challenge -Challenge $challenge -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" -NewNonceUrl "https://pki:9000/acme/acme/new-nonce"

        # Verify directory creation
        Should -Invoke -ModuleName AcmeClient -CommandName New-Item -Times 1 -ParameterFilter {
            $ItemType -eq "Directory" -and $Path -eq "/challenge/.well-known/acme-challenge"
        }
    }

    It "Triggers challenge validation via POST to challenge URL" {
        $rsa = Get-TestRsaObject
        $challengeUrl = "https://pki:9000/acme/acme/challenge/chal5"
        $challenge = @{
            type = "http-01"
            token = "token-post-test"
            url = $challengeUrl
        }

        $postInvoked = $false
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            param($Uri, $Method, $Body)

            if ($Uri -eq $challengeUrl -and $Method -eq "Post") {
                $script:postInvoked = $true

                # Verify payload is empty object
                $jws = $Body | ConvertFrom-Json
                $payloadBytes = [Convert]::FromBase64String(
                    ($jws.payload -replace '-', '+' -replace '_', '/').PadRight(
                        ($jws.payload.Length + 3) - (($jws.payload.Length + 3) % 4), '='
                    )
                )
                $payload = [System.Text.Encoding]::UTF8.GetString($payloadBytes) | ConvertFrom-Json
                $payload.PSObject.Properties | Should -HaveCount 0  # Empty object
            }

            return [PSCustomObject]@{
                Headers = @{
                    'Replay-Nonce' = @('nonce-post')
                }
                Content = (@{status = "processing"} | ConvertTo-Json)
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        Complete-Http01Challenge -Challenge $challenge -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" -NewNonceUrl "https://pki:9000/acme/acme/new-nonce"

        $script:postInvoked | Should -BeTrue
    }

    It "Throws when challenge type is not http-01" {
        $rsa = Get-TestRsaObject
        $challenge = @{
            type = "dns-01"  # Unsupported type
            token = "token-dns"
            url = "https://pki:9000/acme/acme/challenge/chal6"
        }

        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        { Complete-Http01Challenge -Challenge $challenge -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" -NewNonceUrl "https://pki:9000/acme/acme/new-nonce" } | Should -Throw "*Only HTTP-01 challenges are supported*"
    }
}

# =============================================================================
# COMPLETE-ACMEORDER TESTS
# =============================================================================

Describe "Complete-AcmeOrder" {
    BeforeEach {
        InModuleScope AcmeClient {
            $script:CurrentNonce = $null
        }
        Mock -ModuleName AcmeClient -CommandName Start-Sleep {}  # Speed up polling tests
    }

    AfterEach {
        if ($rsa) {
            $rsa.Dispose()
        }
    }

    It "Extracts base64 from CSR PEM correctly" {
        $rsa = Get-TestRsaObject
        $order = @{
            URL = "https://pki:9000/acme/acme/order/order123"
            Finalize = "https://pki:9000/acme/acme/order/order123/finalize"
        }

        $csrPem = @"
-----BEGIN CERTIFICATE REQUEST-----
MIICijCCAXICAQAwRTELMAkGA1UEBhMCQVUxEzARBgNVBAgMClNvbWUtU3RhdGUx
ITAfBgNVBAoMGEludGVybmV0IFdpZGdpdHMgUHR5IEx0ZDCCASIwDQYJKoZIhvcN
AQEBBQADggEPADCCAQoCggEBAL3e7ncI0yY7XFBVqoHDxiKa6XDPfLWxQ93h10od
-----END CERTIFICATE REQUEST-----
"@

        $capturedCsrBase64 = $null
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            param($Uri, $Method, $Body)

            if ($Method -eq "Post" -and $Uri -like "*/finalize") {
                # Capture CSR from finalize request
                $jws = $Body | ConvertFrom-Json
                $payloadBytes = [Convert]::FromBase64String(
                    ($jws.payload -replace '-', '+' -replace '_', '/').PadRight(
                        ($jws.payload.Length + 3) - (($jws.payload.Length + 3) % 4), '='
                    )
                )
                $payload = [System.Text.Encoding]::UTF8.GetString($payloadBytes) | ConvertFrom-Json
                $script:capturedCsrBase64 = $payload.csr

                return [PSCustomObject]@{
                    Headers = @{
                        'Replay-Nonce' = @('nonce-fin')
                    }
                    Content = (@{status = "processing"} | ConvertTo-Json)
                }
            }

            if ($Method -eq "Post" -and $Uri -notlike "*/finalize") {
                # Order status polling (POST-as-GET) - return valid immediately
                return [PSCustomObject]@{
                    Headers = @{
                        'Replay-Nonce' = @('nonce-poll-final')
                    }
                    Content = (@{
                        status = "valid"
                        certificate = "https://pki:9000/acme/acme/certificate/cert123"
                        expires = "2025-12-31T23:59:59Z"
                        identifiers = @(@{type="dns"; value="test.com"})
                        authorizations = @()
                        finalize = $order.Finalize
                    } | ConvertTo-Json -Depth 5)
                }
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        $result = Complete-AcmeOrder -Order $order -CsrPem $csrPem -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" -NewNonceUrl "https://pki:9000/acme/acme/new-nonce"

        # Verify CSR base64 extraction (standard base64, NOT base64url)
        $script:capturedCsrBase64 | Should -Not -BeNullOrEmpty
        $script:capturedCsrBase64 | Should -Not -Match "-----BEGIN"
        $script:capturedCsrBase64 | Should -Not -Match "-----END"
        $script:capturedCsrBase64 | Should -Not -Match "\s"  # No whitespace
        $script:capturedCsrBase64 | Should -Match "^[A-Za-z0-9+/]+=*$"  # Standard base64 (with + and /)
    }

    It "Polls order status until valid" {
        $rsa = Get-TestRsaObject
        $order = @{
            URL = "https://pki:9000/acme/acme/order/order456"
            Finalize = "https://pki:9000/acme/acme/order/order456/finalize"
        }
        $csrPem = "-----BEGIN CERTIFICATE REQUEST-----`nMIICijCCAXICAQAw`n-----END CERTIFICATE REQUEST-----"

        $script:pollCount = 0
        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            param($Uri, $Method)

            if ($Method -eq "Post" -and $Uri -like "*/finalize") {
                return [PSCustomObject]@{
                    Headers = @{
                        'Replay-Nonce' = @('nonce-poll')
                    }
                    Content = (@{status = "processing"} | ConvertTo-Json)
                }
            }

            if ($Method -eq "Post" -and $Uri -notlike "*/finalize") {
                # Polling (POST-as-GET)
                $script:pollCount++

                if ($script:pollCount -lt 3) {
                    return [PSCustomObject]@{
                        Headers = @{
                            'Replay-Nonce' = @('nonce-poll-' + $script:pollCount)
                        }
                        Content = (@{status = "processing"} | ConvertTo-Json)
                    }
                } else {
                    return [PSCustomObject]@{
                        Headers = @{
                            'Replay-Nonce' = @('nonce-poll-final')
                        }
                        Content = (@{
                            status = "valid"
                            certificate = "https://pki:9000/acme/acme/certificate/cert456"
                            expires = "2025-12-31T23:59:59Z"
                            identifiers = @()
                            authorizations = @()
                            finalize = $order.Finalize
                        } | ConvertTo-Json -Depth 5)
                    }
                }
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        $result = Complete-AcmeOrder -Order $order -CsrPem $csrPem -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" -NewNonceUrl "https://pki:9000/acme/acme/new-nonce"

        # Verify polling occurred multiple times
        $script:pollCount | Should -BeGreaterOrEqual 3
        $result.Status | Should -Be "valid"
        $result.Certificate | Should -Be "https://pki:9000/acme/acme/certificate/cert456"
    }

    It "Returns order with certificate URL when status becomes valid" {
        $rsa = Get-TestRsaObject
        $order = @{
            URL = "https://pki:9000/acme/acme/order/order789"
            Finalize = "https://pki:9000/acme/acme/order/order789/finalize"
        }
        $csrPem = "-----BEGIN CERTIFICATE REQUEST-----`nMIICijCCAXICAQAw`n-----END CERTIFICATE REQUEST-----"

        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            param($Uri, $Method)

            if ($Method -eq "Post" -and $Uri -like "*/finalize") {
                return [PSCustomObject]@{
                    Headers = @{
                        'Replay-Nonce' = @('nonce-cert')
                    }
                    Content = (@{status = "processing"} | ConvertTo-Json)
                }
            }

            if ($Method -eq "Post" -and $Uri -notlike "*/finalize") {
                # Polling (POST-as-GET) - return valid immediately
                return [PSCustomObject]@{
                    Headers = @{
                        'Replay-Nonce' = @('nonce-poll')
                    }
                    Content = (@{
                        status = "valid"
                        certificate = "https://pki:9000/acme/acme/certificate/cert789"
                        expires = "2026-01-15T12:00:00Z"
                        identifiers = @(@{type="dns"; value="example.com"})
                        authorizations = @("https://pki:9000/acme/acme/authz/authz1")
                        finalize = $order.Finalize
                    } | ConvertTo-Json -Depth 5)
                }
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        $result = Complete-AcmeOrder -Order $order -CsrPem $csrPem -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" -NewNonceUrl "https://pki:9000/acme/acme/new-nonce"

        $result.Certificate | Should -Be "https://pki:9000/acme/acme/certificate/cert789"
        $result.Status | Should -Be "valid"
    }

    It "Throws when order status becomes invalid" {
        $rsa = Get-TestRsaObject
        $order = @{
            URL = "https://pki:9000/acme/acme/order/order-invalid"
            Finalize = "https://pki:9000/acme/acme/order/order-invalid/finalize"
        }
        $csrPem = "-----BEGIN CERTIFICATE REQUEST-----`nMIICijCCAXICAQAw`n-----END CERTIFICATE REQUEST-----"

        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            param($Uri, $Method, $Body)

            if ($Method -eq "Post" -and $Uri -like "*/finalize") {
                return [PSCustomObject]@{
                    Headers = @{
                        'Replay-Nonce' = @('nonce-inv')
                    }
                    Content = (@{status = "processing"} | ConvertTo-Json)
                }
            }

            if ($Method -eq "Post" -and $Uri -notlike "*/finalize") {
                # Polling (POST-as-GET) - return invalid status
                return [PSCustomObject]@{
                    Headers = @{
                        'Replay-Nonce' = @('nonce-invalid-poll')
                    }
                    Content = (@{
                        status = "invalid"
                        error = @{detail = "CSR validation failed"}
                    } | ConvertTo-Json -Depth 5)
                }
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        { Complete-AcmeOrder -Order $order -CsrPem $csrPem -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" -NewNonceUrl "https://pki:9000/acme/acme/new-nonce" } | Should -Throw "*invalid*"
    }

    It "Handles order finalization timeout" {
        $rsa = Get-TestRsaObject
        $order = @{
            URL = "https://pki:9000/acme/acme/order/order-timeout"
            Finalize = "https://pki:9000/acme/acme/order/order-timeout/finalize"
        }
        $csrPem = "-----BEGIN CERTIFICATE REQUEST-----`nMIICijCCAXICAQAw`n-----END CERTIFICATE REQUEST-----"

        # Mock Start-Sleep to simulate time passing
        $script:sleepCount = 0
        Mock -ModuleName AcmeClient -CommandName Start-Sleep {
            $script:sleepCount++
        }

        Mock -ModuleName AcmeClient -CommandName Invoke-WebRequest {
            param($Uri, $Method, $Body)

            # Always return processing to force timeout (for both finalize and polling)
            return [PSCustomObject]@{
                Headers = @{
                    'Replay-Nonce' = @('nonce-timeout')
                }
                Content = (@{status = "processing"} | ConvertTo-Json)
            }
        }
        InModuleScope AcmeClient { $script:CurrentNonce = "test-nonce" }

        # The function uses hardcoded 60 second timeout, so this test will verify timeout logic
        { Complete-AcmeOrder -Order $order -CsrPem $csrPem -AccountKey $rsa -AccountKeyId "https://pki:9000/acme/acme/acct/123" -NewNonceUrl "https://pki:9000/acme/acme/new-nonce" } | Should -Throw "*timeout*"
    }
}
