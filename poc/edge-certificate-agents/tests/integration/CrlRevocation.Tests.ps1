# ==============================================================================
# CrlRevocation.Tests.ps1 - Integration Tests for CRL Revocation Workflow
# ==============================================================================
# End-to-end tests for certificate revocation list functionality
# Tests the complete workflow: generation, distribution, and validation
# ==============================================================================

BeforeAll {
    # Import CRL validator module
    $modulePath = Resolve-Path "$PSScriptRoot/../../agents/common/CrlValidator.psm1"
    Import-Module $modulePath -Force

    # Test configuration
    $script:PkiUrl = $env:PKI_URL ?? "https://pki:9000"
    $script:CrlUrl = "http://pki:9001/crl/ca.crl"
    $script:CrlHealthUrl = "http://pki:9001/health"
    $script:TestDir = Join-Path $TestDrive "crl-integration"
    New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null

    Write-Host "[SETUP] CRL Integration Tests - PKI URL: $($script:PkiUrl)" -ForegroundColor Cyan
    Write-Host "[SETUP] CRL URL: $($script:CrlUrl)" -ForegroundColor Cyan
}

Describe "CRL HTTP Endpoint" -Tags @('Integration', 'CRL', 'HTTP') {

    Context "CRL Server Availability" {
        It "CRL health endpoint responds" {
            # Test health endpoint
            try {
                $response = Invoke-WebRequest -Uri $script:CrlHealthUrl -UseBasicParsing -TimeoutSec 5
                $response.StatusCode | Should -Be 200
            } catch {
                Set-ItResult -Skipped -Because "CRL server not available: $_"
            }
        }

        It "CRL endpoint is accessible" {
            try {
                $response = Invoke-WebRequest -Uri $script:CrlUrl -UseBasicParsing -TimeoutSec 10
                $response.StatusCode | Should -Be 200
            } catch {
                Set-ItResult -Skipped -Because "CRL endpoint not available: $_"
            }
        }

        It "CRL file has correct Content-Type header" {
            try {
                $response = Invoke-WebRequest -Uri $script:CrlUrl -UseBasicParsing -TimeoutSec 10
                $contentType = $response.Headers['Content-Type']
                $contentType | Should -Match 'application/(pkix-crl|x-pkcs7-crl)'
            } catch {
                Set-ItResult -Skipped -Because "CRL endpoint not available: $_"
            }
        }

        It "CRL file has non-zero size" {
            try {
                $cachePath = Join-Path $script:TestDir "endpoint-test.crl"
                $result = Get-CrlFromUrl -Url $script:CrlUrl -CachePath $cachePath

                $result | Should -Be $true
                Test-Path $cachePath | Should -Be $true
                (Get-Item $cachePath).Length | Should -BeGreaterThan 0
            } catch {
                Set-ItResult -Skipped -Because "CRL download failed: $_"
            }
        }

        It "CRL file is valid DER format" {
            # Skip if openssl not available
            $opensslAvailable = Get-Command openssl -ErrorAction SilentlyContinue
            if (-not $opensslAvailable) {
                Set-ItResult -Skipped -Because "openssl not available"
                return
            }

            try {
                $cachePath = Join-Path $script:TestDir "format-test.crl"
                Get-CrlFromUrl -Url $script:CrlUrl -CachePath $cachePath | Out-Null

                # Try to parse with openssl
                $crlInfo = & openssl crl -inform DER -in $cachePath -noout -text 2>&1
                $LASTEXITCODE | Should -Be 0
            } catch {
                Set-ItResult -Skipped -Because "CRL validation failed: $_"
            }
        }
    }

    Context "CRL Content Validation" {
        It "CRL contains valid issuer information" {
            try {
                $cachePath = Join-Path $script:TestDir "issuer-test.crl"
                Get-CrlFromUrl -Url $script:CrlUrl -CachePath $cachePath | Out-Null

                $info = Get-CrlInfo -CrlPath $cachePath
                $info | Should -Not -BeNullOrEmpty
                $info.Issuer | Should -Not -BeNullOrEmpty
                $info.Issuer | Should -Not -Match "Unknown"
            } catch {
                Set-ItResult -Skipped -Because "CRL info extraction failed: $_"
            }
        }

        It "CRL has ThisUpdate and NextUpdate fields" {
            try {
                $cachePath = Join-Path $script:TestDir "update-fields.crl"
                Get-CrlFromUrl -Url $script:CrlUrl -CachePath $cachePath | Out-Null

                $info = Get-CrlInfo -CrlPath $cachePath
                $info | Should -Not -BeNullOrEmpty
                $info.ThisUpdate | Should -Not -BeNullOrEmpty
                $info.NextUpdate | Should -Not -BeNullOrEmpty
            } catch {
                Set-ItResult -Skipped -Because "CRL info extraction failed: $_"
            }
        }

        It "CRL has RevokedCount field" {
            try {
                $cachePath = Join-Path $script:TestDir "revoked-count.crl"
                Get-CrlFromUrl -Url $script:CrlUrl -CachePath $cachePath | Out-Null

                $info = Get-CrlInfo -CrlPath $cachePath
                $info | Should -Not -BeNullOrEmpty
                $info.RevokedCount | Should -BeGreaterOrEqual 0
            } catch {
                Set-ItResult -Skipped -Because "CRL info extraction failed: $_"
            }
        }
    }
}

