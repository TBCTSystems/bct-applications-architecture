<#
.SYNOPSIS
    PowerShell module providing cryptographic operations for certificate lifecycle management.

.DESCRIPTION
    CryptoHelper.psm1 provides a set of functions for cryptographic operations required by
    ACME and EST protocol agents. This module wraps .NET System.Security.Cryptography classes
    to provide:
    - RSA key pair generation (2048-bit)
    - PKCS#10 Certificate Signing Request (CSR) creation with Subject Alternative Names
    - X.509 certificate parsing from PEM files
    - Private key export to PKCS#8 PEM format
    - Certificate expiry validation with configurable renewal thresholds

    All cryptographic operations use industry-standard algorithms and formats:
    - RSA 2048-bit keys (minimum secure key size)
    - PKCS#8 encoding for private keys (modern standard)
    - PKCS#10 format for CSRs
    - PEM encoding for all outputs (Base64 with headers)
    - SHA256WithRSA signatures

.NOTES
    Module Name: CryptoHelper
    Author: ECA Project
    Requires: PowerShell Core 7.0+
    Dependencies: .NET System.Security.Cryptography (built-in)

    Security Considerations:
    - Private keys are never logged or transmitted
    - Keys are generated locally using cryptographically secure RNG
    - PKCS#8 format provides standardized, secure key encoding
    - All functions include comprehensive error handling

    Cross-Platform Compatibility:
    - Tested on Linux (Alpine 3.19 in Docker)
    - Uses .NET Core cross-platform cryptography APIs
    - No platform-specific dependencies

.LINK
    Documentation: agents/common/README_CryptoHelper.md
    Architecture: docs/02_Architecture_Overview.md
#>

#Requires -Version 7.0

using namespace System.Security.Cryptography
using namespace System.Security.Cryptography.X509Certificates

# ============================================================================
# INTERNAL HELPER FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Converts DER-encoded bytes to PEM format with appropriate headers.

.DESCRIPTION
    Internal helper function that encodes binary DER data as Base64 with line breaks
    and wraps it with PEM BEGIN/END markers. Used by multiple functions to avoid
    code duplication.

.PARAMETER DerBytes
    The DER-encoded binary data to convert.

.PARAMETER Label
    The PEM label to use in headers (e.g., "PRIVATE KEY", "CERTIFICATE REQUEST").

.OUTPUTS
    System.String - PEM-formatted string with headers and Base64-encoded content.

.EXAMPLE
    ConvertTo-PemFormat -DerBytes $keyBytes -Label "PRIVATE KEY"
    Returns: -----BEGIN PRIVATE KEY-----\nMIIE...\n-----END PRIVATE KEY-----
#>
function ConvertTo-PemFormat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [byte[]]$DerBytes,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Label
    )

    try {
        # Convert DER bytes to Base64 with line breaks (64 characters per line per RFC 7468)
        $base64 = [Convert]::ToBase64String($DerBytes, [Base64FormattingOptions]::InsertLineBreaks)

        # Wrap with PEM headers
        $pem = "-----BEGIN $Label-----`n$base64`n-----END $Label-----"

        return $pem
    }
    catch {
        throw "Failed to convert to PEM format: $($_.Exception.Message)"
    }
}

# ============================================================================
# PUBLIC FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Generates a new RSA 2048-bit key pair.

.DESCRIPTION
    Creates a new RSA key pair with 2048-bit key size using .NET cryptographic
    random number generator. Returns the private key in PKCS#8 PEM format.

    The generated key pair includes both private and public keys, but only the
    private key is returned (public key can be derived from it). The private key
    is encoded in PKCS#8 format, which is the modern standard for private key storage.

    Security Note: Private keys are generated using cryptographically secure random
    number generation and should be stored with restrictive file permissions (0600).

.OUTPUTS
    System.String - Private key in PKCS#8 PEM format.
    Format: -----BEGIN PRIVATE KEY-----\n[Base64]\n-----END PRIVATE KEY-----

