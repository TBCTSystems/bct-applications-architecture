# ==============================================================================
# CrlValidator.psm1 - Certificate Revocation List Validation Module
# ==============================================================================
# This module provides CRL download, caching, and certificate validation
# functions for ACME and EST agents.
#
# Functions:
#   - Get-CrlFromUrl: Downloads CRL from URL and caches locally
#   - Test-CertificateRevoked: Checks if certificate is revoked
#   - Get-CrlAge: Returns age of cached CRL
#   - Update-CrlCache: Updates cached CRL if stale
#   - Get-CrlInfo: Extracts information from CRL file
#
# Usage:
#   Import-Module ./CrlValidator.psm1
#   Update-CrlCache -Url "http://pki:9001/crl/ca.crl" -CachePath "/tmp/ca.crl"
#   Test-CertificateRevoked -CertificatePath "/certs/cert.pem" -CrlPath "/tmp/ca.crl"
# ==============================================================================

using namespace System.Security.Cryptography.X509Certificates

# ==============================================================================
# Get-CrlFromUrl
# ==============================================================================
# Downloads a CRL from a URL and saves it to a local cache file
#
# Parameters:
#   -Url: URL to download CRL from (http:// or https://)
#   -CachePath: Local file path to save CRL to
#   -TimeoutSeconds: HTTP request timeout (default: 30)
#
# Returns: $true if download successful, $false otherwise
# ==============================================================================
function Get-CrlFromUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$CachePath,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 30
    )

    try {
        Write-Verbose "[CRL] Downloading CRL from: $Url"

        # Create cache directory if it doesn't exist
        $cacheDir = Split-Path -Parent $CachePath
        if (-not (Test-Path $cacheDir)) {
            Write-Verbose "[CRL] Creating cache directory: $cacheDir"
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        }

        # Download CRL using Invoke-WebRequest
        $response = Invoke-WebRequest -Uri $Url -OutFile $CachePath -TimeoutSec $TimeoutSeconds -UseBasicParsing -ErrorAction Stop

        if (Test-Path $CachePath) {
            $fileSize = (Get-Item $CachePath).Length
            Write-Verbose "[CRL] Download successful - Size: $fileSize bytes"
            return $true
        } else {
            Write-Warning "[CRL] Download completed but file not found at: $CachePath"
            return $false
        }
    }
    catch {
        Write-Warning "[CRL] Failed to download CRL from ${Url}: $_"
        return $false
    }
}

# ==============================================================================
# Get-CrlAge
# ==============================================================================
# Returns the age of a cached CRL file in hours
#
# Parameters:
#   -CrlPath: Path to cached CRL file
#
# Returns: Age in hours as double, or -1 if file doesn't exist
# ==============================================================================
function Get-CrlAge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CrlPath
    )

    if (-not (Test-Path $CrlPath)) {
        Write-Verbose "[CRL] CRL file not found: $CrlPath"
        return -1.0
    }

    try {
        $lastWrite = (Get-Item $CrlPath).LastWriteTime
        $age = (Get-Date) - $lastWrite
        Write-Verbose "[CRL] CRL age: $($age.TotalHours) hours"
        return $age.TotalHours
    }
    catch {
        Write-Warning "[CRL] Failed to get CRL age: $_"
        return -1.0
    }
}

# ==============================================================================
# Get-CrlInfo
# ==============================================================================
# Extracts information from a CRL file
#
# Parameters:
#   -CrlPath: Path to CRL file (DER or PEM format)
#
# Returns: Hashtable with CRL information or $null on error
#   - Issuer: CRL issuer DN
#   - ThisUpdate: When CRL was issued
#   - NextUpdate: When next CRL will be issued
#   - RevokedCount: Number of revoked certificates
#   - RevokedSerials: Array of revoked certificate serial numbers
# ==============================================================================
function Get-CrlInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CrlPath
    )

    if (-not (Test-Path $CrlPath)) {
        Write-Warning "[CRL] CRL file not found: $CrlPath"
        return $null
    }

    try {
        # Read CRL file as bytes
        $crlBytes = [System.IO.File]::ReadAllBytes($CrlPath)

        # Try to parse as X509 CRL
        # Note: .NET doesn't have built-in CRL parsing, so we use openssl if available
        # For pure PowerShell, we'll parse basic information

        # Check if openssl is available
        $opensslAvailable = Get-Command openssl -ErrorAction SilentlyContinue

        if ($opensslAvailable) {
            Write-Verbose "[CRL] Using openssl to parse CRL"

            # Determine format (DER or PEM)
            $format = "DER"
            $firstLine = Get-Content $CrlPath -First 1 -ErrorAction SilentlyContinue
            if ($firstLine -match "BEGIN") {
                $format = "PEM"
            }

            # Parse CRL using openssl
            $crlText = & openssl crl -inform $format -in $CrlPath -noout -text 2>&1

            if ($LASTEXITCODE -ne 0) {
                Write-Warning "[CRL] openssl failed to parse CRL"
                return $null
            }

            # Extract information from openssl output
            $issuer = ""
            $thisUpdate = ""
            $nextUpdate = ""
            $revokedSerials = @()

            foreach ($line in $crlText) {
                if ($line -match "Issuer:\s*(.+)") {
                    $issuer = $Matches[1].Trim()
                }
                if ($line -match "Last Update:\s*(.+)") {
                    $thisUpdate = $Matches[1].Trim()
                }
                if ($line -match "Next Update:\s*(.+)") {
                    $nextUpdate = $Matches[1].Trim()
                }
                if ($line -match "Serial Number:\s*([0-9A-Fa-f]+)") {
                    $revokedSerials += $Matches[1].Trim()
                }
            }

            return @{
                Issuer        = $issuer
                ThisUpdate    = $thisUpdate
                NextUpdate    = $nextUpdate
                RevokedCount  = $revokedSerials.Count
                RevokedSerials = $revokedSerials
            }
        } else {
            Write-Warning "[CRL] openssl not available - returning basic info only"
            return @{
                Issuer        = "Unknown (openssl not available)"
                ThisUpdate    = "Unknown"
                NextUpdate    = "Unknown"
                RevokedCount  = 0
                RevokedSerials = @()
            }
        }
    }
    catch {
        Write-Warning "[CRL] Failed to parse CRL: $_"
        return $null
    }
}