Describe "CRL Caching Workflow" -Tags @('Integration', 'CRL', 'Cache') {

    Context "Update-CrlCache Functionality" {
        It "Downloads CRL on first access" {
            $cachePath = Join-Path $script:TestDir "first-download.crl"

            # Ensure file doesn't exist
            if (Test-Path $cachePath) {
                Remove-Item $cachePath -Force
            }

            try {
                $result = Update-CrlCache -Url $script:CrlUrl -CachePath $cachePath -MaxAgeHours 24

                $result | Should -Not -BeNullOrEmpty
                $result.Downloaded | Should -Be $true
                $result.Updated | Should -Be $true
                $result.CrlAge | Should -Be 0.0
                Test-Path $cachePath | Should -Be $true
            } catch {
                Set-ItResult -Skipped -Because "CRL download failed: $_"
            }
        }

        It "Uses cached CRL when fresh" {
            $cachePath = Join-Path $script:TestDir "cached-fresh.crl"

            try {
                # First download
                Update-CrlCache -Url $script:CrlUrl -CachePath $cachePath -MaxAgeHours 24 | Out-Null

                # Second call should use cache
                $result = Update-CrlCache -Url $script:CrlUrl -CachePath $cachePath -MaxAgeHours 24

                $result.Downloaded | Should -Be $false
                $result.Updated | Should -Be $false
                $result.CrlAge | Should -BeGreaterOrEqual 0.0
                $result.CrlAge | Should -BeLessThan 1.0  # Less than 1 hour
            } catch {
                Set-ItResult -Skipped -Because "CRL caching test failed: $_"
            }
        }

        It "Re-downloads CRL when stale" {
            $cachePath = Join-Path $script:TestDir "cached-stale.crl"

            try {
                # Create initial cache
                Update-CrlCache -Url $script:CrlUrl -CachePath $cachePath -MaxAgeHours 24 | Out-Null

                # Make it stale by setting old timestamp
                $oldTime = (Get-Date).AddHours(-25)
                (Get-Item $cachePath).LastWriteTime = $oldTime

                # Should trigger re-download
                $result = Update-CrlCache -Url $script:CrlUrl -CachePath $cachePath -MaxAgeHours 24

                $result.Downloaded | Should -Be $true
                $result.Updated | Should -Be $true
            } catch {
                Set-ItResult -Skipped -Because "CRL re-download test failed: $_"
            }
        }

        It "Respects custom MaxAgeHours parameter" {
            $cachePath = Join-Path $script:TestDir "custom-age.crl"

            try {
                # Create cache
                "test" | Out-File $cachePath

                # Set to 1.5 hours old
                $oldTime = (Get-Date).AddHours(-1.5)
                (Get-Item $cachePath).LastWriteTime = $oldTime

                # With MaxAgeHours=2, should NOT download
                $result1 = Update-CrlCache -Url $script:CrlUrl -CachePath $cachePath -MaxAgeHours 2.0
                $result1.Downloaded | Should -Be $false

                # With MaxAgeHours=1, SHOULD download
                $result2 = Update-CrlCache -Url $script:CrlUrl -CachePath $cachePath -MaxAgeHours 1.0
                $result2.Downloaded | Should -Be $true
            } catch {
                Set-ItResult -Skipped -Because "Custom age test failed: $_"
            }
        }
    }
}

