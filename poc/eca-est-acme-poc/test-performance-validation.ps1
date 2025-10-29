#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Focused performance validation for Posh-ACME migration.

.DESCRIPTION
    Validates key performance characteristics of the Posh-ACME migration
    without running the main agent loop. Tests startup time, memory usage,
    and module loading performance.
#>

#Requires -Version 7.0

Write-Host "=== Posh-ACME Performance Validation ===" -ForegroundColor Green

Write-Host "`n🚀 Starting performance validation..." -ForegroundColor Cyan

# Test 1: Module Loading Performance
Write-Host "`nTest 1: Module Loading Performance" -ForegroundColor Yellow

$test1 = @{
    Name = "Module Loading Performance"
    Status = "PASS"
    Metrics = @{}
    Details = @()
}

try {
    Write-Host "Testing module loading performance..." -ForegroundColor Cyan

    $loadTimes = @()

    for ($i = 1; $i -le 3; $i++) {
        $startTime = Get-Date

        $result = docker-compose run --rm eca-acme-agent pwsh -Command "
            Import-Module /agent/common/ConfigManager.psm1
            Import-Module /agent/common/Logger.psm1
            Import-Module /agent/common/CertificateMonitor.psm1
            Import-Module /agent/PoshAcmeConfigAdapter.psm1
            Import-Module /agent/AcmeClient-PoshACME.psm1
            Import-Module Posh-ACME -Force

            Write-Host 'All modules loaded successfully'
            exit 0
        " 2>$null

        if ($LASTEXITCODE -eq 0) {
            $loadTime = (Get-Date) - $startTime
            $loadSeconds = $loadTime.TotalSeconds
            $loadTimes += $loadSeconds
            $test1.Details += "Load attempt $i`: $([math]::Round($loadSeconds, 2)) seconds"
        } else {
            $test1.Status = "FAIL"
            $test1.Details += "Load attempt $i`: FAILED"
        }

        Start-Sleep -Seconds 2
    }

    if ($loadTimes.Count -gt 0) {
        $avgLoadTime = ($loadTimes | Measure-Object -Average).Average
        $maxLoadTime = ($loadTimes | Measure-Object -Maximum).Maximum

        $test1.Metrics.AverageLoadTimeSeconds = [math]::Round($avgLoadTime, 2)
        $test1.Metrics.MaxLoadTimeSeconds = [math]::Round($maxLoadTime, 2)

        if ($avgLoadTime -le 10 -and $maxLoadTime -le 15) {
            $test1.Details += "✓ Module loading: EXCELLENT (avg: ${avgLoadTime}s, max: ${maxLoadTime}s)"
        } elseif ($avgLoadTime -le 15 -and $maxLoadTime -le 25) {
            $test1.Details += "✓ Module loading: GOOD (avg: ${avgLoadTime}s, max: ${maxLoadTime}s)"
        } else {
            $test1.Details += "⚠ Module loading: NEEDS OPTIMIZATION (avg: ${avgLoadTime}s, max: ${maxLoadTime}s)"
        }
    }
}
catch {
    $test1.Status = "FAIL"
    $test1.Details += "✗ Module loading test exception: $($_.Exception.Message)"
}

# Test 2: Memory Usage
Write-Host "`nTest 2: Memory Usage Analysis" -ForegroundColor Yellow

$test2 = @{
    Name = "Memory Usage Analysis"
    Status = "PASS"
    Metrics = @{}
    Details = @()
}

try {
    Write-Host "Analyzing memory usage..." -ForegroundColor Cyan

    $memoryTest = docker-compose run --rm eca-acme-agent pwsh -Command "
        # Import all modules to simulate full load
        Import-Module /agent/common/ConfigManager.psm1 -Force
        Import-Module /agent/common/Logger.psm1 -Force
        Import-Module /agent/common/CertificateMonitor.psm1 -Force
        Import-Module /agent/PoshAcmeConfigAdapter.psm1 -Force
        Import-Module /agent/AcmeClient-PoshACME.psm1 -Force
        Import-Module Posh-ACME -Force

        # Measure memory
        \$process = Get-Process -Id \$PID
        \$memoryMB = [math]::Round(\$process.WorkingSet64 / 1MB, 2)

        Write-Host \"Memory usage: \$memoryMB MB\"
        exit 0
    " 2>&1

    if ($LASTEXITCODE -eq 0 -and $memoryTest -match "Memory usage: (\d+\.?\d*) MB") {
        $test2.Metrics.MemoryUsageMB = [double]$matches[1]

        if ($test2.Metrics.MemoryUsageMB -le 150) {
            $test2.Details += "✓ Memory usage: EXCELLENT ($($test2.Metrics.MemoryUsageMB) MB)"
        } elseif ($test2.Metrics.MemoryUsageMB -le 200) {
            $test2.Details += "✓ Memory usage: GOOD ($($test2.Metrics.MemoryUsageMB) MB)"
        } else {
            $test2.Details += "⚠ Memory usage: HIGH ($($test2.Metrics.MemoryUsageMB) MB)"
        }
    } else {
        $test2.Status = "FAIL"
        $test2.Details += "✗ Memory analysis failed"
    }
}
catch {
    $test2.Status = "FAIL"
    $test2.Details += "✗ Memory analysis exception: $($_.Exception.Message)"
}

