#!/usr/bin/env pwsh

# Simple test for Posh-ACME Configuration Adapter core functionality
Write-Host "=== Posh-ACME Configuration Adapter Simple Test ===" -ForegroundColor Green

# Test basic module loading and URL construction
try {
    # Import the adapter
    Import-Module ./agents/acme/PoshAcmeConfigAdapter.psm1 -Force
    Write-Host "✓ PoshAcmeConfigAdapter module loaded successfully" -ForegroundColor Green

    # Test URL construction directly
    $testUrl = "https://pki:9000"
    $expectedUrl = "https://pki:9000/acme/acme/directory"

    # Call the helper function
    $directoryUrl = Get-AcmeDirectoryUrl -PkiUrl $testUrl

    if ($directoryUrl -eq $expectedUrl) {
        Write-Host "✓ URL construction test passed" -ForegroundColor Green
        Write-Host "  Input: $testUrl" -ForegroundColor White
        Write-Host "  Output: $directoryUrl" -ForegroundColor White
    } else {
        Write-Host "✗ URL construction test failed" -ForegroundColor Red
        Write-Host "  Expected: $expectedUrl" -ForegroundColor White
        Write-Host "  Actual: $directoryUrl" -ForegroundColor White
        exit 1
    }

    # Test state directory
    $testConfig = @{ dummy = "value" } # Config parameter is required but content doesn't matter
    $stateDir = Get-PoshAcmeStateDirectory -Config $testConfig
    $expectedDir = "/config/poshacme"

    if ($stateDir -eq $expectedDir) {
        Write-Host "✓ State directory test passed" -ForegroundColor Green
        Write-Host "  Directory: $stateDir" -ForegroundColor White
    } else {
        Write-Host "✗ State directory test failed" -ForegroundColor Red
        Write-Host "  Expected: $expectedDir" -ForegroundColor White
        Write-Host "  Actual: $stateDir" -ForegroundColor White
        exit 1
    }

    # Test function exports
    $functions = @(
        'Set-PoshAcmeServerFromConfig',
        'Initialize-PoshAcmeAccountFromConfig',
        'New-PoshAcmeOrderFromConfig',
        'Save-PoshAcmeCertificate'
    )

    Write-Host "`nTesting function exports:" -ForegroundColor Yellow
    foreach ($func in $functions) {
        if (Get-Command $func -ErrorAction SilentlyContinue) {
            Write-Host "✓ $func" -ForegroundColor Green
        } else {
            Write-Host "✗ $func" -ForegroundColor Red
            exit 1
        }
    }

    Write-Host "`n=== All adapter tests passed! ===" -ForegroundColor Green
    Write-Host "Configuration adapter is ready for integration" -ForegroundColor Cyan

} catch {
    Write-Host "✗ Test failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}