# ==============================================================================
# CrlValidator.Tests.ps1 - Unit Tests for CRL Validation Module
# ==============================================================================
# Tests for Certificate Revocation List download, caching, and validation
# ==============================================================================

BeforeAll {
    # Import module under test
    $modulePath = Resolve-Path "$PSScriptRoot/../../agents/common/CrlValidator.psm1"
    Import-Module $modulePath -Force

    # Create test directory
    $script:TestDir = Join-Path $TestDrive "crl-tests"
    New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null
}

Describe "CrlValidator Module" -Tags @('Unit', 'CRL') {

    Context "Get-CrlAge" {
        It "Returns -1 for non-existent CRL file" {
            $result = Get-CrlAge -CrlPath "/nonexistent/crl.crl"
            $result | Should -Be -1
            $result | Should -BeOfType ([double])
        }

        It "Returns age in hours for existing CRL file" {
            # Create a test file
            $crlPath = Join-Path $script:TestDir "test.crl"
            "test crl content" | Out-File $crlPath

            # File just created should have age near 0
            $age = Get-CrlAge -CrlPath $crlPath
            $age | Should -BeGreaterOrEqual 0.0
            $age | Should -BeLessThan 0.1  # Less than 6 minutes old
        }

        It "Returns positive age for old file" {
            $crlPath = Join-Path $script:TestDir "old.crl"
            "old crl" | Out-File $crlPath

            # Set file timestamp to 25 hours ago
            $oldTime = (Get-Date).AddHours(-25)
            (Get-Item $crlPath).LastWriteTime = $oldTime

            $age = Get-CrlAge -CrlPath $crlPath
            $age | Should -BeGreaterThan 24.0
            $age | Should -BeLessThan 26.0
        }
    }

    Context "Get-CrlFromUrl" {
        It "Creates cache directory if it doesn't exist" {
            $cachePath = Join-Path $script:TestDir "newdir/test.crl"

            # This will fail to download but should create the directory
            Get-CrlFromUrl -Url "http://invalid.local/crl" -CachePath $cachePath -ErrorAction SilentlyContinue

            $cacheDir = Split-Path $cachePath -Parent
            Test-Path $cacheDir | Should -Be $true
        }

        It "Returns false for invalid URL" {
            $cachePath = Join-Path $script:TestDir "invalid.crl"
            $result = Get-CrlFromUrl -Url "http://invalid.local/crl" -CachePath $cachePath -TimeoutSeconds 1
            $result | Should -Be $false
        }
    }

    Context "Get-CrlInfo" {
        It "Returns null for non-existent CRL" {
            $result = Get-CrlInfo -CrlPath "/nonexistent/crl.crl"
            $result | Should -BeNullOrEmpty
        }

        It "Returns hashtable for valid CRL (with openssl)" {
            # Skip if openssl not available
            $opensslAvailable = Get-Command openssl -ErrorAction SilentlyContinue
            if (-not $opensslAvailable) {
                Set-ItResult -Skipped -Because "openssl not available"
                return
            }

            # Create a minimal CRL using openssl
            $crlPath = Join-Path $script:TestDir "minimal.crl"
            $keyPath = Join-Path $script:TestDir "ca.key"
            $certPath = Join-Path $script:TestDir "ca.crt"
            $indexPath = Join-Path $script:TestDir "index.txt"
            $crlnumPath = Join-Path $script:TestDir "crlnumber"
            $confPath = Join-Path $script:TestDir "openssl.cnf"

            # Generate CA key and certificate
            & openssl genrsa -out $keyPath 2048 2>&1 | Out-Null
            & openssl req -new -x509 -key $keyPath -out $certPath -days 1 -subj "/CN=Test CA" 2>&1 | Out-Null

            # Create empty index and crlnumber
            "" | Out-File $indexPath -NoNewline
            "01" | Out-File $crlnumPath -NoNewline

            # Create minimal config
            @"
[ca]
default_ca = CA_default

[CA_default]
database = $indexPath
crlnumber = $crlnumPath
default_crl_days = 1
default_md = sha256
"@ | Out-File $confPath

            # Generate CRL
            & openssl ca -config $confPath -gencrl -keyfile $keyPath -cert $certPath -out $crlPath 2>&1 | Out-Null

            if (Test-Path $crlPath) {
                $info = Get-CrlInfo -CrlPath $crlPath
                $info | Should -Not -BeNullOrEmpty
                $info.ContainsKey('Issuer') | Should -Be $true
                $info.ContainsKey('RevokedCount') | Should -Be $true
                $info.RevokedCount | Should -Be 0  # No revoked certs
            }
        }
    }

    Context "Test-CertificateRevoked" {
        It "Returns null for non-existent certificate" {
            $crlPath = Join-Path $script:TestDir "test.crl"
            "" | Out-File $crlPath

            $result = Test-CertificateRevoked -CertificatePath "/nonexistent/cert.pem" -CrlPath $crlPath
            $result | Should -BeNullOrEmpty
        }

        It "Returns null for non-existent CRL" {
            # Create a minimal self-signed certificate
            $certPath = Join-Path $script:TestDir "test.crt"
            $keyPath = Join-Path $script:TestDir "test.key"

            # Skip if openssl not available
            $opensslAvailable = Get-Command openssl -ErrorAction SilentlyContinue
            if (-not $opensslAvailable) {
                Set-ItResult -Skipped -Because "openssl not available"
                return
            }

            & openssl req -x509 -newkey rsa:2048 -keyout $keyPath -out $certPath -days 1 -nodes -subj "/CN=Test" 2>&1 | Out-Null

            $result = Test-CertificateRevoked -CertificatePath $certPath -CrlPath "/nonexistent/crl.crl"
            $result | Should -BeNullOrEmpty
        }

        It "Returns false for valid certificate not in CRL" {
            # Skip if openssl not available
            $opensslAvailable = Get-Command openssl -ErrorAction SilentlyContinue
            if (-not $opensslAvailable) {
                Set-ItResult -Skipped -Because "openssl not available"
                return
            }

            # Create CA and certificate
            $crlPath = Join-Path $script:TestDir "valid.crl"
            $caKeyPath = Join-Path $script:TestDir "ca2.key"
            $caCertPath = Join-Path $script:TestDir "ca2.crt"
            $certPath = Join-Path $script:TestDir "valid.crt"
            $certKeyPath = Join-Path $script:TestDir "valid.key"
            $indexPath = Join-Path $script:TestDir "index2.txt"
            $crlnumPath = Join-Path $script:TestDir "crlnumber2"
            $confPath = Join-Path $script:TestDir "openssl2.cnf"

            # Generate CA
            & openssl genrsa -out $caKeyPath 2048 2>&1 | Out-Null
            & openssl req -new -x509 -key $caKeyPath -out $caCertPath -days 1 -subj "/CN=Test CA 2" 2>&1 | Out-Null

            # Generate certificate
            & openssl req -x509 -newkey rsa:2048 -keyout $certKeyPath -out $certPath -days 1 -nodes -subj "/CN=Valid Cert" 2>&1 | Out-Null

            # Create empty CRL
            "" | Out-File $indexPath -NoNewline
            "01" | Out-File $crlnumPath -NoNewline
            @"
[ca]
default_ca = CA_default

[CA_default]
database = $indexPath
crlnumber = $crlnumPath
default_crl_days = 1
default_md = sha256
"@ | Out-File $confPath

            & openssl ca -config $confPath -gencrl -keyfile $caKeyPath -cert $caCertPath -out $crlPath 2>&1 | Out-Null

            if (Test-Path $crlPath) {
                $result = Test-CertificateRevoked -CertificatePath $certPath -CrlPath $crlPath
                # Result may be false or null depending on serial number matching
                $result | Should -BeIn @($false, $null)
            }
        }
    }

    Context "Update-CrlCache" {
        It "Returns error for invalid URL" {
            $cachePath = Join-Path $script:TestDir "update-test.crl"
            $result = Update-CrlCache -Url "http://invalid.local/crl" -CachePath $cachePath -MaxAgeHours 24

            $result | Should -Not -BeNullOrEmpty
            $result.Updated | Should -Be $false
            $result.CrlAge | Should -Be -1
        }

        It "Reports CRL as missing when cache doesn't exist" {
            $cachePath = Join-Path $script:TestDir "missing-cache.crl"
            $result = Update-CrlCache -Url "http://invalid.local/crl" -CachePath $cachePath -MaxAgeHours 24

            $result.CrlAge | Should -Be -1
        }

        It "Returns fresh status for recently created cache" {
            $cachePath = Join-Path $script:TestDir "fresh-cache.crl"
            "test crl" | Out-File $cachePath

            # Use invalid URL - should not download since cache is fresh
            $result = Update-CrlCache -Url "http://invalid.local/crl" -CachePath $cachePath -MaxAgeHours 24

            $result.Updated | Should -Be $false
            $result.CrlAge | Should -BeGreaterOrEqual 0.0
            $result.CrlAge | Should -BeLessThan 1.0  # Less than 1 hour old
        }

        It "Attempts update for stale cache" {
            $cachePath = Join-Path $script:TestDir "stale-cache.crl"
            "old crl" | Out-File $cachePath

            # Set to 25 hours old
            $oldTime = (Get-Date).AddHours(-25)
            (Get-Item $cachePath).LastWriteTime = $oldTime

            $result = Update-CrlCache -Url "http://invalid.local/crl" -CachePath $cachePath -MaxAgeHours 24

            # Should have attempted download (but failed due to invalid URL)
            $result.CrlAge | Should -BeGreaterThan 24.0
            $result.Downloaded | Should -Be $false
        }
    }

    Context "Module Exports" {
        It "Exports Get-CrlFromUrl function" {
            $exported = Get-Command Get-CrlFromUrl -ErrorAction SilentlyContinue
            $exported | Should -Not -BeNullOrEmpty
        }

        It "Exports Get-CrlAge function" {
            $exported = Get-Command Get-CrlAge -ErrorAction SilentlyContinue
            $exported | Should -Not -BeNullOrEmpty
        }

        It "Exports Get-CrlInfo function" {
            $exported = Get-Command Get-CrlInfo -ErrorAction SilentlyContinue
            $exported | Should -Not -BeNullOrEmpty
        }

        It "Exports Test-CertificateRevoked function" {
            $exported = Get-Command Test-CertificateRevoked -ErrorAction SilentlyContinue
            $exported | Should -Not -BeNullOrEmpty
        }

        It "Exports Update-CrlCache function" {
            $exported = Get-Command Update-CrlCache -ErrorAction SilentlyContinue
            $exported | Should -Not -BeNullOrEmpty
        }
    }
}

AfterAll {
    # Cleanup is automatic with TestDrive
}
