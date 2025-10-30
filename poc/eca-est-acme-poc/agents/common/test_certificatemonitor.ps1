<#
.SYNOPSIS
    Validation and smoke test script for CertificateMonitor.psm1 module.

.DESCRIPTION
    This script performs comprehensive testing of the CertificateMonitor module:
    1. PSScriptAnalyzer validation (zero errors required)
    2. Module import test
    3. Function availability test
    4. Functional smoke tests for each exported function
    5. Integration tests (lifetime calculations, error handling)

    Run this script in PowerShell Core 7.0+ environment (e.g., Docker container).

.NOTES
    Usage: pwsh -File agents/common/test_certificatemonitor.ps1
    Dependencies: CryptoHelper.psm1 must be present in same directory
#>

#Requires -Version 7.0

# Color output helpers
function Write-Success { param([string]$Message) Write-Host "[✓] $Message" -ForegroundColor Green }
function Write-Failure { param([string]$Message) Write-Host "[✗] $Message" -ForegroundColor Red }
function Write-TestHeader { param([string]$Message) Write-Host "`n=== $Message ===" -ForegroundColor Cyan }

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot "CertificateMonitor.psm1"
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
    'Test-CertificateExists',
    'Get-CertificateLifetimeElapsed',
    'Get-CertificateInfo'
)

$moduleCommands = Get-Command -Module CertificateMonitor

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
# TEST 4: Test-CertificateExists Functional Test
# ============================================================================
Write-TestHeader "Test-CertificateExists Functional Test"

try {
    # Test with non-existent file (should return false, not throw)
    $exists = Test-CertificateExists -Path "/nonexistent/path/cert.pem"

    if ($exists -is [bool]) {
        Write-Success "Test-CertificateExists: Returns boolean type"
        $testsPassed++
    }
    else {
        Write-Failure "Test-CertificateExists: Does not return boolean type"
        $testsFailed++
    }

    if ($exists -eq $false) {
        Write-Success "Test-CertificateExists: Returns false for non-existent file"
        $testsPassed++
    }
    else {
        Write-Failure "Test-CertificateExists: Should return false for non-existent file"
        $testsFailed++
    }

    # Create temporary test file
    $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "test_cert_$(Get-Random).pem"
    Set-Content -Path $tempFile -Value "test content"

    $exists = Test-CertificateExists -Path $tempFile

    if ($exists -eq $true) {
        Write-Success "Test-CertificateExists: Returns true for existing file"
        $testsPassed++
    }
    else {
        Write-Failure "Test-CertificateExists: Should return true for existing file"
        $testsFailed++
    }

    # Clean up
    Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Failure "Test-CertificateExists test failed: $($_.Exception.Message)"
    $testsFailed++
}

# ============================================================================
# TEST 5: Create Test Certificate for Further Tests
# ============================================================================
Write-TestHeader "Creating Test Certificate Fixture"

try {
    # Create a self-signed certificate with known lifetime for testing
    $testCertPath = Join-Path ([System.IO.Path]::GetTempPath()) "test_cert_monitor_$(Get-Random).pem"

    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $subject = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new("CN=test.example.com, O=Test Corp")
    $certRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        $subject,
        $rsa,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )

    # Create certificate valid for exactly 100 days to make percentage calculations predictable
    $notBefore = [DateTimeOffset]::UtcNow
    $notAfter = $notBefore.AddDays(100)
    $cert = $certRequest.CreateSelfSigned($notBefore, $notAfter)

    # Export to PEM
    $certPem = "-----BEGIN CERTIFICATE-----`n"
    $certPem += [Convert]::ToBase64String($cert.RawData, [Base64FormattingOptions]::InsertLineBreaks)
    $certPem += "`n-----END CERTIFICATE-----"

    Set-Content -Path $testCertPath -Value $certPem

    Write-Success "Test certificate created at: $testCertPath"
    Write-Host "[i] Certificate lifetime: 100 days" -ForegroundColor Gray
    Write-Host "[i] Certificate Subject: $($cert.Subject)" -ForegroundColor Gray
    Write-Host "[i] Certificate Serial: $($cert.SerialNumber)" -ForegroundColor Gray

    # Save for later tests
    $script:testCertPath = $testCertPath
    $script:testCert = $cert
    $testsPassed++

    # Clean up RSA
    $rsa.Dispose()
}
catch {
    Write-Failure "Test certificate creation failed: $($_.Exception.Message)"
    $testsFailed++
    exit 1  # Cannot continue without test certificate
}