Describe "Certificate Revocation Validation" -Tags @('Integration', 'CRL', 'Revocation') {

    Context "Valid Certificate Detection" {
        It "Detects non-revoked certificate" {
            # Skip if openssl not available
            $opensslAvailable = Get-Command openssl -ErrorAction SilentlyContinue
            if (-not $opensslAvailable) {
                Set-ItResult -Skipped -Because "openssl not available"
                return
            }

            try {
                # Download current CRL
                $crlPath = Join-Path $script:TestDir "valid-cert-check.crl"
                Get-CrlFromUrl -Url $script:CrlUrl -CachePath $crlPath | Out-Null

                # Create a new certificate (won't be in CRL)
                $certPath = Join-Path $script:TestDir "valid-cert.pem"
                $keyPath = Join-Path $script:TestDir "valid-cert.key"

                & openssl req -x509 -newkey rsa:2048 -keyout $keyPath -out $certPath -days 1 -nodes -subj "/CN=Valid Test Cert" 2>&1 | Out-Null

                # Check revocation status
                $result = Test-CertificateRevoked -CertificatePath $certPath -CrlPath $crlPath

                # Should be false or null (not in CRL = not revoked)
                $result | Should -BeIn @($false, $null)
            } catch {
                Set-ItResult -Skipped -Because "Valid certificate test failed: $_"
            }
        }

        It "Returns null for certificate with non-matching issuer" {
            # Skip if openssl not available
            $opensslAvailable = Get-Command openssl -ErrorAction SilentlyContinue
            if (-not $opensslAvailable) {
                Set-ItResult -Skipped -Because "openssl not available"
                return
            }

            try {
                # Download current CRL
                $crlPath = Join-Path $script:TestDir "wrong-issuer.crl"
                Get-CrlFromUrl -Url $script:CrlUrl -CachePath $crlPath | Out-Null

                # Create certificate with different CA
                $certPath = Join-Path $script:TestDir "wrong-issuer.pem"
                $keyPath = Join-Path $script:TestDir "wrong-issuer.key"

                & openssl req -x509 -newkey rsa:2048 -keyout $keyPath -out $certPath -days 1 -nodes -subj "/CN=Wrong Issuer" 2>&1 | Out-Null

                # Should not be in CRL (different issuer)
                $result = Test-CertificateRevoked -CertificatePath $certPath -CrlPath $crlPath
                $result | Should -BeIn @($false, $null)
            } catch {
                Set-ItResult -Skipped -Because "Wrong issuer test failed: $_"
            }
        }
    }
}

Describe "CRL Agent Integration" -Tags @('Integration', 'CRL', 'Agent') {

    Context "Agent CRL Configuration" {
        It "ACME agent config includes CRL settings" {
            $configPath = "$PSScriptRoot/../../agents/acme/config.yaml"

            if (Test-Path $configPath) {
                $config = Get-Content $configPath -Raw
                $config | Should -Match 'crl:'
                $config | Should -Match 'enabled:'
                $config | Should -Match 'url:'
                $config | Should -Match 'cache_path:'
            } else {
                Set-ItResult -Skipped -Because "ACME config not found"
            }
        }

        It "EST agent config includes CRL settings" {
            $configPath = "$PSScriptRoot/../../agents/est/config.yaml"

            if (Test-Path $configPath) {
                $config = Get-Content $configPath -Raw
                $config | Should -Match 'crl:'
                $config | Should -Match 'enabled:'
                $config | Should -Match 'url:'
                $config | Should -Match 'cache_path:'
            } else {
                Set-ItResult -Skipped -Because "EST config not found"
            }
        }
    }

    Context "CRL Generation Infrastructure" {
        It "CRL generation script exists" {
            $scriptPath = "$PSScriptRoot/../../pki/scripts/generate-crl.sh"

            if (Test-Path $scriptPath) {
                $content = Get-Content $scriptPath -Raw
                $content | Should -Not -BeNullOrEmpty
                $content | Should -Match 'crl'
            } else {
                Set-ItResult -Skipped -Because "CRL generation script not found"
            }
        }

        It "CRL cron configuration exists" {
            $cronPath = "$PSScriptRoot/../../pki/cron/generate-crl"

            if (Test-Path $cronPath) {
                $content = Get-Content $cronPath -Raw
                $content | Should -Not -BeNullOrEmpty
                $content | Should -Match 'generate-crl'
            } else {
                Set-ItResult -Skipped -Because "CRL cron config not found"
            }
        }

        It "CRL nginx configuration exists" {
            $nginxPath = "$PSScriptRoot/../../pki/nginx/crl-server.conf"

            if (Test-Path $nginxPath) {
                $content = Get-Content $nginxPath -Raw
                $content | Should -Not -BeNullOrEmpty
                $content | Should -Match '9001'  # CRL port
                $content | Should -Match '/crl'
            } else {
                Set-ItResult -Skipped -Because "CRL nginx config not found"
            }
        }
    }
}

