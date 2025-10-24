#Requires -Version 5.1

<#
.SYNOPSIS
    Configuration management for Certificate Renewal Service
.DESCRIPTION
    Loads and validates configuration from YAML files using powershell-yaml module
#>

function Get-CertRenewalConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath
    )
    
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }
    
    # Import powershell-yaml module
    try {
        Import-Module powershell-yaml -ErrorAction Stop
    }
    catch {
        throw "Failed to load powershell-yaml module. Install it with: Install-Module -Name powershell-yaml -Scope CurrentUser"
    }
    
    # Load YAML configuration
    try {
        $configData = Get-Content $ConfigPath -Raw | ConvertFrom-Yaml
    }
    catch {
        throw "Failed to parse YAML configuration: $_"
    }
    
    # Validate required fields
    if (-not $configData.step_ca) {
        throw "Missing required configuration: step_ca"
    }
    
    # Set defaults
    if (-not $configData.check_interval_minutes) {
        $configData.check_interval_minutes = 30
    }
    
    if (-not $configData.log_level) {
        $configData.log_level = "INFO"
    }
    
    if (-not $configData.log_file) {
        $configData.log_file = "logs/cert_renewal.log"
    }
    
    if (-not $configData.cert_storage_path) {
        $configData.cert_storage_path = "certs"
    }
    
    if (-not $configData.renewal_threshold_percent) {
        $configData.renewal_threshold_percent = 33.0
    }
    
    # Step CA defaults
    if (-not $configData.step_ca.crl_enabled) {
        $configData.step_ca.crl_enabled = $true
    }
    
    if (-not $configData.step_ca.crl_cache_dir) {
        $configData.step_ca.crl_cache_dir = "certs/crl"
    }
    
    if (-not $configData.step_ca.crl_refresh_hours) {
        $configData.step_ca.crl_refresh_hours = 24
    }
    
    if (-not $configData.step_ca.crl_timeout_seconds) {
        $configData.step_ca.crl_timeout_seconds = 30
    }
    
    if (-not $configData.step_ca.protocol) {
        $configData.step_ca.protocol = "JWK"
    }
    
    if (-not $configData.certificates) {
        $configData.certificates = @()
    }
    
    return $configData
}
