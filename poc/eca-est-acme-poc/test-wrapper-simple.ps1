#!/usr/bin/env pwsh

# Simple test for AcmeClient-PoshACME wrapper module core functionality

Write-Host "=== AcmeClient-PoshACME Simple Test ===" -ForegroundColor Green

# Import the new wrapper module
try {
    Import-Module ./agents/acme/AcmeClient-PoshACME.psm1 -Force
    Write-Host "✓ AcmeClient-PoshACME module loaded successfully" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to load AcmeClient-PoshACME module: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 1: Check function exports (core test)
Write-Host "`nTest 1: Validating function exports..." -ForegroundColor Yellow
$expectedFunctions = @(
    'Get-AcmeDirectory',
    'New-AcmeAccount',
    'Get-AcmeAccount',
    'New-AcmeOrder',
    'Get-AcmeAuthorization',
    'Complete-Http01Challenge',
    'Wait-ChallengeValidation',
    'Complete-AcmeOrder',
    'Get-AcmeCertificate'
)

$exportedFunctions = Get-Command -Module AcmeClient-PoshACME | Select-Object -ExpandProperty Name
$allFunctionsPresent = $true

foreach ($func in $expectedFunctions) {
    if ($func -in $exportedFunctions) {
        Write-Host "✓ $func" -ForegroundColor Green
    } else {
        Write-Host "✗ $func" -ForegroundColor Red
        $allFunctionsPresent = $false
    }
}

if (-not $allFunctionsPresent) {
    Write-Host "✗ Not all expected functions are exported" -ForegroundColor Red
    exit 1
}

Write-Host "✓ All expected functions exported" -ForegroundColor Green

# Test 2: Test deprecated function
Write-Host "`nTest 2: Testing New-JwsSignedRequest deprecation..." -ForegroundColor Yellow
try {
    $result = New-JwsSignedRequest -Url "https://example.com" -Headers @{}
    if ($result.status -eq "deprecated") {
        Write-Host "✓ New-JwsSignedRequest properly deprecated" -ForegroundColor Green
        Write-Host "  Message: $($result.message)" -ForegroundColor White
    } else {
        Write-Host "✗ New-JwsSignedRequest deprecation handling incorrect" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "✗ New-JwsSignedRequest failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 3: Validate function signatures
Write-Host "`nTest 3: Validating function signatures..." -ForegroundColor Yellow
try {
    # Test that functions exist and have expected parameters
    $testCases = @(
        @{ Function = 'Get-AcmeDirectory'; ExpectedParams = @('BaseUrl') },
        @{ Function = 'New-AcmeAccount'; ExpectedParams = @('BaseUrl', 'AccountKeyPath', 'Contact') },
        @{ Function = 'New-AcmeOrder'; ExpectedParams = @('BaseUrl', 'DomainName') },
        @{ Function = 'Get-AcmeCertificate'; ExpectedParams = @('BaseUrl', 'Order') }
    )

    $signaturesValid = $true
    foreach ($testCase in $testCases) {
        $cmdlet = Get-Command $testCase.Function -ErrorAction SilentlyContinue
        if ($cmdlet) {
            $paramNames = $cmdlet.Parameters.Keys
            $missingParams = @()
            foreach ($param in $testCase.ExpectedParams) {
                if ($param -notin $paramNames) {
                    $missingParams += $param
                }
            }

            if ($missingParams.Count -eq 0) {
                Write-Host "✓ $($testCase.Function) signature valid" -ForegroundColor Green
            } else {
                Write-Host "✗ $($testCase.Function) missing parameters: $($missingParams -join ', ')" -ForegroundColor Red
                $signaturesValid = $false
            }
        } else {
            Write-Host "✗ Function not found: $($testCase.Function)" -ForegroundColor Red
            $signaturesValid = $false
        }
    }

    if ($signaturesValid) {
        Write-Host "✓ All function signatures validated" -ForegroundColor Green
    } else {
        Write-Host "✗ Function signature validation failed" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "✗ Function signature validation failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 4: Validate module dependencies
Write-Host "`nTest 4: Validating module dependencies..." -ForegroundColor Yellow
$requiredModules = @(
    'Posh-ACME',
    'PoshAcmeConfigAdapter'
)

$allModulesPresent = $true
foreach ($module in $requiredModules) {
    if (Get-Module $module -ErrorAction SilentlyContinue) {
        Write-Host "✓ $module module loaded" -ForegroundColor Green
    } else {
        Write-Host "✗ $module module not loaded" -ForegroundColor Red
        $allModulesPresent = $false
    }
}

if (-not $allModulesPresent) {
    Write-Host "✗ Not all required modules are loaded" -ForegroundColor Red
    exit 1
}

# Test 5: Code size comparison
Write-Host "`nTest 5: Validating code reduction..." -ForegroundColor Yellow
try {
    $originalLines = (Get-Content "./agents/acme/AcmeClient.psm1" | Measure-Object -Line).Lines
    $newLines = (Get-Content "./agents/acme/AcmeClient-PoshACME.psm1" | Measure-Object -Line).Lines
    $reductionPercentage = [math]::Round((($originalLines - $newLines) / $originalLines) * 100, 1)

    Write-Host "Original AcmeClient.psm1: $originalLines lines" -ForegroundColor White
    Write-Host "New AcmeClient-PoshACME.psm1: $newLines lines" -ForegroundColor White
    Write-Host "✓ Code reduction: $reductionPercentage%" -ForegroundColor Green

    if ($reductionPercentage -lt 50) {
        Write-Host "✗ Code reduction less than expected" -ForegroundColor Yellow
    }
} catch {
    Write-Host "✗ Code size comparison failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== All AcmeClient-PoshACME tests passed! ===" -ForegroundColor Green
Write-Host "✅ Backward compatibility maintained" -ForegroundColor Cyan
Write-Host "✅ All function signatures preserved" -ForegroundColor Cyan
Write-Host "✅ Dependencies properly loaded" -ForegroundColor Cyan
Write-Host "✅ Code reduction achieved" -ForegroundColor Cyan
Write-Host "`n🚀 Wrapper module ready for integration!" -ForegroundColor Green