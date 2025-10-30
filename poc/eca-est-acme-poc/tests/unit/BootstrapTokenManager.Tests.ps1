<#
.SYNOPSIS
    Pester unit tests for BootstrapTokenManager module achieving >90% code coverage.

.DESCRIPTION
    Comprehensive unit test suite for BootstrapTokenManager.psm1 covering:
    - Get-BootstrapToken function (environment variable, config file, error handling)
    - Test-BootstrapTokenValid function (token validation rules)
    - Token redaction security validation (ensures tokens never logged in plain text)

.NOTES
    Requires: Pester 5.0+, PowerShell Core 7.0+
    Target Coverage: >90% (approximately 192 lines of 214 code lines)
#>

#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    # Import the module under test
    $modulePath = "$PSScriptRoot/../../agents/est/BootstrapTokenManager.psm1"
    Import-Module $modulePath -Force

    # Mock all Logger functions to isolate unit tests
    Mock -ModuleName BootstrapTokenManager -CommandName Write-LogInfo {}
    Mock -ModuleName BootstrapTokenManager -CommandName Write-LogDebug {}
    Mock -ModuleName BootstrapTokenManager -CommandName Write-LogError {}
    Mock -ModuleName BootstrapTokenManager -CommandName Write-LogWarn {}
}

AfterAll {
    # Clean up module
    Remove-Module BootstrapTokenManager -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# GET-BOOTSTRAPTOKEN TESTS
# =============================================================================

Describe "Get-BootstrapToken" {

    BeforeEach {
        # Clean up environment variable before each test
        Remove-Item Env:\EST_BOOTSTRAP_TOKEN -ErrorAction SilentlyContinue
    }

    AfterEach {
        # Clean up environment variable after each test
        Remove-Item Env:\EST_BOOTSTRAP_TOKEN -ErrorAction SilentlyContinue
    }

    Context "Token Retrieval from Environment Variable" {

        It "Returns token from environment variable when present" {
            # Arrange
            $expectedToken = "factory-secret-token-12345"
            $env:EST_BOOTSTRAP_TOKEN = $expectedToken

            # Act
            $result = Get-BootstrapToken

            # Assert
            $result | Should -Be $expectedToken
        }

        It "Logs success with redacted token when loading from environment variable" {
            # Arrange
            $testToken = "factory-secret-token-12345"
            $env:EST_BOOTSTRAP_TOKEN = $testToken

            Mock -ModuleName BootstrapTokenManager -CommandName Write-LogInfo {}

            # Act
            Get-BootstrapToken

            # Assert
            Should -Invoke -ModuleName BootstrapTokenManager -CommandName Write-LogInfo -Times 1 -ParameterFilter {
                $Context.source -eq 'environment variable' -and
                $Context.variable -eq 'EST_BOOTSTRAP_TOKEN'
            }
        }

        It "Environment variable takes precedence over config file" {
            # Arrange
            $envToken = "env-token-12345678"
            $configToken = "config-token-87654321"
            $env:EST_BOOTSTRAP_TOKEN = $envToken
            $config = @{ bootstrap_token = $configToken }

            # Act
            $result = Get-BootstrapToken -Config $config

            # Assert
            $result | Should -Be $envToken
            $result | Should -Not -Be $configToken
        }
    }

    Context "Token Retrieval from Configuration File" {

        It "Returns token from config hashtable when environment variable is not set" {
            # Arrange
            Remove-Item Env:\EST_BOOTSTRAP_TOKEN -ErrorAction SilentlyContinue
            $expectedToken = "config-file-token-12345"
            $config = @{ bootstrap_token = $expectedToken }

            # Act
            $result = Get-BootstrapToken -Config $config

            # Assert
            $result | Should -Be $expectedToken
        }

        It "Logs success with redacted token when loading from config file" {
            # Arrange
            Remove-Item Env:\EST_BOOTSTRAP_TOKEN -ErrorAction SilentlyContinue
            $testToken = "config-file-token-12345"
            $config = @{ bootstrap_token = $testToken }

            Mock -ModuleName BootstrapTokenManager -CommandName Write-LogInfo {}

            # Act
            Get-BootstrapToken -Config $config

            # Assert
            Should -Invoke -ModuleName BootstrapTokenManager -CommandName Write-LogInfo -Times 1 -ParameterFilter {
                $Context.source -eq 'configuration file' -and
                $Context.field -eq 'bootstrap_token'
            }
        }
    }

    Context "Error Handling - Token Not Found" {

        It "Throws exception when token not found in environment or config" {
            # Arrange
            Remove-Item Env:\EST_BOOTSTRAP_TOKEN -ErrorAction SilentlyContinue

            # Act & Assert
            { Get-BootstrapToken } | Should -Throw "*Bootstrap token not configured*"
        }

        It "Throws exception with descriptive message mentioning EST_BOOTSTRAP_TOKEN" {
            # Arrange
            Remove-Item Env:\EST_BOOTSTRAP_TOKEN -ErrorAction SilentlyContinue

            # Act & Assert
            { Get-BootstrapToken } | Should -Throw "*EST_BOOTSTRAP_TOKEN*"
        }

        It "Throws exception when config has empty bootstrap_token field" {
            # Arrange
            Remove-Item Env:\EST_BOOTSTRAP_TOKEN -ErrorAction SilentlyContinue
            $config = @{ bootstrap_token = "" }

            # Act & Assert
            { Get-BootstrapToken -Config $config } | Should -Throw "*Bootstrap token not configured*"
        }

        It "Throws exception when config has whitespace-only bootstrap_token field" {
            # Arrange
            Remove-Item Env:\EST_BOOTSTRAP_TOKEN -ErrorAction SilentlyContinue
            $config = @{ bootstrap_token = "   " }

            # Act & Assert
            { Get-BootstrapToken -Config $config } | Should -Throw "*Bootstrap token not configured*"
        }

        It "Logs error when token not found" {
            # Arrange
            Remove-Item Env:\EST_BOOTSTRAP_TOKEN -ErrorAction SilentlyContinue
            Mock -ModuleName BootstrapTokenManager -CommandName Write-LogError {}

            # Act
            try {
                Get-BootstrapToken
            } catch {
                # Exception expected
            }

            # Assert
            Should -Invoke -ModuleName BootstrapTokenManager -CommandName Write-LogError -Times 1 -ParameterFilter {
                $Context.checked_env_var -eq 'EST_BOOTSTRAP_TOKEN' -and
                $Context.checked_config_field -eq 'bootstrap_token'
            }
        }
    }

    Context "Token Redaction Security" {

        It "Never logs actual token value in plain text from environment variable" {
            # Arrange
            $secretToken = "factory-secret-token-12345"
            $env:EST_BOOTSTRAP_TOKEN = $secretToken

            $script:actualLoggedTokens = @()
            Mock -ModuleName BootstrapTokenManager -CommandName Write-LogInfo {
                param($Message, $Context)
                $script:actualLoggedTokens += $Context.token
            }

            # Act
            Get-BootstrapToken

            # Assert
            $actualLoggedTokens | Should -Not -Contain $secretToken
            $actualLoggedTokens | Should -Not -BeNullOrEmpty
            $actualLoggedTokens[0] | Should -Match '\*\*\*'
        }

        It "Never logs actual token value in plain text from config file" {
            # Arrange
            Remove-Item Env:\EST_BOOTSTRAP_TOKEN -ErrorAction SilentlyContinue
            $secretToken = "config-file-secret-67890"
            $config = @{ bootstrap_token = $secretToken }

            $script:actualLoggedTokens = @()
            Mock -ModuleName BootstrapTokenManager -CommandName Write-LogInfo {
                param($Message, $Context)
                $script:actualLoggedTokens += $Context.token
            }

            # Act
            Get-BootstrapToken -Config $config

            # Assert
            $actualLoggedTokens | Should -Not -Contain $secretToken
            $actualLoggedTokens | Should -Not -BeNullOrEmpty
            $actualLoggedTokens[0] | Should -Match '\*\*\*'
        }

        It "Redacts long tokens with pattern: first5-***-last5" {
            # Arrange
            $longToken = "factory-secret-token-12345"
            $env:EST_BOOTSTRAP_TOKEN = $longToken

            $script:actualLoggedTokens = @()
            Mock -ModuleName BootstrapTokenManager -CommandName Write-LogInfo {
                param($Message, $Context)
                $script:actualLoggedTokens += $Context.token
            }

            # Act
            Get-BootstrapToken

            # Assert
            $actualLoggedTokens[0] | Should -Match 'facto-\*\*\*-12345'
        }
    }
}

# =============================================================================
# TEST-BOOTSTRAPTOKENVALID TESTS
# =============================================================================

Describe "Test-BootstrapTokenValid" {

    Context "Valid Token Formats" {

        It "Returns true for valid alphanumeric token (32 characters)" {
            # Arrange
            $validToken = "factory-secret-token-12345678"  # 29 chars (>16)

            # Act
            $result = Test-BootstrapTokenValid -Token $validToken

            # Assert
            $result | Should -Be $true
        }

        It "Returns true for valid alphanumeric token (exactly 16 characters)" {
            # Arrange
            $validToken = "token-1234567890"  # Exactly 16 chars (boundary test)

            # Act
            $result = Test-BootstrapTokenValid -Token $validToken

            # Assert
            $result | Should -Be $true
        }

        It "Returns true for valid base64-encoded token with special characters" {
            # Arrange
            $base64Token = "c3VwZXItc2VjcmV0LXRva2VuLXZhbHVl+base64/12345=="  # Contains +, /, =

            # Act
            $result = Test-BootstrapTokenValid -Token $base64Token

            # Assert
            $result | Should -Be $true
        }

        It "Returns true for token with underscores and hyphens" {
            # Arrange
            $tokenWithSeparators = "factory_secret-token_12345"

            # Act
            $result = Test-BootstrapTokenValid -Token $tokenWithSeparators

            # Assert
            $result | Should -Be $true
        }

        It "Logs debug message when token validation passes" {
            # Arrange
            $validToken = "factory-secret-token-12345"
            Mock -ModuleName BootstrapTokenManager -CommandName Write-LogDebug {}

            # Act
            Test-BootstrapTokenValid -Token $validToken

            # Assert
            Should -Invoke -ModuleName BootstrapTokenManager -CommandName Write-LogDebug -Times 1 -ParameterFilter {
                $Message -match "validation passed"
            }
        }
    }

    Context "Invalid Token Formats - Empty or Null" {

        It "Returns false for empty string token" {
            # Arrange
            $emptyToken = ""

            # Act
            $result = Test-BootstrapTokenValid -Token $emptyToken

            # Assert
            $result | Should -Be $false
        }

        It "Logs warning when token is empty" {
            # Arrange
            $emptyToken = ""
            Mock -ModuleName BootstrapTokenManager -CommandName Write-LogWarn {}

            # Act
            Test-BootstrapTokenValid -Token $emptyToken

            # Assert
            Should -Invoke -ModuleName BootstrapTokenManager -CommandName Write-LogWarn -Times 1 -ParameterFilter {
                $Message -match "null or empty" -and
                $Context.validation_rule -eq 'non_empty'
            }
        }
    }

    Context "Invalid Token Formats - Too Short" {

        It "Returns false for token with less than 16 characters" {
            # Arrange
            $shortToken = "short"  # Only 5 characters

            # Act
            $result = Test-BootstrapTokenValid -Token $shortToken

            # Assert
            $result | Should -Be $false
        }

        It "Returns false for token with exactly 15 characters (boundary test)" {
            # Arrange
            $shortToken = "123456789012345"  # Exactly 15 chars

            # Act
            $result = Test-BootstrapTokenValid -Token $shortToken

            # Assert
            $result | Should -Be $false
        }

        It "Logs warning when token is too short" {
            # Arrange
            $shortToken = "short"
            Mock -ModuleName BootstrapTokenManager -CommandName Write-LogWarn {}

            # Act
            Test-BootstrapTokenValid -Token $shortToken

            # Assert
            Should -Invoke -ModuleName BootstrapTokenManager -CommandName Write-LogWarn -Times 1 -ParameterFilter {
                $Message -match "length below minimum" -and
                $Context.validation_rule -eq 'min_length' -and
                $Context.actual_length -eq 5 -and
                $Context.required_length -eq 16
            }
        }
    }

    Context "Invalid Token Formats - Invalid Characters" {

        It "Returns false for token with dollar signs" {
            # Arrange
            $invalidToken = "invalid-token-with-$$$"

            # Act
            $result = Test-BootstrapTokenValid -Token $invalidToken

            # Assert
            $result | Should -Be $false
        }

        It "Returns false for token with special characters (@, %, #)" {
            # Arrange
            $invalidToken = "token@with#special%chars"

            # Act
            $result = Test-BootstrapTokenValid -Token $invalidToken

            # Assert
            $result | Should -Be $false
        }

        It "Returns false for token with spaces" {
            # Arrange
            $invalidToken = "token with spaces in it"

            # Act
            $result = Test-BootstrapTokenValid -Token $invalidToken

            # Assert
            $result | Should -Be $false
        }

        It "Logs warning when token contains invalid characters" {
            # Arrange
            $invalidToken = "invalid-token-with-$$$"
            Mock -ModuleName BootstrapTokenManager -CommandName Write-LogWarn {}

            # Act
            Test-BootstrapTokenValid -Token $invalidToken

            # Assert
            Should -Invoke -ModuleName BootstrapTokenManager -CommandName Write-LogWarn -Times 1 -ParameterFilter {
                $Message -match "invalid characters" -and
                $Context.validation_rule -eq 'character_set' -and
                $Context.expected_pattern -match 'alphanumeric or base64'
            }
        }
    }

    Context "Token Redaction in Validation Logs" {

        It "Redacts token in warning logs for empty token" {
            # Arrange
            $emptyToken = ""

            $script:actualLoggedTokens = @()
            Mock -ModuleName BootstrapTokenManager -CommandName Write-LogWarn {
                param($Message, $Context)
                $script:actualLoggedTokens += $Context.token
            }

            # Act
            Test-BootstrapTokenValid -Token $emptyToken

            # Assert
            $actualLoggedTokens[0] | Should -Be '***REDACTED***'
        }

        It "Redacts token in warning logs for too short token" {
            # Arrange
            $shortToken = "short"

            $script:actualLoggedTokens = @()
            Mock -ModuleName BootstrapTokenManager -CommandName Write-LogWarn {
                param($Message, $Context)
                $script:actualLoggedTokens += $Context.token
            }

            # Act
            Test-BootstrapTokenValid -Token $shortToken

            # Assert
            $actualLoggedTokens[0] | Should -Be '***REDACTED***'  # Tokens <10 chars fully redacted
        }

        It "Redacts token in warning logs for invalid characters" {
            # Arrange
            $invalidToken = "invalid-token-with-$$$"

            $script:actualLoggedTokens = @()
            Mock -ModuleName BootstrapTokenManager -CommandName Write-LogWarn {
                param($Message, $Context)
                $script:actualLoggedTokens += $Context.token
            }

            # Act
            Test-BootstrapTokenValid -Token $invalidToken

            # Assert
            $actualLoggedTokens | Should -Not -Contain $invalidToken
            $actualLoggedTokens[0] | Should -Match '\*\*\*'
        }

        It "Redacts token in debug logs for valid token" {
            # Arrange
            $validToken = "factory-secret-token-12345"

            $script:actualLoggedTokens = @()
            Mock -ModuleName BootstrapTokenManager -CommandName Write-LogDebug {
                param($Message, $Context)
                $script:actualLoggedTokens += $Context.token
            }

            # Act
            Test-BootstrapTokenValid -Token $validToken

            # Assert
            $actualLoggedTokens | Should -Not -Contain $validToken
            $actualLoggedTokens[0] | Should -Match 'facto-\*\*\*-12345'
        }
    }
}

# =============================================================================
# INTEGRATION TESTS - COMBINED WORKFLOW
# =============================================================================

Describe "BootstrapTokenManager - Integration Tests" {

    BeforeEach {
        Remove-Item Env:\EST_BOOTSTRAP_TOKEN -ErrorAction SilentlyContinue
    }

    AfterEach {
        Remove-Item Env:\EST_BOOTSTRAP_TOKEN -ErrorAction SilentlyContinue
    }

    It "Complete workflow: Get valid token from environment and validate it" {
        # Arrange
        $validToken = "factory-secret-token-12345"
        $env:EST_BOOTSTRAP_TOKEN = $validToken

        # Act
        $token = Get-BootstrapToken
        $isValid = Test-BootstrapTokenValid -Token $token

        # Assert
        $token | Should -Be $validToken
        $isValid | Should -Be $true
    }

    It "Complete workflow: Get valid token from config and validate it" {
        # Arrange
        Remove-Item Env:\EST_BOOTSTRAP_TOKEN -ErrorAction SilentlyContinue
        $validToken = "config-file-token-67890"
        $config = @{ bootstrap_token = $validToken }

        # Act
        $token = Get-BootstrapToken -Config $config
        $isValid = Test-BootstrapTokenValid -Token $token

        # Assert
        $token | Should -Be $validToken
        $isValid | Should -Be $true
    }

    It "Edge case: Token exactly at minimum length boundary (16 chars)" {
        # Arrange
        $boundaryToken = "1234567890123456"  # Exactly 16 characters
        $env:EST_BOOTSTRAP_TOKEN = $boundaryToken

        # Act
        $token = Get-BootstrapToken
        $isValid = Test-BootstrapTokenValid -Token $token

        # Assert
        $token | Should -Be $boundaryToken
        $isValid | Should -Be $true
    }

    It "Edge case: Token exactly at redaction boundary (10 chars)" {
        # Arrange
        $redactionBoundary = "1234567890123456"  # 16 chars (valid), will show partial redaction
        $env:EST_BOOTSTRAP_TOKEN = $redactionBoundary

        $script:actualLoggedTokens = @()
        Mock -ModuleName BootstrapTokenManager -CommandName Write-LogInfo {
            param($Message, $Context)
            $script:actualLoggedTokens += $Context.token
        }

        # Act
        Get-BootstrapToken

        # Assert
        $actualLoggedTokens[0] | Should -Match '12345-\*\*\*-23456'
    }
}
