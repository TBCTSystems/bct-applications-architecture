#!/usr/bin/env pwsh

# Test script for Posh-ACME Configuration Adapter
# This script validates that our adapter maintains backward compatibility

Write-Host "=== Posh-ACME Configuration Adapter Test ===" -ForegroundColor Green

# Import required modules
Import-Module ./agents/common/Logger.psm1 -Force
Import-Module ./agents/common/ConfigManager.psm1 -Force
Import-Module ./agents/acme/PoshAcmeConfigAdapter.psm1 -Force

Write-Host "Modules loaded successfully" -ForegroundColor Cyan

# Test 1: Load existing configuration
Write-Host "Test 1: Loading existing configuration..." -ForegroundColor Yellow
try {
    $config = Read-AgentConfig -ConfigFilePath "./agents/acme/config.yaml"
    Write-Host "✓ Configuration loaded successfully" -ForegroundColor Green
    Write-Host "  PKI URL: $($config.pki_url)" -ForegroundColor White
    Write-Host "  Domain: $($config.domain_name)" -ForegroundColor White
    Write-Host "  Cert Path: $($config.cert_path)" -ForegroundColor White
    Write-Host "  Key Path: $($config.key_path)" -ForegroundColor White
} catch {
    Write-Host "✗ Configuration loading failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 2: URL Construction
Write-Host "`nTest 2: Testing ACME directory URL construction..." -ForegroundColor Yellow
try {
    $directoryUrl = Get-AcmeDirectoryUrl -PkiUrl $config.pki_url
    $expectedUrl = "$($config.pki_url)/acme/acme/directory"
    if ($directoryUrl -eq $expectedUrl) {
        Write-Host "✓ Directory URL construction correct" -ForegroundColor Green
        Write-Host "  URL: $directoryUrl" -ForegroundColor White
    } else {
        Write-Host "✗ Directory URL construction incorrect" -ForegroundColor Red
        Write-Host "  Expected: $expectedUrl" -ForegroundColor White
        Write-Host "  Actual: $directoryUrl" -ForegroundColor White
        exit 1
    }
} catch {
    Write-Host "✗ URL construction failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 3: State Directory Configuration
Write-Host "`nTest 3: Testing state directory configuration..." -ForegroundColor Yellow
try {
    $env:POSHACME_HOME = "/tmp/posh-acme-adapter-state"
    if (Test-Path $env:POSHACME_HOME) {
        Remove-Item -Path $env:POSHACME_HOME -Recurse -Force -ErrorAction SilentlyContinue
    }

    $stateDir = Get-PoshAcmeStateDirectory -Config $config
    $expectedDir = $env:POSHACME_HOME
    if ($stateDir -eq $expectedDir) {
        Write-Host "✓ State directory configuration correct" -ForegroundColor Green
        Write-Host "  Directory: $stateDir" -ForegroundColor White
    } else {
        Write-Host "✗ State directory configuration incorrect" -ForegroundColor Red
        Write-Host "  Expected: $expectedDir" -ForegroundColor White
        Write-Host "  Actual: $stateDir" -ForegroundColor White
        exit 1
    }
    Remove-Item Env:POSHACME_HOME -ErrorAction SilentlyContinue
    if (Test-Path $expectedDir) {
        Remove-Item -Path $expectedDir -Recurse -Force -ErrorAction SilentlyContinue
    }
} catch {
    Write-Host "✗ State directory configuration failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 4: Environment Variable Override
Write-Host "`nTest 4: Testing environment variable overrides..." -ForegroundColor Yellow
try {
    # Test with environment variable
    $env:TEST_PKI_URL = "https://test-pki:8443"
    $testConfig = Read-AgentConfig -ConfigFilePath "./agents/acme/config.yaml" -EnvVarPrefixes @("TEST_")

    if ($testConfig.pki_url -eq "https://test-pki:8443") {
        Write-Host "✓ Environment variable override working" -ForegroundColor Green
        Write-Host "  Override URL: $($testConfig.pki_url)" -ForegroundColor White
    } else {
        Write-Host "✗ Environment variable override failed" -ForegroundColor Red
        Write-Host "  Expected: https://test-pki:8443" -ForegroundColor White
        Write-Host "  Actual: $($testConfig.pki_url)" -ForegroundColor White
        exit 1
    }

    # Clean up
    Remove-Item Env:TEST_PKI_URL -ErrorAction SilentlyContinue
} catch {
    Write-Host "✗ Environment variable override test failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 5: Configuration Validation
Write-Host "`nTest 5: Testing configuration validation..." -ForegroundColor Yellow
try {
    # Test missing required field
    $invalidConfig = @{
        cert_path = "/certs/test.crt"
        key_path = "/certs/test.key"
        # Missing pki_url
    }

    try {
        $result = New-PoshAcmeOrderFromConfig -Config $invalidConfig
        Write-Host "✗ Configuration validation should have failed" -ForegroundColor Red
        exit 1
    } catch {
        if ($_.Exception.Message -like "*domain_name*") {
            Write-Host "✓ Configuration validation working correctly" -ForegroundColor Green
            Write-Host "  Expected validation error occurred" -ForegroundColor White
        } else {
            Write-Host "✗ Unexpected validation error: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }
} catch {
    Write-Host "✗ Configuration validation test failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 6: Adapter Function Exports
Write-Host "`nTest 6: Testing adapter function exports..." -ForegroundColor Yellow
try {
    $expectedFunctions = @(
        'Set-PoshAcmeServerFromConfig',
        'Initialize-PoshAcmeAccountFromConfig',
        'New-PoshAcmeOrderFromConfig',
        'Save-PoshAcmeCertificate',
        'Invoke-PoshAcmeChallenge',
        'Get-PoshAcmeAccountInfo',
        'Remove-PoshAcmeAccount'
    )

    $exportedFunctions = Get-Command -Module PoshAcmeConfigAdapter | Select-Object -ExpandProperty Name

    foreach ($func in $expectedFunctions) {
        if ($func -in $exportedFunctions) {
            Write-Host "✓ Function exported: $func" -ForegroundColor Green
        } else {
            Write-Host "✗ Function missing: $func" -ForegroundColor Red
            exit 1
        }
    }
} catch {
    Write-Host "✗ Function export test failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== All Posh-ACME Configuration Adapter tests passed! ===" -ForegroundColor Green
Write-Host "`n✅ Configuration adapter is ready for integration with agent.ps1" -ForegroundColor Cyan
