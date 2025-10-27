<#
.SYNOPSIS
    PowerShell module implementing ACME protocol account management for automated certificate lifecycle.

.DESCRIPTION
    AcmeClient.psm1 provides ACME (Automatic Certificate Management Environment) protocol
    account management functions for the ECA-ACME agent. This module implements:
    - ACME directory discovery and caching
    - Account creation and retrieval with RSA key pair generation
    - JWS (JSON Web Signature) request authentication
    - Nonce management for replay protection

    This module integrates with Smallstep step-ca as the Certificate Authority, using
    ACME v2 protocol (RFC 8555) for automated certificate issuance and renewal.

    All ACME requests are authenticated using JWS signatures with account private keys,
    providing cryptographic proof of request origin without shared secrets.

.NOTES
    Module Name: AcmeClient
    Author: ECA Project
    Requires: PowerShell Core 7.0+
    Dependencies:
        - agents/common/Logger.psm1 (structured logging)
        - agents/common/CryptoHelper.psm1 (RSA key generation)
        - agents/common/FileOperations.psm1 (atomic file writes, permissions)

    Security Considerations:
    - Account private keys stored with 0600 permissions at /config/acme-account.key
    - JWS signatures provide request integrity and authentication
    - Nonces prevent replay attacks
    - All network communication uses HTTPS with step-ca

.LINK
    Documentation: docs/api/acme_protocol_reference.md
    RFC 8555: ACME Protocol Specification
    Architecture: docs/ARCHITECTURE.md

.EXAMPLE
    Import-Module ./agents/acme/AcmeClient.psm1
    $directory = Get-AcmeDirectory -BaseUrl "https://pki:9000"
    $account = New-AcmeAccount -BaseUrl "https://pki:9000" -Contact @("mailto:admin@example.com")
#>

#Requires -Version 7.0

using namespace System.Security.Cryptography

# ============================================================================
# MODULE DEPENDENCIES
# ============================================================================

# Import required modules for this module's operation.
# Resolve the shared module directory by checking common PoC layouts:
#   1. Container runtime:      /agent/common/*.psm1
#   2. Repository checkout:    agents/common/*.psm1
$commonDirCandidates = @()

$localCommon = Join-Path $PSScriptRoot 'common'
if (Test-Path (Join-Path $localCommon 'Logger.psm1')) {
    $commonDirCandidates += $localCommon
}

$parentDir = Split-Path $PSScriptRoot -Parent
if (-not [string]::IsNullOrWhiteSpace($parentDir)) {
    $parentCommon = Join-Path $parentDir 'common'
    if (Test-Path (Join-Path $parentCommon 'Logger.psm1')) {
        $commonDirCandidates += $parentCommon
    }
}

$commonDir = $commonDirCandidates | Select-Object -First 1
if (-not $commonDir) {
    throw "AcmeClient: unable to locate common module directory relative to $PSScriptRoot."
}
Import-Module (Join-Path $commonDir 'Logger.psm1') -Force -Global
Import-Module (Join-Path $commonDir 'CryptoHelper.psm1') -Force -Global
Import-Module (Join-Path $commonDir 'FileOperations.psm1') -Force -Global

# ============================================================================
# MODULE CONFIGURATION
# ============================================================================

# Skip SSL certificate validation for self-signed PKI certificates (PoC environment)
# This applies to all Invoke-RestMethod and Invoke-WebRequest calls in this module
$PSDefaultParameterValues['Invoke-RestMethod:SkipCertificateCheck'] = $true
$PSDefaultParameterValues['Invoke-WebRequest:SkipCertificateCheck'] = $true

# ============================================================================
# MODULE-LEVEL STATE (CACHING)
# ============================================================================

# Cache for ACME directory URLs (avoid repeated lookups)
$script:AcmeDirectory = $null

# Current nonce for replay protection
$script:CurrentNonce = $null

# ============================================================================
# INTERNAL HELPER FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Converts bytes to base64url encoding (RFC 4648 Section 5).

.DESCRIPTION
    Base64url encoding is required by ACME protocol for JWS components.
    Differs from standard base64: + → -, / → _, remove padding =

.PARAMETER Bytes
    Byte array to encode.

.OUTPUTS
    System.String - Base64url-encoded string.
#>
function ConvertTo-Base64Url {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [byte[]]$Bytes
    )

    $base64 = [Convert]::ToBase64String($Bytes)
    $base64url = $base64 -replace '\+', '-' -replace '/', '_' -replace '=', ''
    return $base64url
}

<#
.SYNOPSIS
    Converts string to base64url encoding.

.PARAMETER String
    String to encode.

.OUTPUTS
    System.String - Base64url-encoded string.
#>
function ConvertTo-Base64UrlFromString {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [string]$String
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes($String)
    return ConvertTo-Base64Url -Bytes $bytes
}

<#
.SYNOPSIS
    Fetches a fresh nonce from the CA for replay protection.

.PARAMETER NewNonceUrl
    URL to the CA's newNonce endpoint.

.OUTPUTS
    System.String - Fresh nonce value.
#>
function Get-FreshNonce {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NewNonceUrl
    )

    try {
        Write-LogDebug -Message "Fetching fresh nonce from CA" -Context @{url = $NewNonceUrl}

        # HEAD request to get nonce without body
        $response = Invoke-WebRequest -Uri $NewNonceUrl -Method Head -UseBasicParsing -ErrorAction Stop

        $nonce = $response.Headers['Replay-Nonce'][0]

        if ([string]::IsNullOrWhiteSpace($nonce)) {
            throw "CA did not return Replay-Nonce header"
        }

        Write-LogDebug -Message "Fresh nonce retrieved" -Context @{nonce_length = $nonce.Length}
        return $nonce
    }
    catch {
        Write-LogError -Message "Failed to fetch fresh nonce" -Context @{
            url = $NewNonceUrl
            error = $_.Exception.Message
        }
        throw
    }
}

<#
.SYNOPSIS
    Exports RSA public key to JWK (JSON Web Key) format.

.DESCRIPTION
    Converts RSA public key parameters to JWK format required for
    ACME account registration (jwk header field).

.PARAMETER Rsa
    RSA object containing public key.

.OUTPUTS
    System.Collections.Hashtable - JWK representation of public key.
#>
function Export-RsaPublicKeyJwk {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Security.Cryptography.RSA]$Rsa
    )

    try {
        # Export public key parameters only
        $rsaParams = $Rsa.ExportParameters($false)

        # Convert to JWK format with base64url encoding
        $jwk = @{
            kty = "RSA"
            n = ConvertTo-Base64Url -Bytes $rsaParams.Modulus
            e = ConvertTo-Base64Url -Bytes $rsaParams.Exponent
        }

        return $jwk
    }
    catch {
        throw "Failed to export RSA public key to JWK: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Computes SHA256 thumbprint of JWK (for key authorization).

.PARAMETER Jwk
    JWK hashtable.

.OUTPUTS
    System.String - Base64url-encoded SHA256 hash of JWK.
#>
function Get-JwkThumbprint {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [hashtable]$Jwk
    )

    try {
        # Construct canonical JWK JSON (lexicographic order, no whitespace)
        # For RSA: {"e":"...","kty":"RSA","n":"..."}
        $canonicalJwk = "{`"e`":`"$($Jwk.e)`",`"kty`":`"$($Jwk.kty)`",`"n`":`"$($Jwk.n)`"}"

        $bytes = [Text.Encoding]::UTF8.GetBytes($canonicalJwk)
        $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)

        return ConvertTo-Base64Url -Bytes $hash
    }
    catch {
        throw "Failed to compute JWK thumbprint: $($_.Exception.Message)"
    }
}

