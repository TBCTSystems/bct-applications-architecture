#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Functional test script for FileOperations.psm1 module.

.DESCRIPTION
    Tests all three exported functions:
    - Write-FileAtomic: Atomic file write with temp file pattern
    - Set-FilePermissions: Cross-platform permission management
    - Test-FilePermissions: Permission validation

    This script should be run in a PowerShell environment (Linux, macOS, or Windows).

.EXAMPLE
    pwsh ./Test-FileOperations.ps1

.NOTES
    Prerequisites:
    - PowerShell Core 7.0+
    - Write permissions in /tmp (or current directory on Windows)
#>

#Requires -Version 7.0

# Import the module
$modulePath = Join-Path $PSScriptRoot "FileOperations.psm1"
Import-Module $modulePath -Force -ErrorAction Stop

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FileOperations.psm1 Functional Tests" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$testsPassed = 0
$testsFailed = 0

# Test directory
$testDir = if ($IsWindows) { $env:TEMP } else { "/tmp" }
$testFile = Join-Path $testDir "fileops_test_$(Get-Random).txt"

try {
    # ========================================
    # Test 1: Write-FileAtomic basic functionality
    # ========================================
    Write-Host "[Test 1] Write-FileAtomic - Basic write" -ForegroundColor Yellow
    try {
        $testContent = "Test content $(Get-Date -Format 'o')"
        Write-FileAtomic -Path $testFile -Content $testContent

        if (Test-Path $testFile) {
            $readContent = Get-Content -Path $testFile -Raw
            if ($readContent -eq $testContent) {
                Write-Host "  ✓ PASS: File written atomically" -ForegroundColor Green
                $testsPassed++
            } else {
                Write-Host "  ✗ FAIL: Content mismatch" -ForegroundColor Red
                $testsFailed++
            }
        } else {
            Write-Host "  ✗ FAIL: File not created" -ForegroundColor Red
            $testsFailed++
        }
    } catch {
        Write-Host "  ✗ FAIL: Exception: $($_.Exception.Message)" -ForegroundColor Red
        $testsFailed++
    }
    Write-Host ""

    # ========================================
    # Test 2: Write-FileAtomic - Overwrite existing file
    # ========================================
    Write-Host "[Test 2] Write-FileAtomic - Overwrite existing" -ForegroundColor Yellow
    try {
        $newContent = "Updated content $(Get-Date -Format 'o')"
        Write-FileAtomic -Path $testFile -Content $newContent

        $readContent = Get-Content -Path $testFile -Raw
        if ($readContent -eq $newContent) {
            Write-Host "  ✓ PASS: File overwritten atomically" -ForegroundColor Green
            $testsPassed++
        } else {
            Write-Host "  ✗ FAIL: Content not updated" -ForegroundColor Red
            $testsFailed++
        }
    } catch {
        Write-Host "  ✗ FAIL: Exception: $($_.Exception.Message)" -ForegroundColor Red
        $testsFailed++
    }
    Write-Host ""

    # ========================================
    # Test 3: Set-FilePermissions - Mode 0600
    # ========================================
    Write-Host "[Test 3] Set-FilePermissions - Mode 0600" -ForegroundColor Yellow
    try {
        Set-FilePermissions -Path $testFile -Mode "0600"

        if ($IsLinux -or $IsMacOS) {
            $actualMode = & stat -c '%a' $testFile 2>&1
            if ($actualMode -eq "600") {
                Write-Host "  ✓ PASS: Permissions set to 0600" -ForegroundColor Green
                $testsPassed++
            } else {
                Write-Host "  ✗ FAIL: Expected 600, got $actualMode" -ForegroundColor Red
                $testsFailed++
            }
        } elseif ($IsWindows) {
            Write-Host "  ⏭ SKIP: Windows permissions validation not implemented in test" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  ✗ FAIL: Exception: $($_.Exception.Message)" -ForegroundColor Red
        $testsFailed++
    }
    Write-Host ""

    # ========================================
    # Test 4: Test-FilePermissions - Validate 0600
    # ========================================
    Write-Host "[Test 4] Test-FilePermissions - Validate 0600" -ForegroundColor Yellow
    try {
        $isValid = Test-FilePermissions -Path $testFile -ExpectedMode "0600"

        if ($IsLinux -or $IsMacOS) {
            if ($isValid -eq $true) {
                Write-Host "  ✓ PASS: Permissions validated correctly (0600)" -ForegroundColor Green
                $testsPassed++
            } else {
                Write-Host "  ✗ FAIL: Validation returned false" -ForegroundColor Red
                $testsFailed++
            }
        } elseif ($IsWindows) {
            Write-Host "  ⏭ SKIP: Windows permissions validation not implemented in test" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  ✗ FAIL: Exception: $($_.Exception.Message)" -ForegroundColor Red
        $testsFailed++
    }
    Write-Host ""

    # ========================================
    # Test 5: Set-FilePermissions - Mode 0644
    # ========================================
    Write-Host "[Test 5] Set-FilePermissions - Mode 0644" -ForegroundColor Yellow
    try {
        Set-FilePermissions -Path $testFile -Mode "0644"

        if ($IsLinux -or $IsMacOS) {
            $actualMode = & stat -c '%a' $testFile 2>&1
            if ($actualMode -eq "644") {
                Write-Host "  ✓ PASS: Permissions set to 0644" -ForegroundColor Green
                $testsPassed++
            } else {
                Write-Host "  ✗ FAIL: Expected 644, got $actualMode" -ForegroundColor Red
                $testsFailed++
            }
        } elseif ($IsWindows) {
            Write-Host "  ⏭ SKIP: Windows permissions validation not implemented in test" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  ✗ FAIL: Exception: $($_.Exception.Message)" -ForegroundColor Red
        $testsFailed++
    }
    Write-Host ""

    # ========================================
    # Test 6: Test-FilePermissions - Negative test
    # ========================================
    Write-Host "[Test 6] Test-FilePermissions - Negative test (wrong mode)" -ForegroundColor Yellow
    try {
        # File should have 0644, test against 0600 (should return false)
        $isValid = Test-FilePermissions -Path $testFile -ExpectedMode "0600"

        if ($IsLinux -or $IsMacOS) {
            if ($isValid -eq $false) {
                Write-Host "  ✓ PASS: Correctly detected permission mismatch" -ForegroundColor Green
                $testsPassed++
            } else {
                Write-Host "  ✗ FAIL: Should have returned false" -ForegroundColor Red
                $testsFailed++
            }
        } elseif ($IsWindows) {
            Write-Host "  ⏭ SKIP: Windows permissions validation not implemented in test" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  ✗ FAIL: Exception: $($_.Exception.Message)" -ForegroundColor Red
        $testsFailed++
    }
    Write-Host ""

} finally {
    # Cleanup
    if (Test-Path $testFile) {
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
    }
}

# ========================================
# Summary
# ========================================
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tests Passed: $testsPassed" -ForegroundColor Green
Write-Host "Tests Failed: $testsFailed" -ForegroundColor Red
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "✓ All tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "✗ Some tests failed" -ForegroundColor Red
    exit 1
}
