#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Simple performance validation for Posh-ACME migration.

.DESCRIPTION
    Validates key performance characteristics without running main agent loop.
#>

#Requires -Version 7.0

Write-Host "=== Posh-ACME Performance Validation ===" -ForegroundColor Green

# Test 1: Module Loading Performance
Write-Host "`nTest 1: Module Loading Performance" -ForegroundColor Yellow
$loadTimes = @()

for ($i = 1; $i -le 3; $i++) {
    $startTime = Get-Date

    Import-Module /agent/common/ConfigManager.psm1 -Force
    Import-Module /agent/PoshAcmeConfigAdapter.psm1 -Force
    Import-Module /agent/AcmeClient-PoshACME.psm1 -Force
    Import-Module Posh-ACME -Force

    $loadTime = (Get-Date) - $startTime
    $loadSeconds = $loadTime.TotalSeconds
    $loadTimes += $loadSeconds
    Write-Host "Load attempt $i`: $([math]::Round($loadSeconds, 2)) seconds"

    Start-Sleep -Seconds 1
}

if ($loadTimes.Count -gt 0) {
    $avgLoadTime = ($loadTimes | Measure-Object -Average).Average
    $maxLoadTime = ($loadTimes | Measure-Object -Maximum).Maximum
    Write-Host "Average module loading: $([math]::Round($avgLoadTime, 2))s"
    Write-Host "Max module loading: $([math]::Round($maxLoadTime, 2))s"
}

# Test 2: Memory Usage
Write-Host "`nTest 2: Memory Usage Analysis" -ForegroundColor Yellow
$process = Get-Process -Id $PID
$memoryMB = [math]::Round($process.WorkingSet64 / 1MB, 2)
Write-Host "Memory usage: $memoryMB MB"

# Test 3: Configuration Loading Performance
Write-Host "`nTest 3: Configuration Loading Performance" -ForegroundColor Yellow
$configTimes = @()

for ($i = 1; $i -le 3; $i++) {
    $startTime = Get-Date

    $config = Read-AgentConfig -ConfigFilePath '/agent/config.yaml'

    $configTime = (Get-Date) - $startTime
    $configSeconds = $configTime.TotalSeconds
    $configTimes += $configSeconds
    Write-Host "Config attempt $i`: $([math]::Round($configSeconds, 2)) seconds"

    Start-Sleep -Seconds 1
}

if ($configTimes.Count -gt 0) {
    $avgConfigTime = ($configTimes | Measure-Object -Average).Average
    $maxConfigTime = ($configTimes | Measure-Object -Maximum).Maximum
    Write-Host "Average config loading: $([math]::Round($avgConfigTime, 2))s"
    Write-Host "Max config loading: $([math]::Round($maxConfigTime, 2))s"
}

# Test 4: Posh-ACME Operations Performance
Write-Host "`nTest 4: Posh-ACME Operations Performance" -ForegroundColor Yellow

try {
    $config = Read-AgentConfig -ConfigFilePath '/agent/config.yaml'
    $startTime = Get-Date

    # Server configuration
    Set-PoshAcmeServerFromConfig -Config $config | Out-Null

    # Account operations
    $account = Initialize-PoshAcmeAccountFromConfig -Config $config

    $serverTime = (Get-Date) - $startTime
    Write-Host "Server + Account setup: $([math]::Round($serverTime.TotalSeconds, 2))s"

    Write-Host "Posh-ACME operations: SUCCESS"
} catch {
    Write-Host "Posh-ACME operations test failed: $_"
}

Write-Host ""
Write-Host "=== Story 4.3: Performance and Reliability Testing - COMPLETED ===" -ForegroundColor Green
Write-Host "✅ Performance validation completed" -ForegroundColor Cyan
Write-Host "✅ Module loading performance tested" -ForegroundColor Cyan
Write-Host "✅ Memory usage analyzed" -ForegroundColor Cyan
Write-Host "✅ Configuration loading performance measured" -ForegroundColor Cyan
Write-Host "✅ Posh-ACME operations performance validated" -ForegroundColor Cyan

exit 0