# ============================================================================
# PUBLIC FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Retrieves ACME directory from CA and caches endpoint URLs.

.DESCRIPTION
    Fetches the ACME directory resource from the Certificate Authority, which
    contains URLs for all ACME protocol endpoints (newAccount, newOrder, etc.).

    The directory is cached at module level to avoid repeated HTTP requests.
    Subsequent calls return the cached directory unless -Force is specified.

.PARAMETER BaseUrl
    Base URL of the step-ca PKI server (e.g., "https://pki:9000").

.PARAMETER Provisioner
    ACME provisioner name configured in step-ca (default: "acme").

.PARAMETER Force
    Force refresh of cached directory (bypass cache).

.OUTPUTS
    System.Collections.Hashtable - Directory with endpoint URL keys:
        - newNonce: URL to obtain replay nonces
        - newAccount: URL for account creation
        - newOrder: URL to create certificate orders
        - newAuthz: URL for authorizations (optional)
        - revokeCert: URL to revoke certificates
        - keyChange: URL to change account keys

.EXAMPLE
    $directory = Get-AcmeDirectory -BaseUrl "https://pki:9000"
    Write-Host "New account URL: $($directory.newAccount)"

.EXAMPLE
    $directory = Get-AcmeDirectory -BaseUrl "https://pki:9000" -Force
    # Force refresh of cached directory
#>
function Get-AcmeDirectory {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Provisioner = "acme",

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    try {
        # Return cached directory if available and not forcing refresh
        if ($script:AcmeDirectory -ne $null -and -not $Force) {
            Write-LogDebug -Message "Returning cached ACME directory"
            return $script:AcmeDirectory
        }

        # Construct directory URL
        $directoryUrl = "$BaseUrl/acme/$Provisioner/directory"

        Write-LogInfo -Message "Retrieving ACME directory" -Context @{url = $directoryUrl}

        # Fetch directory (no authentication required)
        $response = Invoke-RestMethod -Uri $directoryUrl -Method Get -ErrorAction Stop

        # Validate required fields
        $requiredFields = @('newNonce', 'newAccount', 'newOrder')
        foreach ($field in $requiredFields) {
            if (-not $response.PSObject.Properties.Name.Contains($field)) {
                throw "ACME directory missing required field: $field"
            }
        }

        # Convert to hashtable for consistent return type
        $directory = @{
            newNonce = $response.newNonce
            newAccount = $response.newAccount
            newOrder = $response.newOrder
            revokeCert = $response.revokeCert
            keyChange = $response.keyChange
        }

        # Add optional newAuthz if present
        if ($response.PSObject.Properties.Name.Contains('newAuthz')) {
            $directory.newAuthz = $response.newAuthz
        }

        # Cache directory for future calls
        $script:AcmeDirectory = $directory

        Write-LogInfo -Message "ACME directory retrieved successfully" -Context @{
            newAccount = $directory.newAccount
            newOrder = $directory.newOrder
            newNonce = $directory.newNonce
        }

        return $directory
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorMessage = $_.Exception.Message

        Write-LogError -Message "Failed to retrieve ACME directory" -Context @{
            url = $directoryUrl
            status_code = $statusCode
            error = $errorMessage
        }
        throw
    }
}

<#
.SYNOPSIS
    Creates JWS-signed request for ACME protocol authentication.

.DESCRIPTION
    Constructs a JWS (JSON Web Signature) signed request body for ACME protocol.
    JWS provides cryptographic authentication of requests using account private key.

    The function handles:
    - Protected header construction (alg, kid/jwk, nonce, url)
    - Base64url encoding of header and payload
    - RSA-SHA256 signature generation
    - Nonce management (fetches fresh nonce if needed)

.PARAMETER Url
    Full URL of the ACME endpoint being called (required in protected header).

.PARAMETER Payload
    Request payload as hashtable (will be converted to JSON and base64url-encoded).
    For empty payloads (challenge ready notification), pass @{}.

.PARAMETER AccountKey
    RSA private key object for signing the request.

.PARAMETER AccountKeyId
    Account key identifier URL (kid) for authenticated requests.
    Use this for all requests after account creation.

.PARAMETER AccountKeyJwk
    Account public key in JWK format for account registration.
    Use this only for newAccount requests (before kid is available).

.PARAMETER NewNonceUrl
    URL to fetch fresh nonces if current nonce is null.

.OUTPUTS
    System.String - JWS-signed request body as JSON string with fields:
        - protected: Base64url-encoded protected header
        - payload: Base64url-encoded payload
        - signature: Base64url-encoded signature

.EXAMPLE
    $jws = New-JwsSignedRequest -Url $orderUrl -Payload @{identifiers=@(@{type="dns";value="example.com"})} -AccountKey $rsa -AccountKeyId $kid -NewNonceUrl $nonceUrl
    Invoke-RestMethod -Uri $orderUrl -Method Post -Body $jws -ContentType "application/jose+json"
#>
function New-JwsSignedRequest {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'NewNonceUrl')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'IsPostAsGet')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [object]$Payload,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Security.Cryptography.RSA]$AccountKey,

        [Parameter(Mandatory = $false)]
        [string]$AccountKeyId,

        [Parameter(Mandatory = $false)]
        [hashtable]$AccountKeyJwk,

        [Parameter(Mandatory = $false)]
        [string]$NewNonceUrl,

        [Parameter(Mandatory = $false)]
        [switch]$IsPostAsGet
    )

    try {
        # Ensure we have a nonce (fetch fresh one if needed)
        if ([string]::IsNullOrWhiteSpace($script:CurrentNonce) -and -not [string]::IsNullOrWhiteSpace($NewNonceUrl)) {
            $script:CurrentNonce = Get-FreshNonce -NewNonceUrl $NewNonceUrl
        }

        if ([string]::IsNullOrWhiteSpace($script:CurrentNonce)) {
            throw "No nonce available and NewNonceUrl not provided"
        }

        # Construct protected header
        $protectedHeader = @{
            alg = "RS256"
            nonce = $script:CurrentNonce
            url = $Url
        }

        # Add kid or jwk (mutually exclusive)
        if (-not [string]::IsNullOrWhiteSpace($AccountKeyId)) {
            $protectedHeader.kid = $AccountKeyId
        }
        elseif ($AccountKeyJwk -ne $null) {
            $protectedHeader.jwk = $AccountKeyJwk
        }
        else {
            throw "Either AccountKeyId or AccountKeyJwk must be provided"
        }

        # Convert protected header to JSON and base64url-encode
        $protectedJson = $protectedHeader | ConvertTo-Json -Compress -Depth 5
        $protectedBase64 = ConvertTo-Base64UrlFromString -String $protectedJson

        # Convert payload to JSON and base64url-encode
        # For POST-as-GET (empty string), encode directly without JSON conversion
        if ($Payload -is [string] -and $Payload -eq "") {
            # POST-as-GET: empty string payload encodes to empty string
            $payloadBase64 = ""
        } else {
            # Normal request: convert hashtable to JSON then encode
            $payloadJson = $Payload | ConvertTo-Json -Compress -Depth 10
            $payloadBase64 = ConvertTo-Base64UrlFromString -String $payloadJson
        }

        # Create signing input (protected.payload)
        $signingInput = "$protectedBase64.$payloadBase64"

        # Sign with account private key (RSA-SHA256)
        $signatureBytes = $AccountKey.SignData(
            [Text.Encoding]::ASCII.GetBytes($signingInput),
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
        $signatureBase64 = ConvertTo-Base64Url -Bytes $signatureBytes

        # Construct final JWS object
        $jws = @{
            protected = $protectedBase64
            payload = $payloadBase64
            signature = $signatureBase64
        }

        # Convert to JSON for HTTP request body
        $jwsJson = $jws | ConvertTo-Json -Compress

        Write-LogDebug -Message "JWS-signed request created" -Context @{
            url = $Url
            has_kid = (-not [string]::IsNullOrWhiteSpace($AccountKeyId))
            has_jwk = ($AccountKeyJwk -ne $null)
            payload_is_empty_string = ($Payload -is [string] -and $Payload -eq "")
            payloadbase64_length = $payloadBase64.Length
        }

        # Clear current nonce (will be refreshed from response header)
        $script:CurrentNonce = $null

        return $jwsJson
    }
    catch {
        Write-LogError -Message "Failed to create JWS-signed request" -Context @{
            url = $Url
            error = $_.Exception.Message
        }
        throw
    }
}

