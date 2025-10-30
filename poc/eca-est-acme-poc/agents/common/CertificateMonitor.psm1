<#
.SYNOPSIS
    PowerShell module for certificate file monitoring and expiry checking.

.DESCRIPTION
    CertificateMonitor.psm1 provides functions for monitoring X.509 certificate files
    on the file system and calculating certificate lifetime metrics. This module is used
    by ACME and EST protocol agents to determine when certificates need renewal.

    Key capabilities:
    - Certificate file existence checking
    - Certificate information extraction (Subject, Issuer, validity dates, etc.)
    - Lifetime elapsed percentage calculation
    - Days remaining until expiry calculation

    This module builds on top of CryptoHelper.psm1 and provides higher-level monitoring
    functions for certificate lifecycle management workflows.

.NOTES
    Module Name: CertificateMonitor
    Author: ECA Project
    Requires: PowerShell Core 7.0+
    Dependencies: CryptoHelper.psm1 (for certificate parsing)

    Design Principles:
    - All time calculations use UTC for consistency
    - All percentage values rounded to 2 decimal places
    - Graceful error handling for missing/invalid files
    - Separation of concerns (file I/O vs. calculation logic)

    Cross-Platform Compatibility:
    - Tested on Linux (Alpine 3.19 in Docker)
    - Uses .NET Core cross-platform APIs
    - No platform-specific file system dependencies

.LINK
    Documentation: docs/02_Iteration_I1.md (Task I1.T9)
    Architecture: docs/01_Plan_Overview_and_Setup.md (Section 2.3)
    Dependency: agents/common/CryptoHelper.psm1
#>

#Requires -Version 7.0

using namespace System.Security.Cryptography.X509Certificates

# Import CryptoHelper module for certificate parsing
Import-Module (Join-Path $PSScriptRoot 'CryptoHelper.psm1') -Force

# ============================================================================
# PUBLIC FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Checks if a certificate file exists at the specified path.

.DESCRIPTION
    Performs a simple file system existence check for a certificate file.
    This function is used as a pre-validation step before attempting to parse
    certificate files, allowing agents to handle missing certificates gracefully.

    Unlike Read-Certificate from CryptoHelper, this function does not attempt
    to parse the file content - it only checks if the file exists.

.PARAMETER Path
    Absolute or relative path to the certificate file to check.

.OUTPUTS
    System.Boolean
    - $true: File exists at the specified path
    - $false: File does not exist or path is invalid

.EXAMPLE
    if (Test-CertificateExists -Path "/certs/server/server.crt") {
        Write-Host "Certificate file found"
    } else {
        Write-Host "Certificate file missing - needs initial enrollment"
    }

.EXAMPLE
    $certPath = "./my-cert.pem"
    $exists = Test-CertificateExists -Path $certPath
    # Returns $true or $false without throwing exceptions

.NOTES
    - Never throws exceptions (fail-safe design)
    - Returns $false for any error condition (missing file, invalid path, permission denied)
    - Does not validate certificate content (use Read-Certificate for that)
    - Useful for initial enrollment detection in agent startup logic
#>
function Test-CertificateExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    try {
        # Use Test-Path to check file existence
        return Test-Path -Path $Path -PathType Leaf
    }
    catch {
        # Return false on any error (e.g., permission denied, invalid path)
        return $false
    }
}

<#
.SYNOPSIS
    Calculates the percentage of a certificate's lifetime that has elapsed.

.DESCRIPTION
    Computes the percentage of certificate lifetime elapsed using the formula:

        LifetimeElapsedPercent = ((Now - NotBefore) / (NotAfter - NotBefore)) * 100

    Where:
    - Now: Current UTC time
    - NotBefore: Certificate valid from date
    - NotAfter: Certificate valid until date

    The result is rounded to 2 decimal places for consistency. Values can exceed 100%
    for expired certificates or be negative for certificates not yet valid.

    This function operates on a parsed certificate object and does not perform file I/O,
    making it suitable for repeated calculations without filesystem overhead.

.PARAMETER Certificate
    The X509Certificate2 object to evaluate. Must have valid NotBefore and NotAfter dates.

.OUTPUTS
    System.Double
    Percentage of lifetime elapsed, rounded to 2 decimal places.
    - 0.00: Certificate just issued (NotBefore == Now)
    - 50.00: Certificate halfway through its lifetime
    - 100.00: Certificate exactly at expiry (NotAfter == Now)
    - >100.00: Certificate expired (Now > NotAfter)
    - <0.00: Certificate not yet valid (Now < NotBefore)

.EXAMPLE
    $cert = Read-Certificate -Path "/certs/server.crt"
    $elapsed = Get-CertificateLifetimeElapsed -Certificate $cert
    Write-Host "Certificate is $elapsed% through its lifetime"

.EXAMPLE
    $cert = Read-Certificate -Path "/certs/server.crt"
    $elapsed = Get-CertificateLifetimeElapsed -Certificate $cert
    if ($elapsed -ge 75.00) {
        Write-Host "Certificate needs renewal (threshold: 75%)"
    }

.NOTES
    - Uses UTC time for all calculations
    - Result rounded to 2 decimal places using banker's rounding
    - Throws exception if certificate has invalid dates (NotAfter <= NotBefore)
    - Thread-safe (no shared state)
    - Formula matches Test-CertificateExpiry from CryptoHelper for consistency