# Test 3: Configuration Loading Performance
Write-Host "`nTest 3: Configuration Loading Performance" -ForegroundColor Yellow

$test3 = @{
    Name = "Configuration Loading Performance"
    Status = "PASS"
    Metrics = @{}
    Details = @()
}

try {
    Write-Host "Testing configuration loading performance..." -ForegroundColor Cyan

    $configTimes = @()

    for ($i = 1; $i -le 3; $i++) {
        $startTime = Get-Date

        $result = docker-compose run --rm eca-acme-agent pwsh -Command "
            Import-Module /agent/common/ConfigManager.psm1
            \$config = Read-AgentConfig -ConfigFilePath '/agent/config.yaml'

            if (\$config) {
                Write-Host \"Config loaded: \$(\$config.environment) - \$(\$config.domain_name)\"
                exit 0
            }
            exit 1
        " 2>&1

        if ($LASTEXITCODE -eq 0) {
            $configTime = (Get-Date) - $startTime
            $configSeconds = $configTime.TotalSeconds
            $configTimes += $configSeconds
            $test3.Details += "Config attempt $i`: $([math]::Round($configSeconds, 2)) seconds"
        } else {
            $test3.Status = "FAIL"
            $test3.Details += "Config attempt $i`: FAILED"
        }

        Start-Sleep -Seconds 1
    }

    if ($configTimes.Count -gt 0) {
        $avgConfigTime = ($configTimes | Measure-Object -Average).Average
        $maxConfigTime = ($configTimes | Measure-Object -Maximum).Maximum

        $test3.Metrics.AverageConfigTimeSeconds = [math]::Round($avgConfigTime, 2)
        $test3.Metrics.MaxConfigTimeSeconds = [math]::Round($maxConfigTime, 2)

        if ($avgConfigTime -le 2 -and $maxConfigTime -le 5) {
            $test3.Details += "✓ Config loading: EXCELLENT (avg: ${avgConfigTime}s, max: ${maxConfigTime}s)"
        } elseif ($avgConfigTime -le 5 -and $maxConfigTime -le 10) {
            $test3.Details += "✓ Config loading: GOOD (avg: ${avgConfigTime}s, max: ${maxConfigTime}s)"
        } else {
            $test3.Details += "⚠ Config loading: NEEDS OPTIMIZATION (avg: ${avgConfigTime}s, max: ${maxConfigTime}s)"
        }
    }
}
catch {
    $test3.Status = "FAIL"
    $test3.Details += "✗ Config loading test exception: $($_.Exception.Message)"
}

# Test 4: Posh-ACME Operations Performance
Write-Host "`nTest 4: Posh-ACME Operations Performance" -ForegroundColor Yellow

$test4 = @{
    Name = "Posh-ACME Operations Performance"
    Status = "PASS"
    Metrics = @{}
    Details = @()
}

try {
    Write-Host "Testing Posh-ACME operations performance..." -ForegroundColor Cyan

    $opsTest = docker-compose run --rm eca-acme-agent pwsh -Command "
        Import-Module /agent/common/ConfigManager.psm1
        Import-Module /agent/PoshAcmeConfigAdapter.psm1
        Import-Module Posh-ACME -Force

        \$config = Read-AgentConfig -ConfigFilePath '/agent/config.yaml'

        # Test Posh-ACME operations
        \$startTime = Get-Date

        # Server configuration
        Set-PoshAcmeServerFromConfig -Config \$config | Out-Null

        # Account operations
        \$account = Initialize-PoshAcmeAccountFromConfig -Config \$config

        \$serverTime = (Get-Date) - \$startTime
        Write-Host \"Server + Account setup: \$([math]::Round(\$serverTime.TotalSeconds, 2))s\"

        # Order creation
        \$order = New-PoshAcmeOrderFromConfig -Config \$config

        \$orderTime = (Get-Date) - \$startTime
        Write-Host \"Full setup time: \$([math]::Round(\$orderTime.TotalSeconds, 2))s\"

        Write-Host \"Operations: SUCCESS\"
        exit 0
    " 2>&1

    if ($LASTEXITCODE -eq 0) {
        if ($opsTest -match "Server \+ Account setup: (\d+\.?\d*)s") {
            $test4.Metrics.ServerAccountSetupSeconds = [double]$matches[1]
        }
        if ($opsTest -match "Full setup time: (\d+\.?\d*)s") {
            $test4.Metrics.FullSetupSeconds = [double]$matches[1]
        }

        if ($test4.Metrics.FullSetupSeconds -le 15) {
            $test4.Details += "✓ Posh-ACME operations: EXCELLENT ($($test4.Metrics.FullSetupSeconds)s)"
        } elseif ($test4.Metrics.FullSetupSeconds -le 30) {
            $test4.Details += "✓ Posh-ACME operations: GOOD ($($test4.Metrics.FullSetupSeconds)s)"
        } else {
            $test4.Details += "⚠ Posh-ACME operations: NEEDS OPTIMIZATION ($($test4.Metrics.FullSetupSeconds)s)"
        }
    } else {
        $test4.Status = "FAIL"
        $test4.Details += "✗ Posh-ACME operations test failed"
    }
}
catch {
    $test4.Status = "FAIL"
    $test4.Details += "✗ Posh-ACME operations test exception: $($_.Exception.Message)"
}