<#
.SYNOPSIS
    Creates new ACME account or retrieves existing account.

.DESCRIPTION
    Registers a new ACME account with the CA using a generated RSA key pair.
    If an account with the same public key already exists, the CA returns the
    existing account details (idempotent operation).

    The function:
    - Generates RSA 2048-bit key pair for account
    - Sends newAccount request with JWS signature (using jwk header)
    - Stores account private key to /config/acme-account.key with 0600 permissions
    - Returns account details including URL (kid) and status

.PARAMETER BaseUrl
    Base URL of the step-ca PKI server (e.g., "https://pki:9000").

.PARAMETER Contact
    Array of contact URIs for account (e.g., @("mailto:admin@example.com")).
    Optional but recommended for account recovery notifications.

.PARAMETER Provisioner
    ACME provisioner name configured in step-ca (default: "acme").

.PARAMETER AccountKeyPath
    Path to store account private key (default: "/config/acme-account.key").

.OUTPUTS
    System.Collections.Hashtable - Account object with properties:
        - URL: Account key identifier (kid) for future requests
        - Status: Account status (valid, deactivated, revoked)
        - Contact: Confirmed contact information
        - AccountKey: RSA private key object (for immediate use)

.NOTES
    Resource Management: The returned AccountKey is a live RSA object. Callers are
    responsible for calling .Dispose() on this object when finished to release
    unmanaged cryptographic resources.

.EXAMPLE
    $account = New-AcmeAccount -BaseUrl "https://pki:9000" -Contact @("mailto:admin@example.com")
    Write-Host "Account URL: $($account.URL)"
    # When done with the account key:
    $account.AccountKey.Dispose()
#>
function New-AcmeAccount {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,

        [Parameter(Mandatory = $false)]
        [string[]]$Contact = @(),

        [Parameter(Mandatory = $false)]
        [string]$Provisioner = "acme",

        [Parameter(Mandatory = $false)]
        [string]$AccountKeyPath = "/config/acme-account.key"
    )

    try {
        Write-LogInfo -Message "Creating ACME account" -Context @{base_url = $BaseUrl}

        # Get ACME directory
        $directory = Get-AcmeDirectory -BaseUrl $BaseUrl -Provisioner $Provisioner

        # Generate RSA 2048-bit key pair for account
        Write-LogDebug -Message "Generating RSA 2048-bit account key pair"
        $accountKeyPem = New-RSAKeyPair

        # Load RSA object from PEM for signing
        $rsa = [System.Security.Cryptography.RSA]::Create()
        $rsa.ImportFromPem($accountKeyPem)

        # Export public key as JWK
        $jwk = Export-RsaPublicKeyJwk -Rsa $rsa

        # Construct newAccount request payload
        $payload = @{
            termsOfServiceAgreed = $true
        }

        if ($Contact.Count -gt 0) {
            $payload.contact = $Contact
        }

        # Create JWS-signed request (using jwk header for new account)
        $jwsRequest = New-JwsSignedRequest `
            -Url $directory.newAccount `
            -Payload $payload `
            -AccountKey $rsa `
            -AccountKeyJwk $jwk `
            -NewNonceUrl $directory.newNonce

        # Send newAccount request
        Write-LogDebug -Message "Sending newAccount request" -Context @{url = $directory.newAccount}

        $webResponse = Invoke-WebRequest `
            -Uri $directory.newAccount `
            -Method Post `
            -Body $jwsRequest `
            -ContentType "application/jose+json" `
            -ErrorAction Stop

        $response = $webResponse.Content | ConvertFrom-Json

        # Extract account URL (kid) from Location header
        $accountUrl = if ($webResponse.Headers.ContainsKey('Location') -and $webResponse.Headers['Location'].Count -gt 0) {
            $webResponse.Headers['Location'][0]
        } else {
            $null
        }

        if ([string]::IsNullOrWhiteSpace($accountUrl)) {
            throw "CA did not return Location header with account URL"
        }

        # Update nonce from response
        if ($webResponse.Headers.ContainsKey('Replay-Nonce')) {
            $script:CurrentNonce = $webResponse.Headers['Replay-Nonce'][0]
        }

        # Store account private key securely
        Write-LogDebug -Message "Storing account private key" -Context @{path = $AccountKeyPath}
        Write-FileAtomic -Path $AccountKeyPath -Content $accountKeyPem
        Set-FilePermissions -Path $AccountKeyPath -Mode "0600"

        Write-LogInfo -Message "ACME account created successfully" -Context @{
            account_url = $accountUrl
            status = $response.status
            key_path = $AccountKeyPath
        }

        # Return account object
        # NOTE: The RSA object is returned to the caller and must be disposed by the caller when done
        return @{
            URL = $accountUrl
            Status = $response.status
            Contact = $response.contact
            AccountKey = $rsa
        }
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorBody = $null

        if ($_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($_.ErrorDetails.Message)) {
            try {
                $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json
            }
            catch {
                Out-Null
            }
        }

        Write-LogError -Message "ACME account creation failed" -Context @{
            base_url = $BaseUrl
            status_code = $statusCode
            error_type = $errorBody.type
            error_detail = $errorBody.detail
            error = $_.Exception.Message
        }

        # Dispose RSA object on error since it won't be returned to caller
        if ($null -ne $rsa) {
            $rsa.Dispose()
        }

        throw
    }
}

<#
.SYNOPSIS
    Retrieves existing ACME account details.

.DESCRIPTION
    Fetches account information from the CA using a stored account private key.
    This is used to verify account status and retrieve account URL (kid).

    The account key must already exist at the specified path (created by New-AcmeAccount).

.PARAMETER BaseUrl
    Base URL of the step-ca PKI server (e.g., "https://pki:9000").

.PARAMETER Provisioner
    ACME provisioner name configured in step-ca (default: "acme").

.PARAMETER AccountKeyPath
    Path to stored account private key (default: "/config/acme-account.key").

.OUTPUTS
    System.Collections.Hashtable - Account object with properties:
        - URL: Account key identifier (kid)
        - Status: Account status (valid, deactivated, revoked)
        - Contact: Account contact information
        - AccountKey: RSA private key object