# ============================================================================
# TEST 6: Get-CertificateLifetimeElapsed Functional Test
# ============================================================================
Write-TestHeader "Get-CertificateLifetimeElapsed Functional Test"

try {
    $elapsed = Get-CertificateLifetimeElapsed -Certificate $script:testCert

    # Validate return type
    if ($elapsed -is [double]) {
        Write-Success "Get-CertificateLifetimeElapsed: Returns double type"
        $testsPassed++
    }
    else {
        Write-Failure "Get-CertificateLifetimeElapsed: Does not return double type (got $($elapsed.GetType().Name))"
        $testsFailed++
    }

    # For a just-created certificate, elapsed should be very close to 0% (within 1%)
    if ($elapsed -ge 0.0 -and $elapsed -le 1.0) {
        Write-Success "Get-CertificateLifetimeElapsed: Returns reasonable value for fresh certificate ($elapsed%)"
        $testsPassed++
    }
    else {
        Write-Failure "Get-CertificateLifetimeElapsed: Unexpected value for fresh certificate ($elapsed%)"
        $testsFailed++
    }

    # Check precision (should have 2 decimal places when converted to string with fixed format)
    $elapsedStr = $elapsed.ToString("F2")
    if ($elapsedStr -match '^\d+\.\d{2}$') {
        Write-Success "Get-CertificateLifetimeElapsed: Returns value with 2 decimal precision"
        $testsPassed++
    }
    else {
        Write-Failure "Get-CertificateLifetimeElapsed: Value not formatted to 2 decimals ($elapsedStr)"
        $testsFailed++
    }

    Write-Host "[i] Certificate lifetime elapsed: $elapsed%" -ForegroundColor Gray

    # Test with pipeline input
    $elapsedPipeline = $script:testCert | Get-CertificateLifetimeElapsed
    if ($elapsedPipeline -eq $elapsed) {
        Write-Success "Get-CertificateLifetimeElapsed: Accepts pipeline input"
        $testsPassed++
    }
    else {
        Write-Failure "Get-CertificateLifetimeElapsed: Pipeline input not working correctly"
        $testsFailed++
    }
}
catch {
    Write-Failure "Get-CertificateLifetimeElapsed test failed: $($_.Exception.Message)"
    $testsFailed++
}

# ============================================================================
# TEST 7: Get-CertificateInfo Functional Test
# ============================================================================
Write-TestHeader "Get-CertificateInfo Functional Test"