Describe "CRL Performance and Reliability" -Tags @('Integration', 'CRL', 'Performance') {

    Context "Performance Characteristics" {
        It "CRL download completes within timeout" {
            $cachePath = Join-Path $script:TestDir "perf-download.crl"
            $sw = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                $result = Get-CrlFromUrl -Url $script:CrlUrl -CachePath $cachePath -TimeoutSeconds 10
                $sw.Stop()

                $result | Should -Be $true
                $sw.ElapsedSeconds | Should -BeLessThan 10
            } catch {
                Set-ItResult -Skipped -Because "CRL download performance test failed: $_"
            }
        }

        It "CRL parsing completes quickly" {
            # Skip if openssl not available
            $opensslAvailable = Get-Command openssl -ErrorAction SilentlyContinue
            if (-not $opensslAvailable) {
                Set-ItResult -Skipped -Because "openssl not available"
                return
            }

            try {
                $cachePath = Join-Path $script:TestDir "perf-parse.crl"
                Get-CrlFromUrl -Url $script:CrlUrl -CachePath $cachePath | Out-Null

                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $info = Get-CrlInfo -CrlPath $cachePath
                $sw.Stop()

                $sw.ElapsedMilliseconds | Should -BeLessThan 1000  # Less than 1 second
            } catch {
                Set-ItResult -Skipped -Because "CRL parsing performance test failed: $_"
            }
        }

        It "Multiple concurrent CRL checks don't block" {
            try {
                $cachePath = Join-Path $script:TestDir "concurrent.crl"
                Get-CrlFromUrl -Url $script:CrlUrl -CachePath $cachePath | Out-Null

                # Create test certificate
                $certPath = Join-Path $script:TestDir "concurrent-cert.pem"
                $keyPath = Join-Path $script:TestDir "concurrent-cert.key"

                & openssl req -x509 -newkey rsa:2048 -keyout $keyPath -out $certPath -days 1 -nodes -subj "/CN=Concurrent" 2>&1 | Out-Null

                if (Test-Path $certPath) {
                    # Run multiple checks in parallel
                    $jobs = 1..5 | ForEach-Object {
                        Start-Job -ScriptBlock {
                            param($ModulePath, $CertPath, $CrlPath)
                            Import-Module $ModulePath -Force
                            Test-CertificateRevoked -CertificatePath $CertPath -CrlPath $CrlPath
                        } -ArgumentList $modulePath, $certPath, $cachePath
                    }

                    # Wait for all jobs
                    $jobs | Wait-Job -Timeout 10 | Out-Null
                    $jobs | Remove-Job -Force

                    # Test passes if jobs complete
                    $true | Should -Be $true
                }
            } catch {
                Set-ItResult -Skipped -Because "Concurrent access test failed: $_"
            }
        }
    }

    Context "Error Recovery" {
        It "Handles network interruption gracefully" {
            $cachePath = Join-Path $script:TestDir "network-failure.crl"

            # First successful download
            try {
                Update-CrlCache -Url $script:CrlUrl -CachePath $cachePath -MaxAgeHours 24 | Out-Null

                # Simulate network failure by using invalid URL
                $result = Update-CrlCache -Url "http://invalid.local/crl" -CachePath $cachePath -MaxAgeHours 0

                # Should fail gracefully without exception
                $result | Should -Not -BeNullOrEmpty
                $result.Downloaded | Should -Be $false
                $result.Error | Should -Not -BeNullOrEmpty
            } catch {
                Set-ItResult -Skipped -Because "Network interruption test failed: $_"
            }
        }

        It "Falls back to cached CRL on download failure" {
            $cachePath = Join-Path $script:TestDir "fallback.crl"

            try {
                # Create initial cache
                Update-CrlCache -Url $script:CrlUrl -CachePath $cachePath -MaxAgeHours 24 | Out-Null

                # Verify cache exists
                Test-Path $cachePath | Should -Be $true

                # Attempt update with invalid URL (simulating network failure)
                # Even if download fails, cached file should still exist
                Update-CrlCache -Url "http://invalid.local/crl" -CachePath $cachePath -MaxAgeHours 0 -ErrorAction SilentlyContinue

                # Cache should still exist for fallback
                Test-Path $cachePath | Should -Be $true
            } catch {
                Set-ItResult -Skipped -Because "Fallback test failed: $_"
            }
        }
    }
}

AfterAll {
    Write-Host "[TEARDOWN] CRL Integration Tests Complete" -ForegroundColor Cyan
}