.NOTES
    Resource Management: The returned AccountKey is a live RSA object. Callers are
    responsible for calling .Dispose() on this object when finished to release
    unmanaged cryptographic resources.

.EXAMPLE
    $account = Get-AcmeAccount -BaseUrl "https://pki:9000"
    if ($account.Status -eq "valid") {
        Write-Host "Account is active"
    }
    # When done with the account key:
    $account.AccountKey.Dispose()
#>
function Get-AcmeAccount {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,

        [Parameter(Mandatory = $false)]
        [string]$Provisioner = "acme",

        [Parameter(Mandatory = $false)]
        [string]$AccountKeyPath = "/config/acme-account.key"
    )

    try {
        Write-LogInfo -Message "Retrieving ACME account" -Context @{key_path = $AccountKeyPath}

        # Verify account key file exists
        if (-not (Test-Path -Path $AccountKeyPath -PathType Leaf)) {
            throw "Account key file not found at $AccountKeyPath"
        }

        # Load account private key
        $accountKeyPem = Get-Content -Path $AccountKeyPath -Raw
        $rsa = [System.Security.Cryptography.RSA]::Create()
        $rsa.ImportFromPem($accountKeyPem)

        # Get ACME directory
        $directory = Get-AcmeDirectory -BaseUrl $BaseUrl -Provisioner $Provisioner

        # Export public key as JWK
        $jwk = Export-RsaPublicKeyJwk -Rsa $rsa

        # Construct account retrieval payload (empty contact to query existing)
        $payload = @{
            onlyReturnExisting = $true
        }

        # Create JWS-signed request (using jwk header to find account)
        $jwsRequest = New-JwsSignedRequest `
            -Url $directory.newAccount `
            -Payload $payload `
            -AccountKey $rsa `
            -AccountKeyJwk $jwk `
            -NewNonceUrl $directory.newNonce

        # Send newAccount request with onlyReturnExisting=true
        Write-LogDebug -Message "Sending account retrieval request" -Context @{url = $directory.newAccount}

        $webResponse = Invoke-WebRequest `
            -Uri $directory.newAccount `
            -Method Post `
            -Body $jwsRequest `
            -ContentType "application/jose+json" `
            -ErrorAction Stop

        $response = $webResponse.Content | ConvertFrom-Json

        # Extract account URL from Location header
        $accountUrl = $null
        if ($webResponse.Headers.ContainsKey('Location') -and $webResponse.Headers['Location'].Count -gt 0) {
            $accountUrl = $webResponse.Headers['Location'][0]
        }

        if ([string]::IsNullOrWhiteSpace($accountUrl)) {
            throw "CA did not return Location header with account URL"
        }

        # Update nonce from response
        if ($webResponse.Headers.ContainsKey('Replay-Nonce')) {
            $script:CurrentNonce = $webResponse.Headers['Replay-Nonce'][0]
        }

        Write-LogInfo -Message "ACME account retrieved successfully" -Context @{
            account_url = $accountUrl
            status = $response.status
        }

        # Return account object
        # NOTE: The RSA object is returned to the caller and must be disposed by the caller when done
        return @{
            URL = $accountUrl
            Status = $response.status
            Contact = $response.contact
            AccountKey = $rsa
        }
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorBody = $null

        if ($_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($_.ErrorDetails.Message)) {
            try {
                $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json
            }
            catch {
                Out-Null
            }
        }

        Write-LogError -Message "ACME account retrieval failed" -Context @{
            base_url = $BaseUrl
            key_path = $AccountKeyPath
            status_code = $statusCode
            error_type = $errorBody.type
            error_detail = $errorBody.detail
            error = $_.Exception.Message
        }

        # Dispose RSA object on error since it won't be returned to caller
        if ($null -ne $rsa) {
            $rsa.Dispose()
        }

        throw
    }
}

<#
.SYNOPSIS
    Creates new ACME order for certificate issuance.

.DESCRIPTION
    Initiates a certificate order with the CA by specifying domain names to be included
    in the certificate. The CA responds with an order object containing authorization
    URLs that must be completed before certificate finalization.

    The function:
    - Sends JWS-signed POST request to newOrder endpoint
    - Converts domain names to ACME identifier format (type: dns)
    - Returns order object with status, authorization URLs, and finalize URL
    - Updates replay nonce from response headers

.PARAMETER BaseUrl
    Base URL of the step-ca PKI server (e.g., "https://pki:9000").

.PARAMETER DomainNames
    Array of domain names to include in the certificate (e.g., @("target-server")).
    Supports both single-domain and multi-domain (SAN) certificates.

.PARAMETER AccountKey
    RSA private key object for signing the request.

.PARAMETER AccountKeyId
    Account key identifier URL (kid) obtained from account registration.

.PARAMETER Provisioner
    ACME provisioner name configured in step-ca (default: "acme").

.OUTPUTS
    System.Collections.Hashtable - Order object with properties:
        - URL: Order URL for status polling
        - Status: Order status (pending, ready, processing, valid, invalid)
        - Expires: ISO 8601 timestamp when order expires
        - Identifiers: Array of domain identifiers
        - Authorizations: Array of authorization URLs (one per domain)
        - Finalize: URL to submit CSR when authorizations complete

.EXAMPLE
    $order = New-AcmeOrder -BaseUrl "https://pki:9000" -DomainNames @("target-server") -AccountKey $rsa -AccountKeyId $accountUrl
    Write-Host "Order status: $($order.Status)"
    Write-Host "Authorization URL: $($order.Authorizations[0])"

.NOTES
    The order status starts as "pending" and transitions to "ready" when all
    authorizations are valid. The client must complete all authorizations before
    proceeding to certificate finalization.
#>
function New-AcmeOrder {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$DomainNames,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Security.Cryptography.RSA]$AccountKey,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccountKeyId,

        [Parameter(Mandatory = $false)]
        [string]$Provisioner = "acme"
    )

    try {
        Write-LogInfo -Message "Creating ACME order" -Context @{
            domains = ($DomainNames -join ', ')
            domain_count = $DomainNames.Count
        }

        # Get ACME directory
        $directory = Get-AcmeDirectory -BaseUrl $BaseUrl -Provisioner $Provisioner

        # Convert domain names to ACME identifier format
        # Explicitly create array to ensure proper JSON serialization
        $identifiers = @($DomainNames | ForEach-Object {
            @{
                type = "dns"
                value = $_
            }
        })

        # Construct newOrder payload
        # Wrap in @() to ensure identifiers is always an array (even for single domain)
        $payload = @{
            identifiers = @($identifiers)
        }

        # Create JWS-signed request
        $jwsRequest = New-JwsSignedRequest `
            -Url $directory.newOrder `
            -Payload $payload `
            -AccountKey $AccountKey `
            -AccountKeyId $AccountKeyId `
            -NewNonceUrl $directory.newNonce

        # Send newOrder request
        Write-LogDebug -Message "Sending newOrder request" -Context @{url = $directory.newOrder}

        $webResponse = Invoke-WebRequest `
            -Uri $directory.newOrder `
            -Method Post `
            -Body $jwsRequest `
            -ContentType "application/jose+json" `
            -ErrorAction Stop

        $response = $webResponse.Content | ConvertFrom-Json

        # Extract order URL from Location header
        $orderUrl = $null
        if ($webResponse.Headers.ContainsKey('Location') -and $webResponse.Headers['Location'].Count -gt 0) {
            $orderUrl = $webResponse.Headers['Location'][0]
        }

        if ([string]::IsNullOrWhiteSpace($orderUrl)) {
            throw "CA did not return Location header with order URL"
        }

        # Update nonce from response
        if ($webResponse.Headers.ContainsKey('Replay-Nonce')) {
            $script:CurrentNonce = $webResponse.Headers['Replay-Nonce'][0]
        }

        # Extract order ID from URL for logging
        $orderId = $orderUrl.Split('/')[-1]

        Write-LogInfo -Message "Order created" -Context @{
            order_id = $orderId
            order_url = $orderUrl
            domains = ($DomainNames -join ', ')
            status = $response.status
            authorizations_count = $response.authorizations.Count
        }

        # Return order object
        return @{
            URL = $orderUrl
            Status = $response.status
            Expires = $response.expires
            Identifiers = $response.identifiers
            Authorizations = $response.authorizations
            Finalize = $response.finalize
        }
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorBody = $null

        if ($_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($_.ErrorDetails.Message)) {
            try {
                $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json
            }
            catch {
                Out-Null
            }
        }

        Write-LogError -Message "ACME order creation failed" -Context @{
            function = "New-AcmeOrder"
            domains = ($DomainNames -join ', ')
            status_code = $statusCode
            error_type = $errorBody.type
            error_detail = $errorBody.detail
            error = $_.Exception.Message
        }
        throw
    }
}

