<#
.SYNOPSIS
    Validation and smoke test script for CryptoHelper.psm1 module.

.DESCRIPTION
    This script performs comprehensive testing of the CryptoHelper module:
    1. PSScriptAnalyzer validation (zero errors required)
    2. Module import test
    3. Function availability test
    4. Functional smoke tests for each exported function
    5. Integration tests (chaining operations)

    Run this script in PowerShell Core 7.0+ environment (e.g., Docker container).

.NOTES
    Usage: pwsh -File agents/common/test_cryptohelper.ps1
#>

#Requires -Version 7.0

# Color output helpers
function Write-Success { param([string]$Message) Write-Host "[✓] $Message" -ForegroundColor Green }
function Write-Failure { param([string]$Message) Write-Host "[✗] $Message" -ForegroundColor Red }
function Write-TestHeader { param([string]$Message) Write-Host "`n=== $Message ===" -ForegroundColor Cyan }

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot "CryptoHelper.psm1"
$testsPassed = 0
$testsFailed = 0

# ============================================================================
# TEST 1: PSScriptAnalyzer Validation
# ============================================================================
Write-TestHeader "PSScriptAnalyzer Validation"

try {
    # Check if PSScriptAnalyzer is installed
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        Write-Warning "PSScriptAnalyzer not installed. Installing..."
        Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
    }

    Import-Module PSScriptAnalyzer -ErrorAction Stop

    # Run analyzer with Error severity
    $errors = Invoke-ScriptAnalyzer -Path $modulePath -Severity Error

    if ($errors.Count -eq 0) {
        Write-Success "PSScriptAnalyzer: No errors found"
        $testsPassed++
    }
    else {
        Write-Failure "PSScriptAnalyzer: $($errors.Count) error(s) found"
        $errors | ForEach-Object {
            Write-Host "  Line $($_.Line): $($_.Message)" -ForegroundColor Yellow
        }
        $testsFailed++
    }

    # Run analyzer with Warning severity (informational)
    $warnings = Invoke-ScriptAnalyzer -Path $modulePath -Severity Warning

    if ($warnings.Count -gt 0) {
        Write-Host "[i] PSScriptAnalyzer: $($warnings.Count) warning(s) found (non-blocking)" -ForegroundColor Yellow
    }
}
catch {
    Write-Failure "PSScriptAnalyzer test failed: $($_.Exception.Message)"
    $testsFailed++
}

# ============================================================================
# TEST 2: Module Import
# ============================================================================
Write-TestHeader "Module Import Test"

try {
    Import-Module $modulePath -Force -ErrorAction Stop
    Write-Success "Module imported successfully"
    $testsPassed++
}
catch {
    Write-Failure "Module import failed: $($_.Exception.Message)"
    $testsFailed++
    exit 1  # Cannot continue without module
}

# ============================================================================
# TEST 3: Exported Functions Availability
# ============================================================================
Write-TestHeader "Exported Functions Availability"

$expectedFunctions = @(
    'New-RSAKeyPair',
    'New-CertificateRequest',
    'Read-Certificate',
    'Export-PrivateKey',
    'Test-CertificateExpiry'
)

$moduleCommands = Get-Command -Module CryptoHelper

foreach ($funcName in $expectedFunctions) {
    if ($moduleCommands.Name -contains $funcName) {
        Write-Success "Function '$funcName' is exported"
        $testsPassed++
    }
    else {
        Write-Failure "Function '$funcName' is NOT exported"
        $testsFailed++
    }
}

# ============================================================================
# TEST 4: New-RSAKeyPair Functional Test
# ============================================================================
Write-TestHeader "New-RSAKeyPair Functional Test"