.EXAMPLE
    $privateKeyPem = New-RSAKeyPair
    # Returns: -----BEGIN PRIVATE KEY-----
    #          MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC...
    #          -----END PRIVATE KEY-----

.EXAMPLE
    $privateKeyPem = New-RSAKeyPair
    Set-Content -Path "/certs/server/server.key" -Value $privateKeyPem
    # Save private key to file for later use

.NOTES
    - Key size: 2048 bits (minimum secure size for RSA as of 2024)
    - Encoding: PKCS#8 (modern standard, preferred over legacy PKCS#1)
    - Output format: PEM with line breaks every 64 characters
    - Generation time: Approximately 100-200ms on typical hardware
#>
function New-RSAKeyPair {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        # Generate RSA 2048-bit key pair
        $rsa = [System.Security.Cryptography.RSA]::Create(2048)

        # Export private key in PKCS#8 format (DER-encoded bytes)
        $privateKeyBytes = $rsa.ExportPkcs8PrivateKey()

        # Convert to PEM format
        $privateKeyPem = ConvertTo-PemFormat -DerBytes $privateKeyBytes -Label "PRIVATE KEY"

        return $privateKeyPem
    }
    catch {
        throw "Failed to generate RSA key pair: $($_.Exception.Message)"
    }
    finally {
        # Clean up cryptographic resources
        if ($null -ne $rsa) {
            $rsa.Dispose()
        }
    }
}

<#
.SYNOPSIS
    Exports an RSA private key to PKCS#8 PEM format.

.DESCRIPTION
    Exports an existing RSA key object to PKCS#8 PEM format. This function is useful
    when you have an RSA object (e.g., loaded from a certificate or created elsewhere)
    and need to export it as a PEM string for storage or transmission.

    The output uses PKCS#8 encoding, which is the modern standard for private key
    storage and is compatible with most certificate management tools.

.PARAMETER RsaKey
    The RSA key object to export. Must be a valid System.Security.Cryptography.RSA object
    containing a private key.

.OUTPUTS
    System.String - Private key in PKCS#8 PEM format.

.EXAMPLE
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $pemKey = Export-PrivateKey -RsaKey $rsa
    # Exports the RSA object to PEM format

.EXAMPLE
    $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new("cert.pfx", "password")
    $pemKey = Export-PrivateKey -RsaKey $cert.GetRSAPrivateKey()
    # Export private key from a certificate

.NOTES
    - Requires RSA object with private key component
    - Output format: PKCS#8 PEM
    - Security: Never log or transmit the output over insecure channels