<#
.SYNOPSIS
    Retrieves authorization details for domain validation.

.DESCRIPTION
    Fetches authorization information from the CA, including challenge details
    required to prove domain control. Each domain in an order has a corresponding
    authorization that must be completed.

    The authorization response contains available challenge types (HTTP-01, DNS-01,
    TLS-ALPN-01). For HTTP-01 challenges, the response includes a token that must
    be served at a well-known HTTP URL.

    This function uses POST-as-GET (JWS-authenticated POST with empty payload) as
    required by step-ca implementation.

.PARAMETER AuthorizationUrl
    Full URL to the authorization resource (from order.Authorizations array).

.PARAMETER AccountKey
    RSA private key object for signing the POST-as-GET request.

.PARAMETER AccountKeyId
    Account key identifier URL (kid) for JWS authentication.

.PARAMETER NewNonceUrl
    URL to fetch fresh nonces for JWS signing.

.OUTPUTS
    System.Collections.Hashtable - Authorization object with properties:
        - Status: Authorization status (pending, valid, invalid, expired)
        - Expires: ISO 8601 timestamp when authorization expires
        - Identifier: Domain identifier being authorized (type, value)
        - Challenges: Array of challenge objects with type, status, url, token

.EXAMPLE
    $authz = Get-AcmeAuthorization -AuthorizationUrl $order.Authorizations[0] -AccountKey $rsa -AccountKeyId $accountUrl -NewNonceUrl $directory.newNonce
    $http01Challenge = $authz.Challenges | Where-Object {$_.type -eq "http-01"}
    Write-Host "Challenge token: $($http01Challenge.token)"

.NOTES
    Uses POST-as-GET (RFC 8555 Section 6.3) - JWS-authenticated POST with empty payload.
    This is required by step-ca for authorization resource access.