#>
function Get-CertificateLifetimeElapsed {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNull()]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    try {
        # Get current UTC time
        $now = [DateTime]::UtcNow

        # Calculate total certificate lifetime in seconds
        $totalLifetimeSeconds = ($Certificate.NotAfter - $Certificate.NotBefore).TotalSeconds

        # Handle edge case: Invalid certificate with NotAfter <= NotBefore
        if ($totalLifetimeSeconds -le 0) {
            throw "Invalid certificate: NotAfter must be greater than NotBefore"
        }

        # Calculate elapsed lifetime in seconds
        $elapsedSeconds = ($now - $Certificate.NotBefore).TotalSeconds

        # Calculate elapsed percentage
        $elapsedPercentage = ($elapsedSeconds / $totalLifetimeSeconds) * 100

        # Round to 2 decimal places for consistent reporting
        $elapsedPercentage = [Math]::Round($elapsedPercentage, 2)

        return $elapsedPercentage
    }
    catch {
        throw "Failed to calculate certificate lifetime elapsed: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Reads a certificate file and returns comprehensive information as a hashtable.

.DESCRIPTION
    Parses an X.509 certificate from a PEM file and extracts key information into
    a structured hashtable. This function combines certificate parsing, property
    extraction, and lifetime calculations into a single convenient operation.

    The returned hashtable contains:
    - Subject: Subject Distinguished Name (e.g., "CN=example.com")
    - Issuer: Issuer Distinguished Name (e.g., "CN=Intermediate CA")
    - NotBefore: Certificate valid from date (DateTime, UTC)
    - NotAfter: Certificate valid until date (DateTime, UTC)
    - SerialNumber: Unique certificate identifier (hex string)
    - DaysRemaining: Days until expiry (Double, rounded to 2 decimals, can be negative)
    - LifetimeElapsedPercent: Percentage of lifetime elapsed (Double, 0.00-100.00+)

    This function is the primary entry point for certificate monitoring agents to
    gather all necessary information for renewal decision-making.

.PARAMETER Path
    Absolute or relative path to the PEM-encoded certificate file.
    File must contain a valid X.509 certificate.

.OUTPUTS
    System.Collections.Hashtable
    Hashtable with the following keys (all keys always present):
    - Subject (String): Certificate subject DN
    - Issuer (String): Certificate issuer DN
    - NotBefore (DateTime): Valid from date (UTC)
    - NotAfter (DateTime): Valid until date (UTC)
    - SerialNumber (String): Serial number in hex format
    - DaysRemaining (Double): Days until expiry, rounded to 2 decimals
    - LifetimeElapsedPercent (Double): Lifetime elapsed percentage, rounded to 2 decimals

.EXAMPLE
    $info = Get-CertificateInfo -Path "/certs/server/server.crt"
    Write-Host "Subject: $($info.Subject)"
    Write-Host "Issuer: $($info.Issuer)"
    Write-Host "Days Remaining: $($info.DaysRemaining)"
    Write-Host "Lifetime Elapsed: $($info.LifetimeElapsedPercent)%"

.EXAMPLE
    $info = Get-CertificateInfo -Path "/certs/client/client.crt"
    if ($info.LifetimeElapsedPercent -ge 75) {
        Write-Host "Certificate needs renewal!"
        # Trigger EST re-enrollment workflow
    }

.EXAMPLE
    try {
        $info = Get-CertificateInfo -Path "/certs/missing.crt"
    } catch {
        Write-Host "Certificate file not found - performing initial enrollment"
    }

.NOTES
    - Throws exception if file does not exist
    - Throws exception if file is not a valid PEM certificate
    - All DateTime values in UTC timezone
    - DaysRemaining can be negative for expired certificates
    - LifetimeElapsedPercent can exceed 100% for expired certificates
    - SerialNumber format: Uppercase hex string with no separators
    - Uses CryptoHelper's Read-Certificate for parsing
#>
function Get-CertificateInfo {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    try {
        # Check if certificate file exists (fail-fast)
        if (-not (Test-CertificateExists -Path $Path)) {
            throw "Certificate file not found: $Path"
        }

        # Read and parse certificate using CryptoHelper
        $cert = Read-Certificate -Path $Path

        # Get current UTC time for calculations
        $now = [DateTime]::UtcNow

        # Calculate days remaining until expiry
        $daysRemaining = ($cert.NotAfter - $now).TotalDays
        $daysRemaining = [Math]::Round($daysRemaining, 2)

        # Calculate lifetime elapsed percentage
        $lifetimeElapsedPercent = Get-CertificateLifetimeElapsed -Certificate $cert

        # Build and return hashtable with all required fields
        return @{
            Subject                = $cert.Subject
            Issuer                 = $cert.Issuer
            NotBefore              = $cert.NotBefore
            NotAfter               = $cert.NotAfter
            SerialNumber           = $cert.SerialNumber
            DaysRemaining          = $daysRemaining
            LifetimeElapsedPercent = $lifetimeElapsedPercent
        }
    }
    catch {
        throw "Failed to get certificate information from '$Path': $($_.Exception.Message)"
    }
}

# ============================================================================
# MODULE EXPORTS
# ============================================================================

# Export only public functions
Export-ModuleMember -Function @(
    'Test-CertificateExists',
    'Get-CertificateLifetimeElapsed',
    'Get-CertificateInfo'
)