# ==============================================================================
# Test-CertificateRevoked
# ==============================================================================
# Checks if a certificate is revoked according to a CRL
#
# Parameters:
#   -CertificatePath: Path to certificate file (PEM format)
#   -CrlPath: Path to CRL file (DER or PEM format)
#
# Returns: $true if certificate is revoked, $false if valid, $null on error
# ==============================================================================
function Test-CertificateRevoked {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CertificatePath,

        [Parameter(Mandatory = $true)]
        [string]$CrlPath
    )

    if (-not (Test-Path $CertificatePath)) {
        Write-Warning "[CRL] Certificate file not found: $CertificatePath"
        return $null
    }

    if (-not (Test-Path $CrlPath)) {
        Write-Warning "[CRL] CRL file not found: $CrlPath"
        return $null
    }

    try {
        Write-Verbose "[CRL] Checking if certificate is revoked: $CertificatePath"

        # Load certificate to get serial number
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificatePath)
        $certSerial = $cert.SerialNumber

        Write-Verbose "[CRL] Certificate serial number: $certSerial"

        # Get CRL information
        $crlInfo = Get-CrlInfo -CrlPath $CrlPath

        if ($null -eq $crlInfo) {
            Write-Warning "[CRL] Failed to parse CRL"
            return $null
        }

        Write-Verbose "[CRL] CRL contains $($crlInfo.RevokedCount) revoked certificates"

        # Check if certificate serial is in revoked list
        # Note: Serial numbers may have different formats (with/without colons, different case)
        # Normalize both for comparison
        $normalizedCertSerial = $certSerial -replace ':', '' -replace ' ', ''

        foreach ($revokedSerial in $crlInfo.RevokedSerials) {
            $normalizedRevokedSerial = $revokedSerial -replace ':', '' -replace ' ', ''

            if ($normalizedCertSerial -eq $normalizedRevokedSerial) {
                Write-Warning "[CRL] Certificate is REVOKED (serial: $certSerial)"
                return $true
            }
        }

        Write-Verbose "[CRL] Certificate is VALID (not in CRL)"
        return $false
    }
    catch {
        Write-Warning "[CRL] Failed to check certificate revocation status: $_"
        return $null
    }
}

# ==============================================================================
# Update-CrlCache
# ==============================================================================
# Updates cached CRL if it's stale or missing
#
# Parameters:
#   -Url: URL to download CRL from
#   -CachePath: Local file path for CRL cache
#   -MaxAgeHours: Maximum age of cached CRL before refresh (default: 24)
#
# Returns: Hashtable with update status and information
# ==============================================================================
function Update-CrlCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$CachePath,

        [Parameter(Mandatory = $false)]
        [double]$MaxAgeHours = 24.0
    )

    $result = @{
        Updated       = $false
        Downloaded    = $false
        CrlAge        = -1.0
        RevokedCount  = 0
        NextUpdate    = $null
        Error         = $null
    }

    try {
        # Check current CRL age
        $crlAge = Get-CrlAge -CrlPath $CachePath
        $result.CrlAge = $crlAge

        $needsUpdate = $false

        if ($crlAge -lt 0) {
            Write-Verbose "[CRL] CRL cache missing - downloading"
            $needsUpdate = $true
        } elseif ($crlAge -gt $MaxAgeHours) {
            Write-Verbose "[CRL] CRL cache stale (age: $crlAge hours, max: $MaxAgeHours) - downloading"
            $needsUpdate = $true
        } else {
            Write-Verbose "[CRL] CRL cache fresh (age: $crlAge hours)"
        }

        if ($needsUpdate) {
            $downloaded = Get-CrlFromUrl -Url $Url -CachePath $CachePath
            $result.Downloaded = $downloaded

            if ($downloaded) {
                $result.Updated = $true
                $result.CrlAge = 0.0
                Write-Verbose "[CRL] CRL cache updated successfully"
            } else {
                $result.Error = "Failed to download CRL"
                Write-Warning "[CRL] Failed to update CRL cache"
                return $result
            }
        }

        # Get CRL information
        $crlInfo = Get-CrlInfo -CrlPath $CachePath

        if ($null -ne $crlInfo) {
            $result.RevokedCount = $crlInfo.RevokedCount
            $result.NextUpdate = $crlInfo.NextUpdate
            Write-Verbose "[CRL] CRL info: $($crlInfo.RevokedCount) revoked certs, next update: $($crlInfo.NextUpdate)"
        }

        return $result
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-Warning "[CRL] Error updating CRL cache: $_"
        return $result
    }
}

# ==============================================================================
# Export module functions
# ==============================================================================
Export-ModuleMember -Function @(
    'Get-CrlFromUrl',
    'Get-CrlAge',
    'Get-CrlInfo',
    'Test-CertificateRevoked',
    'Update-CrlCache'
)