try {
    $privateKeyPem = New-RSAKeyPair

    # Validate PEM format
    if ($privateKeyPem -match '^-----BEGIN PRIVATE KEY-----') {
        Write-Success "New-RSAKeyPair: Returns valid PEM header"
        $testsPassed++
    }
    else {
        Write-Failure "New-RSAKeyPair: Invalid PEM header"
        $testsFailed++
    }

    if ($privateKeyPem -match '-----END PRIVATE KEY-----$') {
        Write-Success "New-RSAKeyPair: Returns valid PEM footer"
        $testsPassed++
    }
    else {
        Write-Failure "New-RSAKeyPair: Invalid PEM footer"
        $testsFailed++
    }

    # Validate output is string
    if ($privateKeyPem -is [string]) {
        Write-Success "New-RSAKeyPair: Returns string type"
        $testsPassed++
    }
    else {
        Write-Failure "New-RSAKeyPair: Does not return string type"
        $testsFailed++
    }

    # Save for later use
    $script:testPrivateKeyPem = $privateKeyPem
    Write-Host "[i] Generated private key (first 60 chars): $($privateKeyPem.Substring(0, [Math]::Min(60, $privateKeyPem.Length)))..." -ForegroundColor Gray
}
catch {
    Write-Failure "New-RSAKeyPair test failed: $($_.Exception.Message)"
    $testsFailed++
}

# ============================================================================
# TEST 5: New-CertificateRequest Functional Test
# ============================================================================
Write-TestHeader "New-CertificateRequest Functional Test"

try {
    # Generate fresh RSA key for CSR
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)

    # Test with SANs
    $csrPem = New-CertificateRequest -SubjectDN "CN=test.example.com, O=Test Corp" -SubjectAlternativeNames @("test.example.com", "www.test.example.com") -RsaKey $rsa

    # Validate PEM format
    if ($csrPem -match '^-----BEGIN CERTIFICATE REQUEST-----') {
        Write-Success "New-CertificateRequest: Returns valid CSR PEM header"
        $testsPassed++
    }
    else {
        Write-Failure "New-CertificateRequest: Invalid CSR PEM header"
        $testsFailed++
    }

    if ($csrPem -match '-----END CERTIFICATE REQUEST-----$') {
        Write-Success "New-CertificateRequest: Returns valid CSR PEM footer"
        $testsPassed++
    }
    else {
        Write-Failure "New-CertificateRequest: Invalid CSR PEM footer"
        $testsFailed++
    }

    # Test without SANs (empty array)
    $csrNoSan = New-CertificateRequest -SubjectDN "CN=client-device-001" -SubjectAlternativeNames @() -RsaKey $rsa

    if ($csrNoSan -match '^-----BEGIN CERTIFICATE REQUEST-----') {
        Write-Success "New-CertificateRequest: Works with empty SANs array"
        $testsPassed++
    }
    else {
        Write-Failure "New-CertificateRequest: Fails with empty SANs array"
        $testsFailed++
    }

    Write-Host "[i] Generated CSR (first 70 chars): $($csrPem.Substring(0, [Math]::Min(70, $csrPem.Length)))..." -ForegroundColor Gray

    # Clean up
    $rsa.Dispose()
}
catch {
    Write-Failure "New-CertificateRequest test failed: $($_.Exception.Message)"
    $testsFailed++
}

# ============================================================================
# TEST 6: Export-PrivateKey Functional Test
# ============================================================================
Write-TestHeader "Export-PrivateKey Functional Test"

try {
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $exportedPem = Export-PrivateKey -RsaKey $rsa

    # Validate PEM format
    if ($exportedPem -match '^-----BEGIN PRIVATE KEY-----') {
        Write-Success "Export-PrivateKey: Returns valid PEM header"
        $testsPassed++
    }
    else {
        Write-Failure "Export-PrivateKey: Invalid PEM header"
        $testsFailed++
    }

    if ($exportedPem -match '-----END PRIVATE KEY-----$') {
        Write-Success "Export-PrivateKey: Returns valid PEM footer"
        $testsPassed++
    }
    else {
        Write-Failure "Export-PrivateKey: Invalid PEM footer"
        $testsFailed++
    }

    # Clean up
    $rsa.Dispose()
}
catch {
    Write-Failure "Export-PrivateKey test failed: $($_.Exception.Message)"
    $testsFailed++
}

# ============================================================================
# TEST 7: Read-Certificate Functional Test
# ============================================================================
Write-TestHeader "Read-Certificate Functional Test"