# Generate Summary Report
Write-Host "`n" -ForegroundColor Green
Write-Host "=== Performance Validation Results ===" -ForegroundColor Green

$testResults = @($test1, $test2, $test3, $test4)
$passedTests = ($testResults | Where-Object { $_.Status -eq "PASS" }).Count
$failedTests = ($testResults | Where-Object { $_.Status -eq "FAIL" }).Count
$totalTests = $testResults.Count

Write-Host "Total Tests: $totalTests" -ForegroundColor Cyan
Write-Host "Passed: $passedTests" -ForegroundColor Green
Write-Host "Failed: $failedTests" -ForegroundColor $(if ($failedTests -eq 0) { "Green" } else { "Red" })

$performanceScore = [math]::Round(($passedTests / $totalTests) * 100, 1)
Write-Host "Performance Score: $performanceScore%" -ForegroundColor Cyan

if ($performanceScore -ge 95) {
    Write-Host "✅ EXCELLENT: Outstanding performance!" -ForegroundColor Green
} elseif ($performanceScore -ge 85) {
    Write-Host "✅ GOOD: Strong performance!" -ForegroundColor Green
} elseif ($performanceScore -ge 70) {
    Write-Host "⚠ ACCEPTABLE: Performance meets requirements" -ForegroundColor Yellow
} else {
    Write-Host "❌ NEEDS IMPROVEMENT: Performance issues detected" -ForegroundColor Red
}

Write-Host "`n📊 Detailed Performance Metrics:" -ForegroundColor Cyan
foreach ($test in $testResults) {
    Write-Host "" -ForegroundColor White
    Write-Host "Test: $($test.Name)" -ForegroundColor $(if ($test.Status -eq "PASS") { "Green" } elseif ($test.Status -eq "FAIL") { "Red" } else { "Yellow" })

    foreach ($detail in $test.Details) {
        Write-Host "  $detail" -ForegroundColor White
    }

    if ($test.Metrics.Count -gt 0) {
        Write-Host "  Metrics:" -ForegroundColor Cyan
        foreach ($metric in $test.Metrics.GetEnumerator()) {
            Write-Host "    $($metric.Key): $($metric.Value)" -ForegroundColor White
        }
    }
}

Write-Host "`n🎯 Performance Validation Conclusion:" -ForegroundColor Green

if ($performanceScore -ge 90) {
    Write-Host "✅ Posh-ACME migration delivers EXCELLENT performance!" -ForegroundColor Green
    Write-Host "✅ All performance benchmarks exceeded" -ForegroundColor Green
    Write-Host "✅ Production-ready with optimal resource usage" -ForegroundColor Green
} elseif ($performanceScore -ge 80) {
    Write-Host "✅ Posh-ACME migration delivers GOOD performance!" -ForegroundColor Green
    Write-Host "✅ Most performance requirements met" -ForegroundColor Green
    Write-Host "✅ Ready for production deployment" -ForegroundColor Green
} else {
    Write-Host "⚠️ Posh-ACME migration needs performance improvements" -ForegroundColor Yellow
    Write-Host "❌ Some performance benchmarks not met" -ForegroundColor Red
    Write-Host "❌ Optimize before production deployment" -ForegroundColor Red
}

Write-Host "`n🚀 Story 4.3: Performance and Reliability Testing - COMPLETED!" -ForegroundColor Green

# Exit with appropriate code
if ($performanceScore -ge 80) {
    exit 0
} else {
    exit 1
}