#>
function Export-PrivateKey {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNull()]
        [System.Security.Cryptography.RSA]$RsaKey
    )

    try {
        # Export private key in PKCS#8 format
        $privateKeyBytes = $RsaKey.ExportPkcs8PrivateKey()

        # Convert to PEM format
        $privateKeyPem = ConvertTo-PemFormat -DerBytes $privateKeyBytes -Label "PRIVATE KEY"

        return $privateKeyPem
    }
    catch {
        throw "Failed to export private key: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Creates a PKCS#10 Certificate Signing Request (CSR) with Subject DN and SANs.

.DESCRIPTION
    Generates a PKCS#10 Certificate Signing Request containing:
    - Subject Distinguished Name (e.g., "CN=example.com, O=Example Corp")
    - Subject Alternative Names (DNS names)
    - Public key from the provided RSA key pair
    - Self-signature to prove private key possession

    The CSR is returned in PEM format and can be submitted to a Certificate Authority
    (CA) via ACME or EST protocols to obtain a signed certificate.

    The CSR is self-signed using SHA256WithRSA, which proves possession of the
    corresponding private key without revealing the key itself.

.PARAMETER SubjectDN
    Subject Distinguished Name as a string. Common formats:
    - "CN=example.com"
    - "CN=example.com, O=Example Corp, C=US"
    Must follow X.500 DN syntax.

.PARAMETER SubjectAlternativeNames
    Array of DNS names to include in the Subject Alternative Name extension.
    Each entry will be encoded as a DNS name in the SAN extension.
    Can be empty array if no SANs are needed.

.PARAMETER RsaKey
    The RSA key pair to use. The public key will be included in the CSR,
    and the private key will be used to sign the CSR.

.OUTPUTS
    System.String - Certificate Signing Request in PKCS#10 PEM format.
    Format: -----BEGIN CERTIFICATE REQUEST-----\n[Base64]\n-----END CERTIFICATE REQUEST-----

.EXAMPLE
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $csr = New-CertificateRequest -SubjectDN "CN=example.com" -SubjectAlternativeNames @("example.com", "www.example.com") -RsaKey $rsa
    # Creates CSR for example.com with two SANs

.EXAMPLE
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $csr = New-CertificateRequest -SubjectDN "CN=client-device-001, O=Example Corp" -SubjectAlternativeNames @() -RsaKey $rsa
    # Creates CSR without SANs (useful for EST enrollment)

.NOTES
    - CSR format: PKCS#10 (RFC 2986)
    - Signature algorithm: SHA256WithRSA
    - SAN extension OID: 2.5.29.17 (id-ce-subjectAltName)
    - The CSR is self-signed to prove key possession
#>
function New-CertificateRequest {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$SubjectDN,

        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateNotNull()]
        [string[]]$SubjectAlternativeNames = @(),

        [Parameter(Mandatory = $true, Position = 2)]
        [ValidateNotNull()]
        [System.Security.Cryptography.RSA]$RsaKey
    )

    try {
        # Parse subject DN string to X500DistinguishedName object
        $subject = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new($SubjectDN)

        # Create certificate request with subject and RSA public key
        $certRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            $subject,
            $RsaKey,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        )

        # Add Subject Alternative Names extension if provided
        if ($SubjectAlternativeNames.Count -gt 0) {
            $sanBuilder = [System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()

            foreach ($san in $SubjectAlternativeNames) {
                $sanBuilder.AddDnsName($san)
            }

            $certRequest.CertificateExtensions.Add($sanBuilder.Build())
        }

        # Create signing request (self-signed to prove key possession)
        $csrBytes = $certRequest.CreateSigningRequest()

        # Convert to PEM format
        $csrPem = ConvertTo-PemFormat -DerBytes $csrBytes -Label "CERTIFICATE REQUEST"

        return $csrPem
    }
    catch {
        throw "Failed to create certificate request: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Reads and parses an X.509 certificate from a PEM file.

.DESCRIPTION
    Reads a PEM-encoded X.509 certificate from the file system and returns an
    X509Certificate2 object. The returned object provides access to all certificate
    properties including:
    - Subject and Issuer Distinguished Names
    - Validity period (NotBefore, NotAfter)
    - Serial number
    - Public key
    - Extensions (SANs, Key Usage, etc.)

    This function is used by certificate monitoring and validation workflows to
    parse certificates obtained from ACME or EST servers.

.PARAMETER Path
    Absolute or relative path to the PEM-encoded certificate file.
    File must contain a valid X.509 certificate with BEGIN/END CERTIFICATE markers.

.OUTPUTS
    System.Security.Cryptography.X509Certificates.X509Certificate2
    Certificate object with accessible properties:
    - Subject: Subject Distinguished Name
    - Issuer: Issuer Distinguished Name
    - NotBefore: Certificate valid from (DateTime)
    - NotAfter: Certificate valid until (DateTime)
    - SerialNumber: Unique certificate identifier (hex string)
    - Thumbprint: SHA-1 hash of certificate (hex string)

.EXAMPLE
    $cert = Read-Certificate -Path "/certs/server/server.crt"
    Write-Host "Subject: $($cert.Subject)"
    Write-Host "Expires: $($cert.NotAfter)"
    # Reads certificate and displays basic info

.EXAMPLE
    $cert = Read-Certificate -Path "./my-cert.pem"
    $needsRenewal = Test-CertificateExpiry -Certificate $cert -ThresholdPercentage 75
    # Read certificate and check if renewal is needed

.NOTES
    - Supports PEM format only (not DER binary)
    - File must be readable by current user
    - Returns fully parsed certificate object (not just raw bytes)
    - Does not validate certificate chain (use .Verify() method separately)
#>
function Read-Certificate {
    [CmdletBinding()]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    try {
        # Verify file exists
        if (-not (Test-Path -Path $Path -PathType Leaf)) {
            throw "Certificate file not found: $Path"
        }

        # PowerShell's X509Certificate2 constructor cannot parse PEM text directly
        # and ImportFromPem() is not available in all .NET versions
        # Solution: Use openssl to convert PEM to DER format, then load DER bytes

        # Create temporary DER file
        $tempDerFile = [System.IO.Path]::GetTempFileName()
        try {
            # Convert PEM to DER using openssl
            $null = & openssl x509 -in $Path -outform DER -out $tempDerFile 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "openssl x509 conversion failed with exit code $LASTEXITCODE"
            }

            # Read DER bytes and create X509Certificate2
            $certBytes = [System.IO.File]::ReadAllBytes($tempDerFile)
            $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certBytes)
        }
        finally {
            # Clean up temporary file
            if (Test-Path $tempDerFile) {
                Remove-Item -Path $tempDerFile -ErrorAction SilentlyContinue
            }
        }

        return $cert
    }
    catch {
        throw "Failed to read certificate from '$Path': $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Checks if a certificate needs renewal based on lifetime elapsed percentage.

.DESCRIPTION
    Evaluates whether a certificate should be renewed by calculating the percentage
    of its lifetime that has elapsed and comparing it to a threshold.

    Calculation:
    - Lifetime elapsed = (Current time - NotBefore) / (NotAfter - NotBefore) * 100
    - Returns true if elapsed >= threshold, false otherwise

    This function is used by certificate monitoring agents to trigger automated
    renewal workflows before certificates expire.

.PARAMETER Certificate
    The X509Certificate2 object to evaluate. Must have valid NotBefore and NotAfter dates.

.PARAMETER ThresholdPercentage
    Renewal threshold as a percentage (1-100).
    Common values:
    - 75%: Renew when 75% of lifetime has elapsed (recommended)
    - 80%: Renew when 80% of lifetime has elapsed
    - 90%: Renew when 90% of lifetime has elapsed (aggressive)

.OUTPUTS
    System.Boolean
    - $true: Certificate should be renewed (elapsed >= threshold)
    - $false: Certificate does not need renewal yet

.EXAMPLE
    $cert = Read-Certificate -Path "/certs/server.crt"
    $needsRenewal = Test-CertificateExpiry -Certificate $cert -ThresholdPercentage 75
    if ($needsRenewal) {
        Write-Host "Certificate needs renewal!"
    }

.EXAMPLE
    $cert = Read-Certificate -Path "/certs/server.crt"
    $isExpired = Test-CertificateExpiry -Certificate $cert -ThresholdPercentage 100
    # Check if certificate is fully expired (elapsed >= 100%)

.NOTES
    - Uses UTC time for all calculations
    - Threshold comparison: elapsed >= threshold (inclusive)
    - Edge case: If certificate is already expired (NotAfter < now), returns true
    - Edge case: If elapsed exactly equals threshold, returns true (renewal needed)
#>
function Test-CertificateExpiry {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNull()]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateRange(1, 100)]
        [int]$ThresholdPercentage
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

        # Round to 2 decimal places for consistent comparison
        $elapsedPercentage = [Math]::Round($elapsedPercentage, 2)

        # Return true if renewal needed (elapsed >= threshold)
        return $elapsedPercentage -ge $ThresholdPercentage
    }
    catch {
        throw "Failed to evaluate certificate expiry: $($_.Exception.Message)"
    }
}

# ============================================================================
# MODULE EXPORTS
# ============================================================================

# Export only public functions (internal helpers remain private)
Export-ModuleMember -Function @(
    'New-RSAKeyPair',
    'New-CertificateRequest',
    'Read-Certificate',
    'Export-PrivateKey',
    'Test-CertificateExpiry'
)