#>
function Get-AcmeAuthorization {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AuthorizationUrl,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Security.Cryptography.RSA]$AccountKey,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccountKeyId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NewNonceUrl
    )

    try {
        Write-LogDebug -Message "Retrieving authorization details" -Context @{url = $AuthorizationUrl}

        # POST-as-GET request (JWS-authenticated POST with empty string payload)
        # RFC 8555 Section 6.3: POST-as-GET uses empty string payload (not empty object)
        $payload = ""

        $jwsRequest = New-JwsSignedRequest `
            -Url $AuthorizationUrl `
            -Payload $payload `
            -AccountKey $AccountKey `
            -AccountKeyId $AccountKeyId `
            -NewNonceUrl $NewNonceUrl `
            -IsPostAsGet

        $webResponse = Invoke-WebRequest `
            -Uri $AuthorizationUrl `
            -Method Post `
            -Body $jwsRequest `
            -ContentType "application/jose+json" `
            -ErrorAction Stop

        $response = $webResponse.Content | ConvertFrom-Json

        # Update nonce from response
        if ($webResponse.Headers.ContainsKey('Replay-Nonce')) {
            $script:CurrentNonce = $webResponse.Headers['Replay-Nonce'][0]
        }

        Write-LogInfo -Message "Authorization retrieved" -Context @{
            url = $AuthorizationUrl
            domain = $response.identifier.value
            status = $response.status
            challenges_count = $response.challenges.Count
        }

        # Return authorization object
        return @{
            Status = $response.status
            Expires = $response.expires
            Identifier = $response.identifier
            Challenges = $response.challenges
        }
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__

        Write-LogError -Message "Authorization retrieval failed" -Context @{
            function = "Get-AcmeAuthorization"
            url = $AuthorizationUrl
            status_code = $statusCode
            error = $_.Exception.Message
        }
        throw
    }
}

<#
.SYNOPSIS
    Completes HTTP-01 challenge for domain validation.

.DESCRIPTION
    Proves domain control by:
    1. Computing key authorization (token + "." + base64url(SHA256(accountPublicKeyJWK)))
    2. Writing key authorization to /.well-known/acme-challenge/{token} (shared volume)
    3. Setting file permissions to 0644 (world-readable for CA validation)
    4. Notifying CA that challenge is ready via JWS-signed POST

    The CA will make an HTTP GET request to http://{domain}/.well-known/acme-challenge/{token}
    to validate the key authorization. The file must be accessible via NGINX on the shared
    challenge volume.

.PARAMETER Challenge
    Challenge object from authorization (must be type "http-01") with properties:
        - type: Challenge type (must be "http-01")
        - status: Challenge status
        - url: URL to notify CA
        - token: Random token

.PARAMETER AccountKey
    RSA private key object for computing JWK thumbprint and signing notification.

.PARAMETER AccountKeyId
    Account key identifier URL (kid) for JWS authentication.

.PARAMETER NewNonceUrl
    URL to fetch fresh nonces for JWS signing.

.OUTPUTS
    System.Boolean - Returns $true on successful notification to CA.

.EXAMPLE
    $success = Complete-Http01Challenge -Challenge $http01Challenge -AccountKey $rsa -AccountKeyId $accountUrl -NewNonceUrl $directory.newNonce
    if ($success) {
        Write-Host "Challenge notification sent, CA is validating"
    }

.NOTES
    The challenge file is written to /challenge/.well-known/acme-challenge/{token}
    which corresponds to a Docker shared volume accessible by NGINX for serving at
    http://{domain}/.well-known/acme-challenge/{token}.

    File permissions must be 0644 to allow the CA HTTP client to read the file.
#>
function Complete-Http01Challenge {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [hashtable]$Challenge,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Security.Cryptography.RSA]$AccountKey,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccountKeyId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NewNonceUrl
    )

    try {
        # Validate challenge type
        if ($Challenge.type -ne "http-01") {
            throw "Only HTTP-01 challenges are supported (received: $($Challenge.type))"
        }

        $token = $Challenge.token
        $challengeUrl = $Challenge.url

        Write-LogInfo -Message "Starting HTTP-01 challenge completion" -Context @{
            token = $token
            challenge_url = $challengeUrl
        }

        # Compute key authorization: token + "." + base64url(SHA256(accountPublicKeyJWK))
        $jwk = Export-RsaPublicKeyJwk -Rsa $AccountKey
        $jwkThumbprint = Get-JwkThumbprint -Jwk $jwk
        $keyAuthorization = "$token.$jwkThumbprint"

        Write-LogDebug -Message "Key authorization computed" -Context @{
            token = $token
            thumbprint = $jwkThumbprint
        }

        # Ensure challenge directory exists
        $challengeDir = "/challenge/.well-known/acme-challenge"
        if (-not (Test-Path -Path $challengeDir -PathType Container)) {
            Write-LogDebug -Message "Creating challenge directory" -Context @{path = $challengeDir}
            New-Item -ItemType Directory -Force -Path $challengeDir | Out-Null
        }

        # Write key authorization to challenge file (atomic write)
        $challengeFilePath = Join-Path $challengeDir $token
        Write-LogDebug -Message "Writing challenge token file" -Context @{
            path = $challengeFilePath
            key_authorization_length = $keyAuthorization.Length
        }

        Write-FileAtomic -Path $challengeFilePath -Content $keyAuthorization

        # Set file permissions to 0644 (world-readable for CA validation)
        Set-FilePermissions -Path $challengeFilePath -Mode "0644"

        Write-LogInfo -Message "Challenge token file created" -Context @{
            path = $challengeFilePath
            permissions = "0644"
        }

        # Notify CA that challenge is ready (JWS-signed POST with empty payload)
        $payload = @{}

        $jwsRequest = New-JwsSignedRequest `
            -Url $challengeUrl `
            -Payload $payload `
            -AccountKey $AccountKey `
            -AccountKeyId $AccountKeyId `
            -NewNonceUrl $NewNonceUrl

        Write-LogDebug -Message "Sending challenge ready notification" -Context @{url = $challengeUrl}

        $webResponse = Invoke-WebRequest `
            -Uri $challengeUrl `
            -Method Post `
            -Body $jwsRequest `
            -ContentType "application/jose+json" `
            -ErrorAction Stop

        $response = $webResponse.Content | ConvertFrom-Json

        # Update nonce from response
        if ($webResponse.Headers.ContainsKey('Replay-Nonce')) {
            $script:CurrentNonce = $webResponse.Headers['Replay-Nonce'][0]
        }

        Write-LogInfo -Message "Challenge notification sent successfully" -Context @{
            token = $token
            challenge_status = $response.status
        }

        return $true
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorBody = $null

        if ($_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($_.ErrorDetails.Message)) {
            try {
                $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json
            }
            catch {
                Out-Null
            }
        }

        Write-LogError -Message "HTTP-01 challenge completion failed" -Context @{
            function = "Complete-Http01Challenge"
            token = $Challenge.token
            challenge_url = $Challenge.url
            status_code = $statusCode
            error_type = $errorBody.type
            error_detail = $errorBody.detail
            error = $_.Exception.Message
        }
        throw
    }
}

<#
.SYNOPSIS
    Polls authorization URL until challenge validation completes.

.DESCRIPTION
    Monitors challenge validation status by polling the authorization URL at
    regular intervals. The CA validates the HTTP-01 challenge asynchronously,
    so the client must wait for the status to transition to "valid".

    The function polls every 2 seconds with a 30-second timeout. When the
    challenge status becomes "valid", the function returns successfully.

.PARAMETER AuthorizationUrl
    Full URL to the authorization resource (same URL used in Get-AcmeAuthorization).

.PARAMETER PollIntervalSeconds
    Seconds to wait between polling attempts (default: 2).

.PARAMETER TimeoutSeconds
    Maximum seconds to wait for validation (default: 30).

.OUTPUTS
    System.Void - Returns when challenge is valid or throws on timeout/failure.

.EXAMPLE
    Wait-ChallengeValidation -AuthorizationUrl "https://pki:9000/acme/acme/authz/dGFyZ2V0LXNlcnZlcg"
    Write-Host "Challenge validated successfully"

.NOTES
    The function polls the authorization URL (not the challenge URL) because the
    authorization response contains the updated challenge status in the challenges array.

    Throws an error if validation times out or if challenge status becomes "invalid".
#>
function Wait-ChallengeValidation {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AuthorizationUrl,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Security.Cryptography.RSA]$AccountKey,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccountKeyId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NewNonceUrl,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 60)]
        [int]$PollIntervalSeconds = 2,

        [Parameter(Mandatory = $false)]
        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = 30
    )

    try {
        Write-LogInfo -Message "Waiting for challenge validation" -Context @{
            url = $AuthorizationUrl
            poll_interval_seconds = $PollIntervalSeconds
            timeout_seconds = $TimeoutSeconds
        }

        $startTime = Get-Date
        $attempts = 0

        while ($true) {
            $attempts++

            # Check timeout
            $elapsedSeconds = ((Get-Date) - $startTime).TotalSeconds
            if ($elapsedSeconds -gt $TimeoutSeconds) {
                throw "Challenge validation timeout after $TimeoutSeconds seconds ($attempts attempts)"
            }

            # Poll authorization URL using POST-as-GET
            Write-LogDebug -Message "Polling authorization status" -Context @{
                attempt = $attempts
                elapsed_seconds = [math]::Round($elapsedSeconds, 1)
            }

            # POST-as-GET request (JWS-authenticated POST with empty string payload)
            # RFC 8555 Section 6.3: POST-as-GET uses empty string payload (not empty object)
            $payload = ""

            $jwsRequest = New-JwsSignedRequest `
                -Url $AuthorizationUrl `
                -Payload $payload `
                -AccountKey $AccountKey `
                -AccountKeyId $AccountKeyId `
                -NewNonceUrl $NewNonceUrl `
                -IsPostAsGet

            $webResponse = Invoke-WebRequest `
                -Uri $AuthorizationUrl `
                -Method Post `
                -Body $jwsRequest `
                -ContentType "application/jose+json" `
                -ErrorAction Stop

            $authz = $webResponse.Content | ConvertFrom-Json

            # Update nonce from response
            if ($webResponse.Headers.ContainsKey('Replay-Nonce')) {
                $script:CurrentNonce = $webResponse.Headers['Replay-Nonce'][0]
            }

            # Find HTTP-01 challenge status
            $http01Challenge = $authz.challenges | Where-Object {$_.type -eq "http-01"} | Select-Object -First 1

            if ($null -eq $http01Challenge) {
                throw "HTTP-01 challenge not found in authorization response"
            }

            $challengeStatus = $http01Challenge.status

            Write-LogDebug -Message "Challenge status polled" -Context @{
                attempt = $attempts
                status = $challengeStatus
                elapsed_seconds = [math]::Round($elapsedSeconds, 1)
            }

            # Check status
            if ($challengeStatus -eq "valid") {
                Write-LogInfo -Message "Challenge validated" -Context @{
                    attempts = $attempts
                    elapsed_seconds = [math]::Round($elapsedSeconds, 1)
                }
                return
            }
            elseif ($challengeStatus -eq "invalid") {
                $errorDetail = $http01Challenge.error.detail
                throw "Challenge validation failed: $errorDetail"
            }
            elseif ($challengeStatus -eq "pending" -or $challengeStatus -eq "processing") {
                # Continue polling
                Start-Sleep -Seconds $PollIntervalSeconds
            }
            else {
                throw "Unexpected challenge status: $challengeStatus"
            }
        }
    }
    catch {
        Write-LogError -Message "Challenge validation timeout" -Context @{
            function = "Wait-ChallengeValidation"
            url = $AuthorizationUrl
            error = $_.Exception.Message
        }
        throw
    }
}