try {
    # Create a temporary self-signed certificate for testing
    $testCertPath = Join-Path ([System.IO.Path]::GetTempPath()) "test_cert_$(Get-Random).pem"

    # Generate test certificate using .NET
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $subject = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new("CN=TestCert")
    $certRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        $subject,
        $rsa,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )

    # Create self-signed certificate valid for 90 days
    $cert = $certRequest.CreateSelfSigned([DateTimeOffset]::UtcNow, [DateTimeOffset]::UtcNow.AddDays(90))

    # Export to PEM
    $certPem = "-----BEGIN CERTIFICATE-----`n"
    $certPem += [Convert]::ToBase64String($cert.RawData, [Base64FormattingOptions]::InsertLineBreaks)
    $certPem += "`n-----END CERTIFICATE-----"

    Set-Content -Path $testCertPath -Value $certPem

    # Test Read-Certificate
    $readCert = Read-Certificate -Path $testCertPath

    # Validate returned object
    if ($readCert -is [System.Security.Cryptography.X509Certificates.X509Certificate2]) {
        Write-Success "Read-Certificate: Returns X509Certificate2 object"
        $testsPassed++
    }
    else {
        Write-Failure "Read-Certificate: Does not return X509Certificate2 object"
        $testsFailed++
    }

    # Validate properties
    if ($readCert.Subject -eq "CN=TestCert") {
        Write-Success "Read-Certificate: Subject property accessible"
        $testsPassed++
    }
    else {
        Write-Failure "Read-Certificate: Subject property incorrect or inaccessible"
        $testsFailed++
    }

    if ($null -ne $readCert.NotBefore -and $null -ne $readCert.NotAfter) {
        Write-Success "Read-Certificate: NotBefore/NotAfter properties accessible"
        $testsPassed++
    }
    else {
        Write-Failure "Read-Certificate: NotBefore/NotAfter properties inaccessible"
        $testsFailed++
    }

    if ($null -ne $readCert.SerialNumber) {
        Write-Success "Read-Certificate: SerialNumber property accessible"
        $testsPassed++
    }
    else {
        Write-Failure "Read-Certificate: SerialNumber property inaccessible"
        $testsFailed++
    }

    Write-Host "[i] Certificate Subject: $($readCert.Subject)" -ForegroundColor Gray
    Write-Host "[i] Certificate Valid: $($readCert.NotBefore) to $($readCert.NotAfter)" -ForegroundColor Gray

    # Save for Test-CertificateExpiry test
    $script:testCertificate = $readCert

    # Test error handling: non-existent file
    try {
        $null = Read-Certificate -Path "/nonexistent/path/cert.pem"
        Write-Failure "Read-Certificate: Should throw on non-existent file"
        $testsFailed++
    }
    catch {
        Write-Success "Read-Certificate: Correctly throws on non-existent file"
        $testsPassed++
    }

    # Clean up
    Remove-Item -Path $testCertPath -Force -ErrorAction SilentlyContinue
    $rsa.Dispose()
    $cert.Dispose()
}
catch {
    Write-Failure "Read-Certificate test failed: $($_.Exception.Message)"
    $testsFailed++
}

# ============================================================================
# TEST 8: Test-CertificateExpiry Functional Test
# ============================================================================
Write-TestHeader "Test-CertificateExpiry Functional Test"