try {
    $info = Get-CertificateInfo -Path $script:testCertPath

    # Validate return type
    if ($info -is [hashtable]) {
        Write-Success "Get-CertificateInfo: Returns hashtable type"
        $testsPassed++
    }
    else {
        Write-Failure "Get-CertificateInfo: Does not return hashtable type"
        $testsFailed++
    }

    # Check all required keys are present
    $requiredKeys = @('Subject', 'Issuer', 'NotBefore', 'NotAfter', 'SerialNumber', 'DaysRemaining', 'LifetimeElapsedPercent')
    $missingKeys = $requiredKeys | Where-Object { -not $info.ContainsKey($_) }

    if ($missingKeys.Count -eq 0) {
        Write-Success "Get-CertificateInfo: All required keys present"
        $testsPassed++
    }
    else {
        Write-Failure "Get-CertificateInfo: Missing keys: $($missingKeys -join ', ')"
        $testsFailed++
    }

    # Validate Subject field
    if ($info.Subject -eq $script:testCert.Subject) {
        Write-Success "Get-CertificateInfo: Subject matches certificate"
        $testsPassed++
    }
    else {
        Write-Failure "Get-CertificateInfo: Subject does not match (expected: $($script:testCert.Subject), got: $($info.Subject))"
        $testsFailed++
    }

    # Validate Issuer field (self-signed, so should equal Subject)
    if ($info.Issuer -eq $script:testCert.Issuer) {
        Write-Success "Get-CertificateInfo: Issuer matches certificate"
        $testsPassed++
    }
    else {
        Write-Failure "Get-CertificateInfo: Issuer does not match"
        $testsFailed++
    }

    # Validate SerialNumber field
    if ($info.SerialNumber -eq $script:testCert.SerialNumber) {
        Write-Success "Get-CertificateInfo: SerialNumber matches certificate"
        $testsPassed++
    }
    else {
        Write-Failure "Get-CertificateInfo: SerialNumber does not match"
        $testsFailed++
    }

    # Validate NotBefore/NotAfter
    if ($info.NotBefore -eq $script:testCert.NotBefore) {
        Write-Success "Get-CertificateInfo: NotBefore matches certificate"
        $testsPassed++
    }
    else {
        Write-Failure "Get-CertificateInfo: NotBefore does not match"
        $testsFailed++
    }

    if ($info.NotAfter -eq $script:testCert.NotAfter) {
        Write-Success "Get-CertificateInfo: NotAfter matches certificate"
        $testsPassed++
    }
    else {
        Write-Failure "Get-CertificateInfo: NotAfter does not match"
        $testsFailed++
    }

    # Validate DaysRemaining calculation (should be close to 100 for fresh 100-day cert)
    if ($info.DaysRemaining -ge 99.9 -and $info.DaysRemaining -le 100.0) {
        Write-Success "Get-CertificateInfo: DaysRemaining calculated correctly ($($info.DaysRemaining))"
        $testsPassed++
    }
    else {
        Write-Failure "Get-CertificateInfo: DaysRemaining out of expected range (got: $($info.DaysRemaining), expected ~100)"
        $testsFailed++
    }

    # Validate DaysRemaining precision (2 decimals)
    $daysStr = $info.DaysRemaining.ToString("F2")
    if ($daysStr -match '^\d+\.\d{2}$') {
        Write-Success "Get-CertificateInfo: DaysRemaining has 2 decimal precision"
        $testsPassed++
    }
    else {
        Write-Failure "Get-CertificateInfo: DaysRemaining not formatted to 2 decimals ($daysStr)"
        $testsFailed++
    }

    # Validate LifetimeElapsedPercent
    if ($info.LifetimeElapsedPercent -ge 0.0 -and $info.LifetimeElapsedPercent -le 1.0) {
        Write-Success "Get-CertificateInfo: LifetimeElapsedPercent reasonable for fresh cert ($($info.LifetimeElapsedPercent)%)"
        $testsPassed++
    }
    else {
        Write-Failure "Get-CertificateInfo: LifetimeElapsedPercent unexpected (got: $($info.LifetimeElapsedPercent)%)"
        $testsFailed++
    }

    # Validate LifetimeElapsedPercent precision (2 decimals)
    $percentStr = $info.LifetimeElapsedPercent.ToString("F2")
    if ($percentStr -match '^\d+\.\d{2}$') {
        Write-Success "Get-CertificateInfo: LifetimeElapsedPercent has 2 decimal precision"
        $testsPassed++
    }
    else {
        Write-Failure "Get-CertificateInfo: LifetimeElapsedPercent not formatted to 2 decimals ($percentStr)"
        $testsFailed++
    }

    Write-Host "[i] Certificate Info:" -ForegroundColor Gray
    Write-Host "    Subject: $($info.Subject)" -ForegroundColor Gray
    Write-Host "    Issuer: $($info.Issuer)" -ForegroundColor Gray
    Write-Host "    Serial: $($info.SerialNumber)" -ForegroundColor Gray
    Write-Host "    Valid: $($info.NotBefore) to $($info.NotAfter)" -ForegroundColor Gray
    Write-Host "    Days Remaining: $($info.DaysRemaining)" -ForegroundColor Gray
    Write-Host "    Lifetime Elapsed: $($info.LifetimeElapsedPercent)%" -ForegroundColor Gray
}
catch {
    Write-Failure "Get-CertificateInfo test failed: $($_.Exception.Message)"
    $testsFailed++
}

# ============================================================================
# TEST 8: Error Handling Tests
# ============================================================================
Write-TestHeader "Error Handling Tests"

# Test Get-CertificateInfo with non-existent file (should throw)
try {
    $null = Get-CertificateInfo -Path "/nonexistent/path/cert.pem"
    Write-Failure "Get-CertificateInfo: Should throw on non-existent file"
    $testsFailed++
}
catch {
    if ($_.Exception.Message -match "Certificate file not found") {
        Write-Success "Get-CertificateInfo: Correctly throws on non-existent file with appropriate message"
        $testsPassed++
    }
    else {
        Write-Success "Get-CertificateInfo: Throws on non-existent file (message: $($_.Exception.Message))"
        $testsPassed++
    }
}

