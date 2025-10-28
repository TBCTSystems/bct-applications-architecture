#!/usr/bin/env pwsh

# Test script for Posh-ACME with step-ca integration
# This script tests basic Posh-ACME functionality with our step-ca instance

Write-Host "=== Posh-ACME Integration Test ===" -ForegroundColor Green

# Import Posh-ACME module
Import-Module Posh-ACME

Write-Host "Posh-ACME module loaded successfully" -ForegroundColor Cyan

# Set step-ca directory URL
$stepCaUrl = "https://pki:9000/acme/acme/directory"
Write-Host "Testing with step-ca URL: $stepCaUrl" -ForegroundColor Cyan

# Set custom POSHACME_HOME for testing
$env:POSHACME_HOME = "/tmp/poshacme-test"

# Configure Posh-ACME server
Write-Host "Configuring Posh-ACME server..." -ForegroundColor Yellow
Set-PAServer -DirectoryUrl $stepCaUrl -SkipCertificateCheck

# Test directory retrieval (implicitly through New-PAAccount)
Write-Host "Testing step-ca directory access..." -ForegroundColor Yellow

try {
    # Test creating a new ACME account
    $account = New-PAAccount -AcceptTOS
    Write-Host "✓ ACME account created successfully" -ForegroundColor Green
    Write-Host "  Account ID: $($account.ID)" -ForegroundColor White
    Write-Host "  Status: $($account.status)" -ForegroundColor White

    # Test getting account information
    $accountInfo = Get-PAAccount
    Write-Host "✓ Account information retrieved successfully" -ForegroundColor Green
    Write-Host "  Account ID: $($accountInfo.ID)" -ForegroundColor White
    Write-Host "  Contact: $($accountInfo.contact)" -ForegroundColor White

    # Test creating a new order
    Write-Host "Testing order creation..." -ForegroundColor Yellow
    $order = New-PAOrder -Domain "test.example.com"
    Write-Host "✓ Order created successfully" -ForegroundColor Green
    Write-Host "  Order ID: $($order.ID)" -ForegroundColor White
    Write-Host "  Status: $($order.status)" -ForegroundColor White
    Write-Host "  Domains: $($order.identifiers | ForEach-Object { $_.value })" -ForegroundColor White

    # Clean up test account
    Write-Host "Cleaning up test account..." -ForegroundColor Yellow
    Remove-PAAccount -ID $accountInfo.ID -Force
    Write-Host "✓ Test account removed" -ForegroundColor Green

} catch {
    Write-Host "✗ Test failed with error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}

Write-Host "=== All Posh-ACME tests passed! ===" -ForegroundColor Green