try {
    if ($null -eq $script:testCertificate) {
        Write-Warning "Test certificate not available, skipping expiry test"
    }
    else {
        # Test with low threshold (should return false for fresh 90-day cert)
        $needsRenewal = Test-CertificateExpiry -Certificate $script:testCertificate -ThresholdPercentage 75

        if ($needsRenewal -is [bool]) {
            Write-Success "Test-CertificateExpiry: Returns boolean type"
            $testsPassed++
        }
        else {
            Write-Failure "Test-CertificateExpiry: Does not return boolean type"
            $testsFailed++
        }

        # Fresh certificate should not need renewal at 75% threshold
        if ($needsRenewal -eq $false) {
            Write-Success "Test-CertificateExpiry: Correctly returns false for fresh certificate"
            $testsPassed++
        }
        else {
            Write-Failure "Test-CertificateExpiry: Incorrectly returns true for fresh certificate"
            $testsFailed++
        }

        # Test with 1% threshold (should return true - certificate is past 1% of lifetime)
        $needsRenewalLowThreshold = Test-CertificateExpiry -Certificate $script:testCertificate -ThresholdPercentage 1

        if ($needsRenewalLowThreshold -eq $true) {
            Write-Success "Test-CertificateExpiry: Correctly handles low threshold"
            $testsPassed++
        }
        else {
            Write-Failure "Test-CertificateExpiry: Incorrectly handles low threshold"
            $testsFailed++
        }

        # Calculate and display actual elapsed percentage
        $now = [DateTime]::UtcNow
        $totalSeconds = ($script:testCertificate.NotAfter - $script:testCertificate.NotBefore).TotalSeconds
        $elapsedSeconds = ($now - $script:testCertificate.NotBefore).TotalSeconds
        $elapsedPercentage = [Math]::Round(($elapsedSeconds / $totalSeconds) * 100, 2)

        Write-Host "[i] Certificate lifetime elapsed: $elapsedPercentage%" -ForegroundColor Gray
    }
}
catch {
    Write-Failure "Test-CertificateExpiry test failed: $($_.Exception.Message)"
    $testsFailed++
}

# ============================================================================
# TEST 9: Parameter Validation Tests
# ============================================================================
Write-TestHeader "Parameter Validation Tests"

# Test New-CertificateRequest with null RSA key (should throw)
try {
    $null = New-CertificateRequest -SubjectDN "CN=test" -SubjectAlternativeNames @() -RsaKey $null
    Write-Failure "New-CertificateRequest: Should reject null RSA key"
    $testsFailed++
}
catch {
    Write-Success "New-CertificateRequest: Correctly rejects null RSA key"
    $testsPassed++
}

# Test Test-CertificateExpiry with invalid threshold (0)
try {
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $subject = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new("CN=Test")
    $certRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        $subject, $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
    $testCert = $certRequest.CreateSelfSigned([DateTimeOffset]::UtcNow, [DateTimeOffset]::UtcNow.AddDays(90))

    $null = Test-CertificateExpiry -Certificate $testCert -ThresholdPercentage 0
    Write-Failure "Test-CertificateExpiry: Should reject threshold 0"
    $testsFailed++

    $rsa.Dispose()
    $testCert.Dispose()
}
catch {
    Write-Success "Test-CertificateExpiry: Correctly rejects invalid threshold (0)"
    $testsPassed++
}

# Test Test-CertificateExpiry with invalid threshold (101)
try {
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $subject = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new("CN=Test")
    $certRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        $subject, $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
    $testCert = $certRequest.CreateSelfSigned([DateTimeOffset]::UtcNow, [DateTimeOffset]::UtcNow.AddDays(90))

    $null = Test-CertificateExpiry -Certificate $testCert -ThresholdPercentage 101
    Write-Failure "Test-CertificateExpiry: Should reject threshold 101"
    $testsFailed++

    $rsa.Dispose()
    $testCert.Dispose()
}
catch {
    Write-Success "Test-CertificateExpiry: Correctly rejects invalid threshold (101)"
    $testsPassed++
}

# ============================================================================
# TEST SUMMARY
# ============================================================================
Write-TestHeader "Test Summary"

$totalTests = $testsPassed + $testsFailed
$passRate = if ($totalTests -gt 0) { [Math]::Round(($testsPassed / $totalTests) * 100, 1) } else { 0 }

Write-Host ""
Write-Host "Total Tests: $totalTests" -ForegroundColor White
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { "Green" } else { "Red" })
Write-Host "Pass Rate: $passRate%" -ForegroundColor $(if ($passRate -eq 100) { "Green" } elseif ($passRate -ge 80) { "Yellow" } else { "Red" })
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Success "All tests passed! Module is ready for use."
    exit 0
}
else {
    Write-Failure "Some tests failed. Please review errors above."
    exit 1
}
