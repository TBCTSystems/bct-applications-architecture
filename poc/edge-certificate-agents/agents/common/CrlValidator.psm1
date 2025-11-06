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
        Write-LogInfo "Downloading CRL" -Context @{
            operation = "crl_download"
            crl_url = $Url
            cache_path = $CachePath
            timeout_seconds = $TimeoutSeconds
            status = "started"
        }

        # Create cache directory if it doesn't exist
        $cacheDir = Split-Path -Parent $CachePath
        if (-not (Test-Path $cacheDir)) {
            Write-LogInfo "Creating CRL cache directory" -Context @{
                operation = "crl_cache_setup"
                cache_dir = $cacheDir
            }
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        }

        # Download CRL using Invoke-WebRequest
        $response = Invoke-WebRequest -Uri $Url -OutFile $CachePath -TimeoutSec $TimeoutSeconds -UseBasicParsing -ErrorAction Stop

        if (Test-Path $CachePath) {
            $fileSize = (Get-Item $CachePath).Length
            Write-LogInfo "CRL download successful" -Context @{
                operation = "crl_download"
                crl_url = $Url
                cache_path = $CachePath
                file_size_bytes = $fileSize
                status = "success"
            }
            return $true
        } else {
            Write-LogWarn "CRL download completed but file not found" -Context @{
                operation = "crl_download"
                crl_url = $Url
                cache_path = $CachePath
                status = "file_not_found"
            }
            return $false
        }
    }
    catch {
        Write-LogError "Failed to download CRL" -Context @{
            operation = "crl_download"
            crl_url = $Url
            cache_path = $CachePath
            error = $_.Exception.Message
            status = "failed"
        }
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
        Write-LogInfo "CRL file not found" -Context @{
            operation = "crl_age_check"
            crl_path = $CrlPath
            status = "not_found"
        }
        return -1.0
    }

    try {
        $lastWrite = (Get-Item $CrlPath).LastWriteTime
        $age = (Get-Date) - $lastWrite
        Write-LogInfo "CRL age checked" -Context @{
            operation = "crl_age_check"
            crl_path = $CrlPath
            age_hours = [math]::Round($age.TotalHours, 2)
            last_write = $lastWrite.ToString("yyyy-MM-ddTHH:mm:ssZ")
            status = "success"
        }
        return $age.TotalHours
    }
    catch {
        Write-LogError "Failed to get CRL age" -Context @{
            operation = "crl_age_check"
            crl_path = $CrlPath
            error = $_.Exception.Message
            status = "failed"
        }
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
        Write-LogWarn "CRL file not found for parsing" -Context @{
            operation = "crl_parse"
            crl_path = $CrlPath
            status = "not_found"
        }
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
            Write-LogInfo "Parsing CRL using openssl" -Context @{
                operation = "crl_parse"
                crl_path = $CrlPath
                parser = "openssl"
            }

            # Determine format (DER or PEM)
            $format = "DER"
            $firstLine = Get-Content $CrlPath -First 1 -ErrorAction SilentlyContinue
            if ($firstLine -match "BEGIN") {
                $format = "PEM"
            }

            # Parse CRL using openssl
            $crlText = & openssl crl -inform $format -in $CrlPath -noout -text 2>&1

            if ($LASTEXITCODE -ne 0) {
                Write-LogError "openssl failed to parse CRL" -Context @{
                    operation = "crl_parse"
                    crl_path = $CrlPath
                    parser = "openssl"
                    exit_code = $LASTEXITCODE
                    status = "failed"
                }
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

            Write-LogInfo "CRL parsed successfully" -Context @{
                operation = "crl_parse"
                crl_path = $CrlPath
                issuer = $issuer
                this_update = $thisUpdate
                next_update = $nextUpdate
                revoked_count = $revokedSerials.Count
                revoked_serials = ($revokedSerials -join ",")
                status = "success"
            }

            return @{
                Issuer        = $issuer
                ThisUpdate    = $thisUpdate
                NextUpdate    = $nextUpdate
                RevokedCount  = $revokedSerials.Count
                RevokedSerials = $revokedSerials
            }
        } else {
            Write-LogWarn "openssl not available for CRL parsing" -Context @{
                operation = "crl_parse"
                crl_path = $CrlPath
                parser = "openssl"
                status = "unavailable"
            }
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
        Write-LogError "Failed to parse CRL" -Context @{
            operation = "crl_parse"
            crl_path = $CrlPath
            error = $_.Exception.Message
            status = "failed"
        }
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
        Write-LogWarn "Certificate file not found for revocation check" -Context @{
            operation = "certificate_revocation_check"
            cert_path = $CertificatePath
            status = "cert_not_found"
        }
        return $null
    }

    if (-not (Test-Path $CrlPath)) {
        Write-LogWarn "CRL file not found for revocation check" -Context @{
            operation = "certificate_revocation_check"
            cert_path = $CertificatePath
            crl_path = $CrlPath
            status = "crl_not_found"
        }
        return $null
    }

    try {
        Write-LogInfo "Checking certificate revocation status" -Context @{
            operation = "certificate_revocation_check"
            cert_path = $CertificatePath
            crl_path = $CrlPath
            status = "started"
        }

        # Load certificate to get serial number
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificatePath)
        $certSerial = $cert.SerialNumber
        $certThumbprint = $cert.Thumbprint
        $certSubject = $cert.Subject

        Write-LogInfo "Certificate loaded for revocation check" -Context @{
            operation = "certificate_revocation_check"
            cert_serial = $certSerial
            cert_thumbprint = $certThumbprint
            cert_subject = $certSubject
        }

        # Get CRL information
        $crlInfo = Get-CrlInfo -CrlPath $CrlPath

        if ($null -eq $crlInfo) {
            Write-LogError "Failed to parse CRL for revocation check" -Context @{
                operation = "certificate_revocation_check"
                cert_serial = $certSerial
                crl_path = $CrlPath
                status = "crl_parse_failed"
            }
            return $null
        }

        Write-LogInfo "CRL loaded for revocation check" -Context @{
            operation = "certificate_revocation_check"
            cert_serial = $certSerial
            crl_revoked_count = $crlInfo.RevokedCount
            crl_issuer = $crlInfo.Issuer
        }

        # Check if certificate serial is in revoked list
        # Note: Serial numbers may have different formats (with/without colons, different case)
        # Normalize both for comparison
        $normalizedCertSerial = $certSerial -replace ':', '' -replace ' ', ''

        foreach ($revokedSerial in $crlInfo.RevokedSerials) {
            $normalizedRevokedSerial = $revokedSerial -replace ':', '' -replace ' ', ''

            if ($normalizedCertSerial -eq $normalizedRevokedSerial) {
                Write-LogWarn "Certificate is REVOKED" -Context @{
                    operation = "certificate_revocation_check"
                    cert_serial = $certSerial
                    cert_thumbprint = $certThumbprint
                    cert_subject = $certSubject
                    crl_path = $CrlPath
                    revoked = $true
                    status = "revoked"
                }
                return $true
            }
        }

        Write-LogInfo "Certificate is VALID (not in CRL)" -Context @{
            operation = "certificate_revocation_check"
            cert_serial = $certSerial
            cert_thumbprint = $certThumbprint
            cert_subject = $certSubject
            crl_path = $CrlPath
            crl_revoked_count = $crlInfo.RevokedCount
            revoked = $false
            status = "valid"
        }
        return $false
    }
    catch {
        Write-LogError "Failed to check certificate revocation status" -Context @{
            operation = "certificate_revocation_check"
            cert_path = $CertificatePath
            crl_path = $CrlPath
            error = $_.Exception.Message
            status = "failed"
        }
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
            Write-LogInfo "CRL cache missing, download required" -Context @{
                operation = "crl_cache_update"
                crl_url = $Url
                cache_path = $CachePath
                status = "cache_missing"
            }
            $needsUpdate = $true
        } elseif ($crlAge -gt $MaxAgeHours) {
            Write-LogInfo "CRL cache stale, download required" -Context @{
                operation = "crl_cache_update"
                crl_url = $Url
                cache_path = $CachePath
                age_hours = [math]::Round($crlAge, 2)
                max_age_hours = $MaxAgeHours
                status = "cache_stale"
            }
            $needsUpdate = $true
        } else {
            Write-LogInfo "CRL cache fresh, no update needed" -Context @{
                operation = "crl_cache_update"
                cache_path = $CachePath
                age_hours = [math]::Round($crlAge, 2)
                max_age_hours = $MaxAgeHours
                status = "cache_fresh"
            }
        }

        if ($needsUpdate) {
            $downloaded = Get-CrlFromUrl -Url $Url -CachePath $CachePath
            $result.Downloaded = $downloaded

            if ($downloaded) {
                $result.Updated = $true
                $result.CrlAge = 0.0
                Write-LogInfo "CRL cache updated successfully" -Context @{
                    operation = "crl_cache_update"
                    crl_url = $Url
                    cache_path = $CachePath
                    status = "updated"
                }
            } else {
                $result.Error = "Failed to download CRL"
                Write-LogError "Failed to update CRL cache" -Context @{
                    operation = "crl_cache_update"
                    crl_url = $Url
                    cache_path = $CachePath
                    error = "Download failed"
                    status = "failed"
                }
                return $result
            }
        }

        # Get CRL information
        $crlInfo = Get-CrlInfo -CrlPath $CachePath

        if ($null -ne $crlInfo) {
            $result.RevokedCount = $crlInfo.RevokedCount
            $result.NextUpdate = $crlInfo.NextUpdate
            Write-LogInfo "CRL cache information retrieved" -Context @{
                operation = "crl_cache_update"
                cache_path = $CachePath
                revoked_count = $crlInfo.RevokedCount
                next_update = $crlInfo.NextUpdate
                issuer = $crlInfo.Issuer
                status = "success"
            }
        }

        return $result
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-LogError "Error updating CRL cache" -Context @{
            operation = "crl_cache_update"
            crl_url = $Url
            cache_path = $CachePath
            error = $_.Exception.Message
            status = "failed"
        }
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