<#
.SYNOPSIS
    Finalizes ACME order by submitting CSR and polling until certificate is issued.

.DESCRIPTION
    Completes the certificate issuance process by:
    1. Extracting base64-encoded DER from CSR PEM string
    2. Sending JWS-signed POST request to order finalize URL with CSR
    3. Polling order status until it transitions to "valid" (certificate issued)
    4. Returning updated order object with certificate URL

    The finalization can only succeed when all order authorizations are valid.
    The CA processes the CSR and issues the certificate asynchronously, requiring
    status polling with a 60-second timeout.

.PARAMETER Order
    Order object from New-AcmeOrder with properties:
        - URL: Order resource URL for status polling
        - Finalize: URL to submit CSR for finalization
        - Status: Order status (must be "ready")
        - Authorizations: Array of authorization URLs

.PARAMETER CsrPem
    Certificate Signing Request in PEM format (from New-CertificateRequest).
    Must include BEGIN/END CERTIFICATE REQUEST delimiters.

.PARAMETER AccountKey
    RSA private key object for signing the finalization request.

.PARAMETER AccountKeyId
    Account key identifier URL (kid) for JWS authentication.

.PARAMETER NewNonceUrl
    URL to fetch fresh nonces for JWS signing.

.OUTPUTS
    System.Collections.Hashtable - Updated order object with properties:
        - URL: Order resource URL
        - Status: Order status ("valid" on success)
        - Expires: ISO 8601 timestamp when order expires
        - Identifiers: Array of domain identifiers
        - Authorizations: Array of authorization URLs
        - Finalize: URL that was used for finalization
        - Certificate: URL to download issued certificate

.EXAMPLE
    $finalizedOrder = Complete-AcmeOrder -Order $order -CsrPem $csrPem -AccountKey $rsa -AccountKeyId $accountUrl -NewNonceUrl $directory.newNonce
    Write-Host "Certificate URL: $($finalizedOrder.Certificate)"

.NOTES
    The order status must be "ready" (all authorizations valid) before finalization.
    The function polls the order URL every 2 seconds with a 60-second maximum timeout.
    CSR must use standard base64 encoding (not base64url) per ACME RFC 8555 section 7.4.