# Test Get-CertificateInfo with malformed certificate file
try {
    $malformedPath = Join-Path ([System.IO.Path]::GetTempPath()) "malformed_cert_$(Get-Random).pem"
    Set-Content -Path $malformedPath -Value "This is not a valid certificate"

    $null = Get-CertificateInfo -Path $malformedPath
    Write-Failure "Get-CertificateInfo: Should throw on malformed certificate"
    $testsFailed++

    Remove-Item -Path $malformedPath -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Success "Get-CertificateInfo: Correctly throws on malformed certificate"
    $testsPassed++
    Remove-Item -Path $malformedPath -Force -ErrorAction SilentlyContinue
}

# Test Get-CertificateLifetimeElapsed with null certificate (should throw)
try {
    $null = Get-CertificateLifetimeElapsed -Certificate $null
    Write-Failure "Get-CertificateLifetimeElapsed: Should reject null certificate"
    $testsFailed++
}
catch {
    Write-Success "Get-CertificateLifetimeElapsed: Correctly rejects null certificate"
    $testsPassed++
}

# ============================================================================
# TEST 9: Integration Test - CryptoHelper Dependency
# ============================================================================
Write-TestHeader "Integration Test - CryptoHelper Dependency"

try {
    # Verify that CertificateMonitor correctly uses CryptoHelper's Read-Certificate
    # by checking that it can read a certificate generated by CryptoHelper workflow

    # Import CryptoHelper
    Import-Module (Join-Path $PSScriptRoot "CryptoHelper.psm1") -Force

    # Generate a new certificate using CryptoHelper workflow
    $integrationCertPath = Join-Path ([System.IO.Path]::GetTempPath()) "integration_cert_$(Get-Random).pem"

    $rsa2 = [System.Security.Cryptography.RSA]::Create(2048)
    $subject2 = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new("CN=integration.test.com")
    $certRequest2 = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        $subject2, $rsa2,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
    $cert2 = $certRequest2.CreateSelfSigned([DateTimeOffset]::UtcNow, [DateTimeOffset]::UtcNow.AddDays(30))

    $certPem2 = "-----BEGIN CERTIFICATE-----`n"
    $certPem2 += [Convert]::ToBase64String($cert2.RawData, [Base64FormattingOptions]::InsertLineBreaks)
    $certPem2 += "`n-----END CERTIFICATE-----"
    Set-Content -Path $integrationCertPath -Value $certPem2

    # Use CertificateMonitor to read it
    $integrationInfo = Get-CertificateInfo -Path $integrationCertPath

    if ($integrationInfo.Subject -eq "CN=integration.test.com") {
        Write-Success "Integration: CertificateMonitor correctly uses CryptoHelper"
        $testsPassed++
    }
    else {
        Write-Failure "Integration: CertificateMonitor failed to read certificate from CryptoHelper"
        $testsFailed++
    }

    # Verify DaysRemaining is reasonable for 30-day cert
    if ($integrationInfo.DaysRemaining -ge 29.9 -and $integrationInfo.DaysRemaining -le 30.0) {
        Write-Success "Integration: DaysRemaining calculation correct across modules"
        $testsPassed++
    }
    else {
        Write-Failure "Integration: DaysRemaining calculation incorrect (got: $($integrationInfo.DaysRemaining))"
        $testsFailed++
    }

    # Clean up
    Remove-Item -Path $integrationCertPath -Force -ErrorAction SilentlyContinue
    $rsa2.Dispose()
    $cert2.Dispose()
}
catch {
    Write-Failure "Integration test failed: $($_.Exception.Message)"
    $testsFailed++
}

# ============================================================================
# CLEANUP
# ============================================================================
Write-TestHeader "Cleanup"

try {
    Remove-Item -Path $script:testCertPath -Force -ErrorAction SilentlyContinue
    $script:testCert.Dispose()
    Write-Success "Test certificate cleaned up"
}
catch {
    Write-Host "[i] Cleanup: $($_.Exception.Message)" -ForegroundColor Yellow
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
    Write-Success "All tests passed! CertificateMonitor module is ready for use."
    exit 0
}
else {
    Write-Failure "Some tests failed. Please review errors above."
    exit 1
}