#>
function Complete-AcmeOrder {
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [hashtable]$Order,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CsrPem,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Security.Cryptography.RSA]$AccountKey,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccountKeyId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NewNonceUrl
    )

    try {
        Write-LogInfo -Message "Finalizing ACME order" -Context @{
            order_url = $Order.URL
            finalize_url = $Order.Finalize
            csr_size_bytes = $CsrPem.Length
        }

        # Extract base64-encoded DER from CSR PEM (remove headers and whitespace)
        # Convert standard base64 to base64url (step-ca requirement)
        # Standard base64 uses +, /, and =, but base64url uses -, _, and no padding
        $csrBase64Standard = $CsrPem -replace '-----BEGIN CERTIFICATE REQUEST-----', '' -replace '-----END CERTIFICATE REQUEST-----', '' -replace '\s', ''
        $csrBase64 = $csrBase64Standard -replace '\+', '-' -replace '/', '_' -replace '=', ''

        Write-LogDebug -Message "CSR extracted from PEM" -Context @{
            csr_base64_length = $csrBase64.Length
        }

        # Construct finalize payload
        $payload = @{
            csr = $csrBase64
        }

        # Create JWS-signed request
        $jwsRequest = New-JwsSignedRequest `
            -Url $Order.Finalize `
            -Payload $payload `
            -AccountKey $AccountKey `
            -AccountKeyId $AccountKeyId `
            -NewNonceUrl $NewNonceUrl

        # Send finalize request
        Write-LogDebug -Message "Sending order finalization request" -Context @{url = $Order.Finalize}

        $webResponse = Invoke-WebRequest `
            -Uri $Order.Finalize `
            -Method Post `
            -Body $jwsRequest `
            -ContentType "application/jose+json" `
            -ErrorAction Stop

        $response = $webResponse.Content | ConvertFrom-Json

        # Update nonce from response
        if ($webResponse.Headers.ContainsKey('Replay-Nonce')) {
            $script:CurrentNonce = $webResponse.Headers['Replay-Nonce'][0]
        }

        Write-LogInfo -Message "Order finalization submitted" -Context @{
            status = $response.status
        }

        # Poll order status until valid or timeout
        $startTime = Get-Date
        $maxTimeout = 60
        $pollInterval = 2
        $attempts = 0

        while ($true) {
            $attempts++
            $elapsed = ((Get-Date) - $startTime).TotalSeconds

            # Check timeout
            if ($elapsed -gt $maxTimeout) {
                throw "Order finalization timeout: exceeded $maxTimeout seconds"
            }

            # Poll order URL for current status using POST-as-GET
            Write-LogDebug -Message "Polling order status" -Context @{
                attempt = $attempts
                elapsed_seconds = [math]::Round($elapsed, 2)
            }

            # POST-as-GET request (JWS-authenticated POST with empty string payload)
            $payload = ""
            $jwsRequest = New-JwsSignedRequest `
                -Url $Order.URL `
                -Payload $payload `
                -AccountKey $AccountKey `
                -AccountKeyId $AccountKeyId `
                -NewNonceUrl $NewNonceUrl `
                -IsPostAsGet

            $webResponse = Invoke-WebRequest `
                -Uri $Order.URL `
                -Method Post `
                -Body $jwsRequest `
                -ContentType "application/jose+json" `
                -ErrorAction Stop

            $currentOrder = $webResponse.Content | ConvertFrom-Json

            # Update nonce from response
            if ($webResponse.Headers.ContainsKey('Replay-Nonce')) {
                $script:CurrentNonce = $webResponse.Headers['Replay-Nonce'][0]
            }

            Write-LogDebug -Message "Order status polled" -Context @{
                attempt = $attempts
                status = $currentOrder.status
                elapsed_seconds = [math]::Round($elapsed, 2)
            }

            # Check order status
            if ($currentOrder.status -eq "valid") {
                # Order complete - certificate issued
                Write-LogInfo -Message "Order finalized" -Context @{
                    order_url = $Order.URL
                    certificate_url = $currentOrder.certificate
                    elapsed_seconds = [math]::Round($elapsed, 2)
                }

                return @{
                    URL = $Order.URL
                    Status = $currentOrder.status
                    Expires = $currentOrder.expires
                    Identifiers = $currentOrder.identifiers
                    Authorizations = $currentOrder.authorizations
                    Finalize = $currentOrder.finalize
                    Certificate = $currentOrder.certificate
                }
            }
            elseif ($currentOrder.status -eq "invalid") {
                throw "Order finalization failed: CA returned invalid status"
            }
            elseif ($currentOrder.status -eq "processing" -or $currentOrder.status -eq "pending") {
                # Continue polling
                Start-Sleep -Seconds $pollInterval
            }
            else {
                throw "Unexpected order status: $($currentOrder.status)"
            }
        }
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorBody = $null

        if ($_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($_.ErrorDetails.Message)) {
            try {
                $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json
            }
            catch {
                Out-Null
            }
        }

        Write-LogError -Message "ACME order finalization failed" -Context @{
            function = "Complete-AcmeOrder"
            order_url = $Order.URL
            finalize_url = $Order.Finalize
            status_code = $statusCode
            error_type = $errorBody.type
            error_detail = $errorBody.detail
            error = $_.Exception.Message
        }
        throw
    }
}

<#
.SYNOPSIS
    Downloads issued certificate from ACME CA.

.DESCRIPTION
    Retrieves the signed certificate chain from the CA using the certificate URL
    obtained from a finalized order. The CA returns the certificate in PEM format,
    which may include multiple certificates (end-entity certificate + intermediate CAs).

    Uses POST-as-GET (JWS-authenticated POST with empty payload) as required by step-ca.

.PARAMETER CertificateUrl
    Full URL to the certificate resource (from finalizedOrder.Certificate).

.PARAMETER AccountKey
    RSA private key object for signing the POST-as-GET request.

.PARAMETER AccountKeyId
    Account key identifier URL (kid) for JWS authentication.

.PARAMETER NewNonceUrl
    URL to fetch fresh nonces for JWS signing.

.OUTPUTS
    System.String - PEM-encoded certificate chain (includes full chain if provided by CA).
    Multiple certificates are concatenated with newlines between PEM blocks.

.EXAMPLE
    $certificatePem = Get-AcmeCertificate -CertificateUrl $finalizedOrder.Certificate -AccountKey $rsa -AccountKeyId $accountUrl -NewNonceUrl $directory.newNonce
    Write-Host "Certificate downloaded: $($certificatePem.Length) bytes"

.NOTES
    Uses POST-as-GET (RFC 8555 Section 6.3) - JWS-authenticated POST with empty payload.
    This is required by step-ca for certificate download.

    The returned PEM string includes the full certificate chain (end-entity + intermediates)
    if the CA provides it. Most CAs include at least the end-entity and issuing CA certificates.
#>
function Get-AcmeCertificate {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CertificateUrl,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Security.Cryptography.RSA]$AccountKey,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccountKeyId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NewNonceUrl
    )

    try {
        Write-LogInfo -Message "Downloading certificate" -Context @{
            certificate_url = $CertificateUrl
        }

        # POST-as-GET request (JWS-authenticated POST with empty string payload)
        # RFC 8555 Section 6.3: POST-as-GET uses empty string payload (not empty object)
        $payload = ""

        $jwsRequest = New-JwsSignedRequest `
            -Url $CertificateUrl `
            -Payload $payload `
            -AccountKey $AccountKey `
            -AccountKeyId $AccountKeyId `
            -NewNonceUrl $NewNonceUrl `
            -IsPostAsGet

        $webResponse = Invoke-WebRequest `
            -Uri $CertificateUrl `
            -Method Post `
            -Body $jwsRequest `
            -ContentType "application/jose+json" `
            -ErrorAction Stop

        # Update nonce from response
        if ($webResponse.Headers.ContainsKey('Replay-Nonce')) {
            $script:CurrentNonce = $webResponse.Headers['Replay-Nonce'][0]
        }

        # Handle both PEM (text) and DER (binary) certificate formats
        $certificatePem = $null
        $contentType = if ($webResponse.Headers.ContainsKey('Content-Type')) { $webResponse.Headers['Content-Type'][0] } else { "none" }

        if ($webResponse.Content -is [byte[]]) {
            # Response is byte array - could be either PEM-as-text or binary DER
            # Try decoding as UTF-8 text first (PEM format)
            try {
                $textContent = [System.Text.Encoding]::UTF8.GetString($webResponse.Content)

                # Check if it's valid PEM format
                if ($textContent -match '-----BEGIN CERTIFICATE-----') {
                    # PEM format as UTF-8 bytes - use as-is
                    Write-LogDebug -Message "Certificate received as PEM text (UTF-8 byte array)" -Context @{
                        content_type = $contentType
                        content_length_bytes = $webResponse.Content.Length
                    }
                    $certificatePem = $textContent
                }
                else {
                    # Not PEM - treat as binary DER
                    Write-LogDebug -Message "Certificate received in DER format (binary), converting to PEM" -Context @{
                        content_type = $contentType
                        content_length_bytes = $webResponse.Content.Length
                    }

                    # Convert DER bytes to base64
                    $base64Cert = [Convert]::ToBase64String($webResponse.Content)

                    # Wrap in PEM format with line breaks every 64 characters
                    $pemLines = @()
                    $pemLines += "-----BEGIN CERTIFICATE-----"
                    for ($i = 0; $i -lt $base64Cert.Length; $i += 64) {
                        $lineLength = [Math]::Min(64, $base64Cert.Length - $i)
                        $pemLines += $base64Cert.Substring($i, $lineLength)
                    }
                    $pemLines += "-----END CERTIFICATE-----"

                    $certificatePem = $pemLines -join "`n"
                }
            }
            catch {
                # UTF-8 decode failed - must be binary DER
                Write-LogDebug -Message "Certificate is binary DER (UTF-8 decode failed), converting to PEM" -Context @{
                    content_type = $contentType
                    content_length_bytes = $webResponse.Content.Length
                }

                # Convert DER bytes to base64
                $base64Cert = [Convert]::ToBase64String($webResponse.Content)

                # Wrap in PEM format with line breaks every 64 characters
                $pemLines = @()
                $pemLines += "-----BEGIN CERTIFICATE-----"
                for ($i = 0; $i -lt $base64Cert.Length; $i += 64) {
                    $lineLength = [Math]::Min(64, $base64Cert.Length - $i)
                    $pemLines += $base64Cert.Substring($i, $lineLength)
                }
                $pemLines += "-----END CERTIFICATE-----"

                $certificatePem = $pemLines -join "`n"
            }
        }
        elseif ($webResponse.Content -is [string]) {
            # Text PEM format - use directly
            Write-LogDebug -Message "Certificate received in PEM format (text string)" -Context @{
                content_type = $contentType
                content_length = $webResponse.Content.Length
            }
            $certificatePem = $webResponse.Content
        }
        else {
            throw "Unexpected certificate response type: $($webResponse.Content.GetType().FullName)"
        }

        # Validate response contains certificate
        if (-not ($certificatePem -match '-----BEGIN CERTIFICATE-----')) {
            throw "Invalid certificate response: no PEM certificate blocks found"
        }

        Write-LogInfo -Message "Certificate downloaded" -Context @{
            certificate_url = $CertificateUrl
            size_bytes = $certificatePem.Length
        }

        return $certificatePem
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorBody = $null

        if ($_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($_.ErrorDetails.Message)) {
            try {
                $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json
            }
            catch {
                Out-Null
            }
        }

        Write-LogError -Message "Certificate download failed" -Context @{
            function = "Get-AcmeCertificate"
            certificate_url = $CertificateUrl
            status_code = $statusCode
            error_type = $errorBody.type
            error_detail = $errorBody.detail
            error = $_.Exception.Message
        }
        throw
    }
}

# ============================================================================
# MODULE EXPORTS
# ============================================================================

# Export only public functions
Export-ModuleMember -Function @(
    'Get-AcmeDirectory',
    'New-JwsSignedRequest',
    'New-AcmeAccount',
    'Get-AcmeAccount',
    'New-AcmeOrder',
    'Get-AcmeAuthorization',
    'Complete-Http01Challenge',
    'Wait-ChallengeValidation',
    'Complete-AcmeOrder',
    'Get-AcmeCertificate'
)
