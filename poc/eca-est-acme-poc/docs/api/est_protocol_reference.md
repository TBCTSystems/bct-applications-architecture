# EST Protocol Reference - ECA PoC

## Document Overview

This document provides a comprehensive reference for the EST (Enrollment over Secure Transport) protocol implementation used in the Edge Certificate Agent (ECA) Proof of Concept system. It describes the EST protocol endpoints, request/response formats, authentication mechanisms (bootstrap token and mTLS), content type encoding (PKCS#10 and PKCS#7), error handling strategies, and provides concrete examples for implementing the EST client workflow.

**Scope**: This reference focuses specifically on the EST protocol subset used by the ECA-EST agent for automated client certificate lifecycle management with bootstrap token-based initial enrollment and certificate-based re-enrollment. This document covers the integration with Smallstep step-ca as the Certificate Authority and the specific EST provisioner configuration used in this PoC.

**Intended Audience**: Developers implementing EST client logic for the ECA-EST agent, system architects reviewing the protocol implementation, and operators troubleshooting client certificate enrollment and renewal issues.

**Related Documentation**: See `docs/ARCHITECTURE.md` (Section 3.7.4) for EST protocol overview, `docs/diagrams/est_enrollment_sequence.puml` for detailed interaction flow diagrams, and `pki/config/provisioners.json` for EST provisioner configuration.

---

## 1. Protocol Overview

### 1.1. EST Protocol Introduction

EST (Enrollment over Secure Transport) is a standardized protocol defined in **RFC 7030** that enables automated certificate enrollment and renewal between clients and Certificate Authorities. Originally designed to support IoT devices and enterprise endpoints requiring machine identity certificates, EST provides a simple HTTP-based mechanism for certificate lifecycle management.

The protocol is built on RESTful HTTP APIs with specialized MIME types for cryptographic payloads, making it accessible to a wide variety of programming languages and platforms. Unlike ACME's focus on server certificates with domain validation, EST is designed for **client certificate enrollment** where authentication relies on either shared secrets (bootstrap tokens) or existing certificates (for renewal).

EST's primary innovation is the dual authentication model:
1. **Initial Enrollment**: Uses a bootstrap token (shared secret) for first-time enrollment
2. **Re-Enrollment**: Uses the existing certificate via mTLS for subsequent renewals

This approach enables secure device provisioning in factory environments (with pre-configured tokens) while supporting automated renewal without operator intervention once the initial certificate is installed.

### 1.2. EST in the ECA PoC Context

The ECA-EST agent implements EST protocol (as defined in RFC 7030) to manage client certificates for mTLS authentication. The implementation uses **bootstrap token authentication** for initial enrollment and **mTLS (mutual TLS) authentication** for re-enrollment, enabling fully automated client certificate lifecycle management.

**Key workflow phases**:

1. **Initial Enrollment** (first time):
   - Detect missing client certificate
   - Authenticate with bootstrap token (HTTP Bearer authentication)
   - Generate new RSA-2048 key pair
   - Submit CSR to `/simpleenroll` endpoint
   - Receive signed certificate in PKCS#7 format
   - Install certificate and private key to shared volume

2. **Re-Enrollment** (renewal):
   - Detect certificate approaching expiration (75% lifetime threshold)
   - Authenticate with existing client certificate (mTLS)
   - Generate new RSA-2048 key pair (fresh keys for rotation)
   - Submit new CSR to `/simplereenroll` endpoint
   - Receive new signed certificate in PKCS#7 format
   - Replace old certificate and key with new ones

The ECA PoC integrates with **Smallstep step-ca** as the Certificate Authority. step-ca provides a modern, cloud-native PKI platform with full EST protocol support, making it ideal for containerized edge environments. The CA is configured with short-lived certificates (10 minute default lifetime in the PoC) to demonstrate rapid renewal cycles and automated lifecycle management.

### 1.3. Implementation Scope

**Supported Features**:
- EST protocol (RFC 7030 compliant)
- Bootstrap token authentication (HTTP Bearer) for initial enrollment
- Client certificate authentication (mTLS) for re-enrollment
- RSA-2048 key generation with SHA-256 signature algorithm
- PKCS#10 CSR format (application/pkcs10)
- PKCS#7 certificate response format (application/pkcs7-mime)
- Base64 encoding for binary payloads in HTTP transport
- CA certificates retrieval (`/cacerts` endpoint)
- Exponential backoff retry logic for transient errors
- Error recovery mechanisms (401 token errors, 403 certificate expiry)

**Not Implemented** (out of scope for this PoC):
- Certificate revocation (not required for short-lived certificates)
- Server-side key generation (CSR attributes requesting CA to generate keys)
- Full CMC (Certificate Management over CMS) support
- TPM-bound keys or hardware security module integration
- Certificate distribution to multiple endpoints

This focused implementation scope aligns with the PoC objectives of demonstrating automated client certificate management for containerized services using the most straightforward EST enrollment methods.

---

## 2. Authentication Mechanisms

EST protocol supports two distinct authentication methods depending on whether the client already possesses a valid certificate. Understanding these authentication mechanisms is critical for implementing a robust EST client.

### 2.1. Bootstrap Token Authentication (Initial Enrollment)

**Use Case**: First-time enrollment when the client has no certificate

**Mechanism**: HTTP Bearer token authentication

Bootstrap tokens are shared secrets provisioned to devices during manufacturing, factory configuration, or initial deployment. In the ECA PoC, the bootstrap token simulates a factory-provisioned secret that authenticates the device for its first certificate enrollment.

**Authentication Flow**:
1. Client retrieves bootstrap token from configuration (`EST_BOOTSTRAP_TOKEN` environment variable)
2. Client includes token in HTTP `Authorization` header with Bearer scheme
3. step-ca validates token against configured provisioner secrets
4. If valid, step-ca processes CSR and issues certificate
5. If invalid, step-ca returns 401 Unauthorized

**HTTP Header Format**:
```http
Authorization: Bearer factory-secret-token-12345
```

**Example Request**:
```http
POST /.well-known/est/est-provisioner/simpleenroll HTTP/1.1
Host: pki:9000
Authorization: Bearer factory-secret-token-12345
Content-Type: application/pkcs10
Content-Length: 892

MIICmzCCAYMCAQAwGDEWMBQGA1UEAwwNY2xpZW50LWRldmljZS0wMDEwggEiMA0G...
```

**Security Considerations**:
- **Token Storage**: Bootstrap tokens must be stored securely (encrypted at rest, restricted file permissions)
- **Token Rotation**: Production deployments should rotate tokens periodically and support token revocation
- **Single-Use Tokens**: For high-security environments, tokens should be single-use and expire after first enrollment
- **Token Transmission**: Tokens are transmitted over HTTPS (TLS) to prevent interception
- **Token Leakage**: Compromised tokens allow unauthorized certificate issuance—monitor for unusual enrollment patterns

**PoC Configuration**:
The bootstrap token is configured via the `EST_BOOTSTRAP_TOKEN` environment variable in the ECA-EST agent container. For demonstration purposes, a static token is used. Production deployments should implement secure token provisioning mechanisms (e.g., cloud secret management, hardware TPM attestation).

### 2.2. Client Certificate Authentication (Re-Enrollment)

**Use Case**: Certificate renewal when the client possesses a valid certificate

**Mechanism**: Mutual TLS (mTLS) authentication

Client certificate authentication uses the existing certificate and private key to establish mTLS with the CA. This provides strong cryptographic authentication without requiring a shared secret, enabling fully automated renewal.

**Authentication Flow**:
1. Client reads existing certificate (`client.crt`) and private key (`client.key`) from volume
2. Client establishes TLS connection with step-ca, presenting client certificate
3. step-ca validates certificate chain, expiration, and revocation status
4. If valid, TLS handshake completes with mutual authentication
5. Client submits CSR over mTLS-authenticated connection
6. step-ca issues new certificate

**PowerShell Implementation**:
```powershell
# Load existing client certificate with private key
$certWithKey = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
    "/certs/client/client.crt",
    (Get-Content "/certs/client/client.key" -Raw),
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
)

# Make request with client certificate for mTLS
$response = Invoke-RestMethod `
    -Uri "https://pki:9000/.well-known/est/est-provisioner/simplereenroll" `
    -Method Post `
    -Certificate $certWithKey `
    -ContentType "application/pkcs10" `
    -Body $csrBase64
```

**Certificate Requirements**:
- Certificate must be issued by the same step-ca instance (or trusted CA chain)
- Certificate must not be expired at the time of re-enrollment
- Certificate must not be revoked (step-ca checks revocation status)
- Certificate must contain valid Subject/Issuer fields
- Private key must be available and match the certificate public key

**Security Considerations**:
- **Private Key Protection**: Client private keys must have restrictive file permissions (0600) and never be transmitted
- **Certificate Expiration**: Clients must renew before certificate expiration to maintain mTLS authentication capability
- **Clock Synchronization**: Time skew between client and CA can cause premature expiration failures—use NTP
- **Certificate Validation**: step-ca validates full certificate chain including intermediate CAs
- **Revocation Checking**: If certificate is revoked, mTLS authentication fails with 403 Forbidden

**Error Recovery**:
If re-enrollment fails due to certificate expiration (403 Forbidden), the agent can recover by:
1. Deleting the expired certificate (`client.crt`)
2. Triggering initial enrollment using bootstrap token
3. Obtaining a fresh certificate for future re-enrollments

This recovery mechanism ensures the agent can self-heal from certificate expiration scenarios without operator intervention (assuming bootstrap token is still valid).

---

## 3. Content Types and Encoding

EST protocol uses specialized MIME types for cryptographic payloads that differ from typical JSON APIs. Understanding these content types and their encoding is essential for correct implementation.

### 3.1. PKCS#10 Certificate Signing Request (CSR)

**MIME Type**: `application/pkcs10`

**Format**: PKCS#10 (Public Key Cryptography Standards #10) is the standard format for Certificate Signing Requests, defined in RFC 2986. A CSR contains:
- **Subject**: Distinguished Name (DN) identifying the certificate subject (e.g., `CN=client-device-001`)
- **Public Key**: The public key to be certified (corresponding private key held by client)
- **Attributes**: Optional attributes such as Subject Alternative Names (SANs)
- **Signature**: CSR is self-signed by the private key to prove possession

**Encoding for EST**:
1. Generate CSR in DER (Distinguished Encoding Rules) binary format
2. Base64-encode the DER bytes (standard base64, not base64url)
3. Transmit base64-encoded CSR as HTTP request body

**PowerShell CSR Generation Example**:
```powershell
# Generate RSA-2048 key pair
$rsa = [System.Security.Cryptography.RSA]::Create(2048)
$privateKey = $rsa
$publicKey = $rsa

# Create CSR with subject CN=client-device-001
$subject = "CN=client-device-001"
$subjectDN = New-Object System.Security.Cryptography.X509Certificates.X500DistinguishedName($subject)

# Create certificate request
$certRequest = New-Object System.Security.Cryptography.X509Certificates.CertificateRequest(
    $subjectDN,
    $rsa,
    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
)

# Create DER-encoded CSR
$csrDer = $certRequest.CreateSigningRequest()

# Base64-encode for EST transmission
$csrBase64 = [Convert]::ToBase64String($csrDer)

# Example output (truncated):
# MIICmzCCAYMCAQAwGDEWMBQGA1UEAwwNY2xpZW50LWRldmljZS0wMDEwggEiMA0G
# CSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDL8n5Z2dH3vX9pN1wK4jL0wDQYJKoZ
# ...
```

**CSR Validation**:
step-ca validates the CSR during enrollment:
- Signature verification (proves private key possession)
- Subject DN format validation
- Public key algorithm and strength validation (RSA-2048 minimum)
- Malformed CSR detection (invalid DER encoding, missing required fields)

**Common Errors**:
- **400 Bad Request**: Malformed CSR, invalid base64 encoding, or unsupported public key algorithm
- **Invalid DER encoding**: Ensure CSR is DER-encoded, not PEM-encoded (no `-----BEGIN CERTIFICATE REQUEST-----` headers)

### 3.2. PKCS#7 Certificate Response

**MIME Type**: `application/pkcs7-mime`

**Format**: PKCS#7 (also known as CMS - Cryptographic Message Syntax) is a container format for cryptographic messages, defined in RFC 5652. EST uses PKCS#7 to return signed certificates, which may include:
- **End-Entity Certificate**: The issued client certificate
- **Certificate Chain**: Intermediate CA certificates (optional, but recommended)
- **Signature**: Cryptographic signature over the certificate data (for integrity)

**Encoding for EST**:
1. step-ca generates certificate in X.509 format
2. step-ca packages certificate into PKCS#7 SignedData structure
3. step-ca encodes PKCS#7 in DER format
4. step-ca base64-encodes DER bytes for HTTP response
5. Client receives base64-encoded PKCS#7 in response body

**PowerShell PKCS#7 Parsing Example**:
```powershell
# Receive base64-encoded PKCS#7 response from EST endpoint
$response = Invoke-RestMethod `
    -Uri "https://pki:9000/.well-known/est/est-provisioner/simpleenroll" `
    -Method Post `
    -Headers @{ Authorization = "Bearer $bootstrapToken" } `
    -ContentType "application/pkcs10" `
    -Body $csrBase64

# Response is base64-encoded PKCS#7
$pkcs7Base64 = $response

# Decode base64 to binary DER
$pkcs7Der = [Convert]::FromBase64String($pkcs7Base64)

# Parse PKCS#7 using SignedCms class
$signedCms = New-Object System.Security.Cryptography.Pkcs.SignedCms
$signedCms.Decode($pkcs7Der)

# Extract certificates from PKCS#7 container
$certificates = $signedCms.Certificates

# Get the end-entity certificate (first certificate in collection)
$clientCertificate = $certificates[0]

# Export to PEM format for file storage
$certPem = "-----BEGIN CERTIFICATE-----`n"
$certPem += [Convert]::ToBase64String($clientCertificate.Export('Cert'), 'InsertLineBreaks')
$certPem += "`n-----END CERTIFICATE-----`n"

# Write to volume
Set-Content -Path "/certs/client/client.crt" -Value $certPem -NoNewline
```

**Certificate Chain Handling**:
If the PKCS#7 response contains multiple certificates (end-entity + intermediates), extract all certificates and construct the full chain:

```powershell
# Extract all certificates from PKCS#7
$allCerts = $signedCms.Certificates

# Identify end-entity certificate (issued to client subject)
$endEntityCert = $allCerts | Where-Object {
    $_.Subject -like "*CN=client-device-001*"
}

# Identify intermediate CA certificates
$intermediateCerts = $allCerts | Where-Object {
    $_.Subject -notlike "*CN=client-device-001*"
}

# Build full chain PEM file (end-entity first, then intermediates)
$chainPem = ConvertTo-PemCertificate $endEntityCert
foreach ($intermediateCert in $intermediateCerts) {
    $chainPem += ConvertTo-PemCertificate $intermediateCert
}

# Write full chain to file
Set-Content -Path "/certs/client/client.crt" -Value $chainPem -NoNewline
```

**Common Errors**:
- **Invalid PKCS#7**: Malformed response from CA (rare, indicates CA bug)
- **Empty Certificate Collection**: PKCS#7 contains no certificates (CA issuance failure)
- **SignedCms Decode Exception**: Invalid base64 encoding or corrupted response

### 3.3. Base64 Encoding Details

**Important**: EST protocol uses **standard base64 encoding** (RFC 4648), NOT base64url encoding used in ACME JWS.

**Standard Base64 Alphabet**:
- Characters: `A-Z`, `a-z`, `0-9`, `+`, `/`
- Padding: `=` (required for non-multiple-of-3 byte lengths)

**Base64url Alphabet** (NOT used in EST):
- Characters: `A-Z`, `a-z`, `0-9`, `-`, `_`
- Padding: None (or optional)

**PowerShell Base64 Encoding**:
```powershell
# Encode to standard base64 (correct for EST)
$csrBase64 = [Convert]::ToBase64String($csrDer)
# Output: MIICmzCCAYMCAQAwGDEW...==

# WRONG: Do NOT use base64url encoding
# $csrBase64Url = $csrBase64 -replace '\+', '-' -replace '/', '_' -replace '=', ''
```

**Line Breaks**:
EST protocol accepts base64 with or without line breaks. For HTTP transmission, single-line base64 (no line breaks) is recommended:

```powershell
# Single-line base64 (recommended)
$csrBase64 = [Convert]::ToBase64String($csrDer)

# Multi-line base64 with 64-character line breaks (also acceptable)
$csrBase64MultiLine = [Convert]::ToBase64String($csrDer, 'InsertLineBreaks')
```

step-ca accepts both formats, but single-line base64 is simpler and avoids potential parsing issues.

---

## 4. Initial Enrollment

Initial enrollment is the first-time certificate enrollment process using bootstrap token authentication. This section describes the complete workflow with detailed request/response examples.

### 4.1. Endpoint

**Endpoint**: `POST /.well-known/est/{provisioner}/simpleenroll`

**step-ca Concrete Path**: `POST /.well-known/est/est-provisioner/simpleenroll`

**Authentication**: Bootstrap token (HTTP Bearer)

**Content-Type**: Request: `application/pkcs10`, Response: `application/pkcs7-mime`

### 4.2. Request Format

**HTTP Headers**:
```http
POST /.well-known/est/est-provisioner/simpleenroll HTTP/1.1
Host: pki:9000
Authorization: Bearer factory-secret-token-12345
Content-Type: application/pkcs10
Content-Length: 892
```

**Required Headers**:
- **`Authorization`**: Bearer token authentication (value from `EST_BOOTSTRAP_TOKEN` environment variable)
- **`Content-Type`**: Must be `application/pkcs10` (indicates PKCS#10 CSR payload)
- **`Content-Length`**: Byte length of base64-encoded CSR

**Request Body**:
Base64-encoded PKCS#10 CSR (single-line, no PEM headers)

**Example Request Body** (truncated for readability):
```
MIICmzCCAYMCAQAwGDEWMBQGA1UEAwwNY2xpZW50LWRldmljZS0wMDEwggEiMA0G
CSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDL8n5Z2dH3vX9pN1wK4jL0wDQYJKoZ
IhvcNAQELBQADggEBAKL8n5Z2dH3vX9pN1wK4jL0wDQYJKoZIhvcNAQELBQADggE
BAM7vKQ8n5Z2dH3vX9pN1wK4jL0wDQYJKoZIhvcNAQELBQADggEBAKL8n5Z2dH3v
...
```

### 4.3. Response Format

**HTTP Status**: `200 OK` (success), `401 Unauthorized` (invalid token), `400 Bad Request` (malformed CSR)

**Response Headers**:
```http
HTTP/1.1 200 OK
Content-Type: application/pkcs7-mime
Content-Length: 1456
```

**Response Body**:
Base64-encoded PKCS#7 SignedData containing the issued certificate

**Example Response Body** (truncated for readability):
```
MIIGXwYJKoZIhvcNAQcCoIIGUDCCBkwCAQExADALBgkqhkiG9w0BBwGgggYyMIID
XTCCAkWgAwIBAgIRAKL8n5Z2dH3vX9pN1wK4jL0wDQYJKoZIhvcNAQELBQAwSDEL
MAkGA1UEBhMCVVMxCzAJBgNVBAgMAkNBMRQwEgYDVQQKDAtTbWFsbHN0ZXBsMRYw
FAYDVQQDDA1TbWFsbHN0ZXAgQ0EwHhcNMjUxMDI0MTAwMDE1WhcNMjUxMDI0MTAx
MDE1WjAYMRYwFAYDVQQDDA1jbGllbnQtZGV2aWNlLTAwMTCCASIwDQYJKoZIhvcN
AQEBBQADggEPADCCAQoCggEBAMvyflnZ0fe9f2k3XAriMvTANBgkqhkiG9w0BAQE
...
```

### 4.4. Complete Workflow Example

This example demonstrates the complete initial enrollment process from CSR generation to certificate installation.

**Step 1: Generate RSA Key Pair**
```powershell
$rsa = [System.Security.Cryptography.RSA]::Create(2048)
$privateKeyPem = ConvertTo-PemPrivateKey $rsa
```

**Step 2: Generate CSR**
```powershell
$subject = "CN=client-device-001"
$subjectDN = New-Object System.Security.Cryptography.X509Certificates.X500DistinguishedName($subject)

$certRequest = New-Object System.Security.Cryptography.X509Certificates.CertificateRequest(
    $subjectDN,
    $rsa,
    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
)

$csrDer = $certRequest.CreateSigningRequest()
$csrBase64 = [Convert]::ToBase64String($csrDer)
```

**Step 3: Submit CSR to EST Endpoint**
```powershell
$bootstrapToken = $env:EST_BOOTSTRAP_TOKEN  # "factory-secret-token-12345"

$response = Invoke-RestMethod `
    -Uri "https://pki:9000/.well-known/est/est-provisioner/simpleenroll" `
    -Method Post `
    -Headers @{ Authorization = "Bearer $bootstrapToken" } `
    -ContentType "application/pkcs10" `
    -Body $csrBase64
```

**Step 4: Parse PKCS#7 Response**
```powershell
$pkcs7Der = [Convert]::FromBase64String($response)
$signedCms = New-Object System.Security.Cryptography.Pkcs.SignedCms
$signedCms.Decode($pkcs7Der)

$clientCertificate = $signedCms.Certificates[0]
$certPem = ConvertTo-PemCertificate $clientCertificate
```

**Step 5: Install Certificate and Private Key**
```powershell
# Write certificate (world-readable, contains only public information)
Set-Content -Path "/certs/client/client.crt" -Value $certPem -NoNewline

# Write private key with restrictive permissions (critical security requirement)
Set-Content -Path "/certs/client/client.key" -Value $privateKeyPem -NoNewline
chmod 0600 /certs/client/client.key

Write-Log -Level INFO "Initial enrollment successful, certificate valid until $($clientCertificate.NotAfter)"
```

### 4.5. Error Scenarios

**401 Unauthorized - Invalid Bootstrap Token**

**Response**:
```http
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer
Content-Type: application/json

{
  "error": "invalid_token",
  "error_description": "The access token is invalid or expired"
}
```

**Causes**:
- Bootstrap token incorrect (typo in configuration)
- Bootstrap token expired or revoked
- EST provisioner not configured with matching token
- Token missing from environment variable

**Recommended Action**:
1. Log error with token value (masked for security: `factory-***-12345`)
2. Verify `EST_BOOTSTRAP_TOKEN` environment variable value
3. Check step-ca provisioner configuration for matching token
4. Do NOT retry immediately (token unlikely to become valid without manual intervention)
5. Retry on next check cycle (60 seconds later) in case of temporary CA issue
6. Alert operator if error persists beyond 5 retry attempts

**400 Bad Request - Malformed CSR**

**Response**:
```http
HTTP/1.1 400 Bad Request
Content-Type: application/json

{
  "error": "invalid_request",
  "error_description": "Error parsing certificate request: invalid CSR encoding"
}
```

**Causes**:
- CSR is not valid DER encoding
- CSR contains unsupported public key algorithm
- CSR signature verification failed
- Base64 encoding error (e.g., used base64url instead of standard base64)

**Recommended Action**:
1. Log full error detail for debugging
2. Validate CSR generation logic (check DER encoding, base64 encoding)
3. Do NOT retry (client code bug, not transient error)
4. Fix CSR generation code before next enrollment attempt

**500 Internal Server Error - CA Failure**

**Response**:
```http
HTTP/1.1 500 Internal Server Error
Content-Type: application/json

{
  "error": "server_error",
  "error_description": "Internal server error"
}
```

**Causes**:
- step-ca database unavailable
- step-ca cryptographic operation failure (HSM error, signing failure)
- step-ca configuration error

**Recommended Action**:
1. Log error with timestamp
2. Retry with exponential backoff (initial delay: 30 seconds, max delay: 10 minutes, max retries: 10)
3. If error persists beyond 1 hour, alert operator for CA health check
4. 500 errors are often transient and resolve during CA restart or failover

---

## 5. Re-Enrollment

Re-enrollment is the certificate renewal process using existing certificate-based mTLS authentication. This section describes the complete workflow with detailed request/response examples.

### 5.1. Endpoint

**Endpoint**: `POST /.well-known/est/{provisioner}/simplereenroll`

**step-ca Concrete Path**: `POST /.well-known/est/est-provisioner/simplereenroll`

**Authentication**: Client certificate (mTLS)

**Content-Type**: Request: `application/pkcs10`, Response: `application/pkcs7-mime`

### 5.2. Request Format

**HTTP Headers**:
```http
POST /.well-known/est/est-provisioner/simplereenroll HTTP/1.1
Host: pki:9000
Content-Type: application/pkcs10
Content-Length: 892
```

**Required Headers**:
- **`Content-Type`**: Must be `application/pkcs10` (indicates PKCS#10 CSR payload)
- **`Content-Length`**: Byte length of base64-encoded CSR

**TLS Client Certificate**: Existing certificate and private key are provided at the TLS layer (not in HTTP headers). PowerShell's `Invoke-RestMethod` uses the `-Certificate` parameter to provide the client certificate for mTLS.

**Request Body**:
Base64-encoded PKCS#10 CSR (same format as initial enrollment)

**Example Request Body** (truncated):
```
MIICmzCCAYMCAQAwGDEWMBQGA1UEAwwNY2xpZW50LWRldmljZS0wMDEwggEiMA0G
CSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDL8n5Z2dH3vX9pN1wK4jL0wDQYJKoZ
...
```

### 5.3. mTLS Setup in PowerShell

**Loading Client Certificate with Private Key**:

The client certificate and private key must be loaded into an `X509Certificate2` object with the private key attached. This is more complex than simply reading PEM files because the certificate and key are stored separately.

**Method 1: Load PFX/PKCS#12 Bundle** (recommended if available):
```powershell
# If certificate and key are already in PFX format with password protection
$certWithKey = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
    "/certs/client/client.pfx",
    "password",
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
)
```

**Method 2: Load PEM Certificate and Key Separately** (typical for EST):
```powershell
# Read PEM certificate file
$certPem = Get-Content "/certs/client/client.crt" -Raw

# Read PEM private key file
$keyPem = Get-Content "/certs/client/client.key" -Raw

# Parse certificate (public key only)
$certBytes = [Convert]::FromBase64String(
    ($certPem -replace "-----BEGIN CERTIFICATE-----", "") `
             -replace "-----END CERTIFICATE-----", "" `
             -replace "`n", "" `
             -replace "`r", ""
)
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certBytes)

# Parse private key (RSA PEM format)
$keyBytes = [Convert]::FromBase64String(
    ($keyPem -replace "-----BEGIN (RSA )?PRIVATE KEY-----", "") `
            -replace "-----END (RSA )?PRIVATE KEY-----", "" `
            -replace "`n", "" `
            -replace "`r", ""
)
$rsa = [System.Security.Cryptography.RSA]::Create()
$rsa.ImportRSAPrivateKey($keyBytes, [ref]$null)

# Combine certificate and private key
$certWithKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::CopyWithPrivateKey(
    $cert,
    $rsa
)
```

**Method 3: Use OpenSSL to Create PFX** (simplest workaround):
```powershell
# Use OpenSSL to combine PEM cert + key into PFX
openssl pkcs12 -export `
    -in /certs/client/client.crt `
    -inkey /certs/client/client.key `
    -out /certs/client/client.pfx `
    -password pass:temppassword

# Load PFX with private key
$certWithKey = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
    "/certs/client/client.pfx",
    "temppassword",
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
)
```

### 5.4. Making mTLS Request

**PowerShell Example**:
```powershell
# Load certificate with private key (using one of the methods above)
$certWithKey = # ... (see section 5.3)

# Generate new CSR for renewal (new key pair for key rotation)
$newRsa = [System.Security.Cryptography.RSA]::Create(2048)
$newCsrDer = # ... (same CSR generation as initial enrollment)
$newCsrBase64 = [Convert]::ToBase64String($newCsrDer)

# Make re-enrollment request with mTLS client certificate
$response = Invoke-RestMethod `
    -Uri "https://pki:9000/.well-known/est/est-provisioner/simplereenroll" `
    -Method Post `
    -Certificate $certWithKey `
    -ContentType "application/pkcs10" `
    -Body $newCsrBase64

# Response is base64-encoded PKCS#7 (same format as initial enrollment)
$pkcs7Der = [Convert]::FromBase64String($response)
# ... (parse PKCS#7 same as initial enrollment)
```

**TLS Handshake Flow**:
1. Client initiates TLS connection to step-ca
2. Client sends ClientHello with supported cipher suites
3. step-ca sends ServerHello + server certificate + CertificateRequest
4. Client sends client certificate (`client.crt`) + CertificateVerify (signed with `client.key`)
5. step-ca validates client certificate chain, expiration, revocation status
6. TLS handshake completes with mutual authentication
7. HTTP POST request with CSR is sent over mTLS-authenticated connection

### 5.5. Response Format

**HTTP Status**: `200 OK` (success), `403 Forbidden` (invalid/expired certificate), `400 Bad Request` (malformed CSR)

**Response Headers**:
```http
HTTP/1.1 200 OK
Content-Type: application/pkcs7-mime
Content-Length: 1456
```

**Response Body**:
Base64-encoded PKCS#7 SignedData containing the new certificate (identical format to initial enrollment response)

### 5.6. Complete Workflow Example

**Step 1: Check Certificate Lifetime**
```powershell
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2("/certs/client/client.crt")
$lifetime = ($cert.NotAfter - $cert.NotBefore).TotalSeconds
$elapsed = ([DateTime]::UtcNow - $cert.NotBefore).TotalSeconds
$percentElapsed = ($elapsed / $lifetime) * 100

if ($percentElapsed -gt 75) {
    Write-Log -Level INFO "Certificate renewal threshold exceeded (${percentElapsed}% > 75%), triggering re-enrollment"
    # Proceed with re-enrollment
}
```

**Step 2: Generate New Key Pair and CSR**
```powershell
# Generate NEW key pair (key rotation best practice)
$newRsa = [System.Security.Cryptography.RSA]::Create(2048)
$newPrivateKeyPem = ConvertTo-PemPrivateKey $newRsa

# Generate CSR with same subject as existing certificate
$subject = $cert.Subject  # "CN=client-device-001"
$subjectDN = New-Object System.Security.Cryptography.X509Certificates.X500DistinguishedName($subject)

$certRequest = New-Object System.Security.Cryptography.X509Certificates.CertificateRequest(
    $subjectDN,
    $newRsa,
    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
)

$csrDer = $certRequest.CreateSigningRequest()
$csrBase64 = [Convert]::ToBase64String($csrDer)
```

**Step 3: Load Existing Certificate for mTLS**
```powershell
# Use OpenSSL to create PFX from PEM cert + key
openssl pkcs12 -export `
    -in /certs/client/client.crt `
    -inkey /certs/client/client.key `
    -out /tmp/client-mtls.pfx `
    -password pass:temppassword

$certWithKey = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
    "/tmp/client-mtls.pfx",
    "temppassword",
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
)
```

**Step 4: Submit CSR with mTLS Authentication**
```powershell
$response = Invoke-RestMethod `
    -Uri "https://pki:9000/.well-known/est/est-provisioner/simplereenroll" `
    -Method Post `
    -Certificate $certWithKey `
    -ContentType "application/pkcs10" `
    -Body $csrBase64
```

**Step 5: Parse and Install New Certificate**
```powershell
$pkcs7Der = [Convert]::FromBase64String($response)
$signedCms = New-Object System.Security.Cryptography.Pkcs.SignedCms
$signedCms.Decode($pkcs7Der)

$newCertificate = $signedCms.Certificates[0]
$newCertPem = ConvertTo-PemCertificate $newCertificate

# Atomic replacement: Write new cert/key, then overwrite old files
Set-Content -Path "/certs/client/client.crt.new" -Value $newCertPem -NoNewline
Set-Content -Path "/certs/client/client.key.new" -Value $newPrivateKeyPem -NoNewline
chmod 0600 /certs/client/client.key.new

Move-Item -Path "/certs/client/client.crt.new" -Destination "/certs/client/client.crt" -Force
Move-Item -Path "/certs/client/client.key.new" -Destination "/certs/client/client.key" -Force

Write-Log -Level INFO "Re-enrollment successful, new certificate valid until $($newCertificate.NotAfter)"
```

### 5.7. Error Scenarios

**403 Forbidden - Certificate Expired or Invalid**

**Response**:
```http
HTTP/1.1 403 Forbidden
Content-Type: application/json

{
  "error": "invalid_client",
  "error_description": "Client certificate expired or invalid"
}
```

**Causes**:
- Existing certificate expired before renewal attempt
- Certificate revoked by CA
- Certificate not issued by step-ca (untrusted chain)
- Clock skew causing premature expiration detection

**Recommended Action**:
1. Log error with certificate details (subject, expiry, issuer)
2. Check certificate expiration: `openssl x509 -in /certs/client/client.crt -noout -enddate`
3. Check system clock synchronization (NTP)
4. **Recovery**: Delete expired certificate and trigger initial enrollment with bootstrap token:
   ```powershell
   Remove-Item /certs/client/client.crt -Force
   Remove-Item /certs/client/client.key -Force
   Write-Log -Level WARN "Certificate expired, deleted cert to trigger initial enrollment"
   # Next check cycle will detect missing certificate and perform initial enrollment
   ```
5. Verify bootstrap token is still valid for recovery enrollment

**TLS Handshake Failure - Certificate Not Trusted**

**Error**:
```
Invoke-RestMethod: The remote certificate is invalid according to the validation procedure
```

**Causes**:
- step-ca root CA not in system trust store
- step-ca intermediate CA changed (certificate chain validation failure)
- Client certificate chain incomplete

**Recommended Action**:
1. Verify step-ca CA certificates are installed in trust store
2. Check CA certificate fingerprint matches expected value
3. Use `-SkipCertificateCheck` parameter for testing (NOT for production)
4. Validate certificate chain: `openssl verify -CAfile /path/to/ca.crt /certs/client/client.crt`

---

## 6. CA Certificates Retrieval

The `/cacerts` endpoint allows clients to retrieve the CA's certificate chain for trust store management. This is useful for initial setup and for detecting CA certificate rotation.

### 6.1. Endpoint

**Endpoint**: `GET /.well-known/est/{provisioner}/cacerts`

**step-ca Concrete Path**: `GET /.well-known/est/est-provisioner/cacerts`

**Authentication**: None required (public endpoint)

**Content-Type**: Response: `application/pkcs7-mime`

### 6.2. Use Case

**When to Use**:
1. **Initial Agent Setup**: Download CA certificates to establish trust before first enrollment
2. **CA Certificate Rotation**: Detect when CA certificates have been updated
3. **Trust Store Validation**: Verify the agent has the correct CA certificates installed

**Trust Store Management**:
The CA certificates returned by this endpoint should be installed in the system trust store (for HTTPS validation) and optionally written to a local file for mTLS certificate validation.

### 6.3. Request and Response

**Request**:
```http
GET /.well-known/est/est-provisioner/cacerts HTTP/1.1
Host: pki:9000
```

**Response** (200 OK):
```http
HTTP/1.1 200 OK
Content-Type: application/pkcs7-mime
Content-Length: 2048

MIIGXwYJKoZIhvcNAQcCoIIGUDCCBkwCAQExADALBgkqhkiG9w0BBwGgggYyMIID
XTCCAkWgAwIBAgIRAKL8n5Z2dH3vX9pN1wK4jL0wDQYJKoZIhvcNAQELBQAwSDEL
...
(base64-encoded PKCS#7 containing root + intermediate CA certificates)
```

### 6.4. Parsing CA Certificates

**PowerShell Example**:
```powershell
# Fetch CA certificates
$response = Invoke-RestMethod `
    -Uri "https://pki:9000/.well-known/est/est-provisioner/cacerts" `
    -Method Get `
    -SkipCertificateCheck  # Required if CA certs not yet trusted

# Parse PKCS#7 response
$pkcs7Der = [Convert]::FromBase64String($response)
$signedCms = New-Object System.Security.Cryptography.Pkcs.SignedCms
$signedCms.Decode($pkcs7Der)

# Extract all CA certificates
$caCertificates = $signedCms.Certificates

# Write to trust store files
$rootCa = $caCertificates | Where-Object { $_.Issuer -eq $_.Subject }  # Self-signed root
$intermediateCa = $caCertificates | Where-Object { $_.Issuer -ne $_.Subject }  # Intermediate

$rootCaPem = ConvertTo-PemCertificate $rootCa
$intermediateCaPem = ConvertTo-PemCertificate $intermediateCa

Set-Content -Path "/usr/local/share/ca-certificates/step-ca-root.crt" -Value $rootCaPem -NoNewline
Set-Content -Path "/usr/local/share/ca-certificates/step-ca-intermediate.crt" -Value $intermediateCaPem -NoNewline

# Update system trust store (Linux)
update-ca-certificates

Write-Log -Level INFO "CA certificates downloaded and installed to trust store"
```

### 6.5. Periodic CA Certificate Updates

**Best Practice**: Poll the `/cacerts` endpoint periodically (e.g., daily) to detect CA certificate rotation:

```powershell
# Fetch current CA certificates
$currentCaCerts = Get-CaCertificates  # From /cacerts endpoint

# Compare with locally cached CA certificates
$cachedCaCerts = Get-Content "/var/lib/eca-est/ca-certs-cache.pem" -Raw

if ($currentCaCerts -ne $cachedCaCerts) {
    Write-Log -Level WARN "CA certificate change detected, updating trust store"
    Update-TrustStore $currentCaCerts
    Set-Content -Path "/var/lib/eca-est/ca-certs-cache.pem" -Value $currentCaCerts -NoNewline
}
```

---

## 7. Error Handling

Robust error handling is essential for reliable automated certificate management. This section provides a comprehensive reference for EST protocol errors and recovery strategies.

### 7.1. HTTP Status Codes

| Status Code | Error Type | Meaning | Common Causes | Retry Strategy | Max Retries |
|-------------|-----------|---------|---------------|----------------|-------------|
| **400 Bad Request** | Client Error | CSR malformed or invalid | Invalid DER encoding, unsupported key algorithm, base64 encoding error | **No** (fix client code) | 0 |
| **401 Unauthorized** | Auth Error | Bootstrap token invalid | Token expired/revoked, typo in config, provisioner not configured | **Yes** (exponential backoff) | 3 |
| **403 Forbidden** | Auth Error | Client certificate rejected | Certificate expired, revoked, or untrusted chain | **Recovery** (delete cert, use bootstrap token) | 1 |
| **404 Not Found** | Client Error | Endpoint does not exist | Incorrect URL, provisioner name typo | **No** (fix client code) | 0 |
| **500 Internal Server Error** | Server Error | CA internal failure | Database error, HSM failure, config error | **Yes** (exponential backoff) | 10 |
| **503 Service Unavailable** | Server Error | CA temporarily unavailable | Maintenance, overload, startup | **Yes** (exponential backoff) | 10 |

### 7.2. Error Scenarios and Recovery Actions

#### 400 Bad Request - Malformed CSR

**Example Response**:
```json
{
  "error": "invalid_request",
  "error_description": "Error parsing certificate request: invalid CSR encoding"
}
```

**Recovery Action**:
1. Log full error detail including CSR (base64-encoded) for debugging
2. Validate CSR generation logic:
   - Ensure DER encoding (not PEM)
   - Ensure standard base64 encoding (not base64url)
   - Verify public key algorithm is supported (RSA-2048 minimum)
3. **Do NOT retry** (client bug, not transient error)
4. Fix CSR generation code before next enrollment attempt
5. Alert developer for code review

#### 401 Unauthorized - Invalid Bootstrap Token

**Example Response**:
```json
{
  "error": "invalid_token",
  "error_description": "The access token is invalid or expired"
}
```

**Recovery Action**:
1. Log error with masked token (e.g., `factory-***-12345`)
2. Verify `EST_BOOTSTRAP_TOKEN` environment variable value
3. Check step-ca provisioner configuration for matching token
4. Retry with exponential backoff:
   - Initial delay: 5 seconds
   - Max delay: 5 minutes
   - Max retries: 3
5. If error persists after 3 retries, alert operator:
   - Message: "EST initial enrollment failed: Invalid bootstrap token after 3 retry attempts"
   - Action required: Verify token value and provisioner configuration
6. Continue retry attempts on subsequent check cycles (may resolve if token is updated externally)

#### 403 Forbidden - Certificate Expired or Invalid

**Example Response**:
```json
{
  "error": "invalid_client",
  "error_description": "Client certificate expired or invalid"
}
```

**Recovery Action**:
1. Log certificate details (subject, expiry, issuer)
2. Check certificate expiration:
   ```powershell
   $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2("/certs/client/client.crt")
   $daysUntilExpiry = ($cert.NotAfter - [DateTime]::UtcNow).TotalDays

   if ($daysUntilExpiry -lt 0) {
       Write-Log -Level ERROR "Certificate expired $([Math]::Abs($daysUntilExpiry)) days ago"
   }
   ```
3. Check system clock synchronization (NTP):
   ```bash
   timedatectl status  # Check if NTP is synchronized
   ```
4. **Automatic Recovery**: Delete expired certificate and trigger initial enrollment:
   ```powershell
   Remove-Item /certs/client/client.crt -Force
   Remove-Item /certs/client/client.key -Force
   Write-Log -Level WARN "Certificate expired or invalid, deleted to trigger initial enrollment with bootstrap token"
   ```
5. Next check cycle will detect missing certificate and perform initial enrollment (requires valid bootstrap token)
6. If bootstrap token is also invalid, alert operator for manual intervention

#### 500 Internal Server Error - CA Failure

**Example Response**:
```json
{
  "error": "server_error",
  "error_description": "Internal server error"
}
```

**Recovery Action**:
1. Log error with timestamp and full response body
2. Retry with exponential backoff:
   - Initial delay: 30 seconds
   - Max delay: 10 minutes
   - Max retries: 10
   - Jitter: ±25% of delay to prevent thundering herd
3. If error persists beyond 1 hour (accumulated retry delays), alert operator:
   - Message: "EST enrollment failed: step-ca returning 500 errors for >1 hour"
   - Action required: Check step-ca health, logs, database, HSM connectivity
4. Check step-ca health endpoint (optional):
   ```powershell
   $health = Invoke-RestMethod -Uri "https://pki:9000/health" -SkipCertificateCheck
   if ($health.status -ne "ok") {
       Write-Log -Level ERROR "step-ca health check failed: $($health.status)"
   }
   ```
5. Continue retry attempts (500 errors often transient, resolve during CA restart or failover)

#### 503 Service Unavailable - CA Temporarily Unavailable

**Example Response**:
```http
HTTP/1.1 503 Service Unavailable
Retry-After: 600
```

**Recovery Action**:
1. Check for `Retry-After` header (seconds until retry recommended)
2. Honor `Retry-After` header if present:
   ```powershell
   $retryAfterSeconds = $response.Headers['Retry-After']
   if ($retryAfterSeconds) {
       Write-Log -Level WARN "CA unavailable, retrying in $retryAfterSeconds seconds"
       Start-Sleep -Seconds $retryAfterSeconds
   }
   ```
3. If no `Retry-After` header, use exponential backoff (same as 500 errors)
4. Max delay: 30 minutes (longer than 500 errors, as 503 indicates planned maintenance)
5. Alert operator if unavailable beyond 2 hours

### 7.3. Retry Strategy Implementation

**Exponential Backoff with Jitter**:
```powershell
function Invoke-EstEnrollmentWithRetry {
    param(
        [string]$Endpoint,
        [string]$CsrBase64,
        [string]$BootstrapToken = $null,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$ClientCertificate = $null,
        [int]$MaxRetries = 5,
        [int]$BaseDelaySeconds = 5,
        [int]$MaxDelaySeconds = 300
    )

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            $requestParams = @{
                Uri = $Endpoint
                Method = 'Post'
                ContentType = 'application/pkcs10'
                Body = $CsrBase64
            }

            if ($BootstrapToken) {
                $requestParams['Headers'] = @{ Authorization = "Bearer $BootstrapToken" }
            } elseif ($ClientCertificate) {
                $requestParams['Certificate'] = $ClientCertificate
            }

            $response = Invoke-RestMethod @requestParams
            return $response  # Success
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $errorBody = $_.ErrorDetails.Message

            Write-Log -Level WARN "EST enrollment failed (attempt $attempt/$MaxRetries): HTTP $statusCode - $errorBody"

            # Don't retry client errors (4xx except 401)
            if ($statusCode -ge 400 -and $statusCode -lt 500 -and $statusCode -ne 401) {
                Write-Log -Level ERROR "Client error (HTTP $statusCode), aborting retry"
                throw
            }

            # Don't retry on last attempt
            if ($attempt -eq $MaxRetries) {
                Write-Log -Level ERROR "Max retries exceeded, enrollment failed"
                throw
            }

            # Calculate exponential backoff with jitter
            $delay = [Math]::Min($BaseDelaySeconds * [Math]::Pow(2, $attempt - 1), $MaxDelaySeconds)
            $jitter = Get-Random -Minimum 0 -Maximum ($delay * 0.25)
            $totalDelay = $delay + $jitter

            # Check for Retry-After header (503 responses)
            if ($_.Exception.Response.Headers['Retry-After']) {
                $retryAfter = [int]$_.Exception.Response.Headers['Retry-After']
                $totalDelay = [Math]::Max($totalDelay, $retryAfter)
            }

            Write-Log -Level INFO "Retrying in $totalDelay seconds..."
            Start-Sleep -Seconds $totalDelay
        }
    }
}
```

### 7.4. Logging and Alerting Guidelines

**Log Levels**:
- **ERROR**: Certificate enrollment failed after all retries, expired certificate, invalid configuration
- **WARN**: Transient errors (401, 500, 503), retry attempts, certificate approaching expiration
- **INFO**: Enrollment initiated, enrollment successful, certificate installed, CA certificate updated

**Critical Alerts** (require operator intervention):
- Initial enrollment failed after 3 retries (invalid bootstrap token)
- Re-enrollment failed with 403 and automatic recovery unsuccessful
- CA unavailable for >2 hours (sustained 500/503 errors)
- Certificate expiry imminent (<5% lifetime remaining) without successful renewal

**Warning Alerts** (monitor closely):
- Repeated 401 errors on initial enrollment (verify token configuration)
- Certificate expired and triggered automatic recovery (verify bootstrap token for recovery enrollment)
- Clock skew detected (time difference >30 seconds with CA)

**Structured Logging Format**:
```powershell
Write-Log -Level ERROR -Component "ESTClient" -Operation "InitialEnrollment" -Status "Failed" `
    -Details @{
        StatusCode = 401
        Error = "invalid_token"
        Endpoint = "/.well-known/est/est-provisioner/simpleenroll"
        Attempt = 3
        MaxRetries = 3
    }
```

---

## 8. Complete Workflow Example

This section provides an end-to-end walkthrough of the complete EST certificate lifecycle, from initial enrollment through re-enrollment, with realistic request and response examples.

**Scenario**: The ECA-EST agent needs to obtain a client certificate for mTLS authentication from step-ca PKI, then automatically renew it when 75% of the lifetime has elapsed.

**Prerequisites**:
- step-ca is running at `https://pki:9000`
- EST provisioner named `est-provisioner` is configured
- Bootstrap token `factory-secret-token-12345` is configured in `EST_BOOTSTRAP_TOKEN` environment variable
- Agent has Docker volume mounted at `/certs/client` for certificate storage

---

### Workflow Part 1: Initial Enrollment

#### Step 1: Agent Detects Missing Certificate

```powershell
# Check if certificate exists
if (-not (Test-Path "/certs/client/client.crt")) {
    Write-Log -Level INFO "No client certificate found, performing initial enrollment"
    $enrollmentType = "initial"
}
```

#### Step 2: Generate RSA-2048 Key Pair

```powershell
$rsa = [System.Security.Cryptography.RSA]::Create(2048)

# Export private key to PEM format
$privateKeyBytes = $rsa.ExportRSAPrivateKey()
$privateKeyPem = "-----BEGIN RSA PRIVATE KEY-----`n"
$privateKeyPem += [Convert]::ToBase64String($privateKeyBytes, 'InsertLineBreaks')
$privateKeyPem += "`n-----END RSA PRIVATE KEY-----`n"
```

#### Step 3: Generate Certificate Signing Request

```powershell
$subject = "CN=client-device-001"
$subjectDN = New-Object System.Security.Cryptography.X509Certificates.X500DistinguishedName($subject)

$certRequest = New-Object System.Security.Cryptography.X509Certificates.CertificateRequest(
    $subjectDN,
    $rsa,
    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
)

# Generate DER-encoded CSR
$csrDer = $certRequest.CreateSigningRequest()

# Base64-encode for HTTP transmission
$csrBase64 = [Convert]::ToBase64String($csrDer)

Write-Log -Level INFO "Generated CSR for CN=client-device-001, key size: 2048 bits"
```

**Example CSR (base64-encoded, truncated)**:
```
MIICmzCCAYMCAQAwGDEWMBQGA1UEAwwNY2xpZW50LWRldmljZS0wMDEwggEiMA0G
CSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDL8n5Z2dH3vX9pN1wK4jL0wDQYJKoZ
IhvcNAQELBQADggEBAKL8n5Z2dH3vX9pN1wK4jL0wDQYJKoZIhvcNAQELBQADggE
...
```

#### Step 4: Submit CSR to EST Endpoint with Bootstrap Token

```powershell
$bootstrapToken = $env:EST_BOOTSTRAP_TOKEN  # "factory-secret-token-12345"

Write-Log -Level INFO "Submitting CSR to EST endpoint with bootstrap token authentication"

$response = Invoke-RestMethod `
    -Uri "https://pki:9000/.well-known/est/est-provisioner/simpleenroll" `
    -Method Post `
    -Headers @{ Authorization = "Bearer $bootstrapToken" } `
    -ContentType "application/pkcs10" `
    -Body $csrBase64
```

**HTTP Request**:
```http
POST /.well-known/est/est-provisioner/simpleenroll HTTP/1.1
Host: pki:9000
Authorization: Bearer factory-secret-token-12345
Content-Type: application/pkcs10
Content-Length: 892

MIICmzCCAYMCAQAwGDEWMBQGA1UEAwwNY2xpZW50LWRldmljZS0wMDEwggEiMA0G
CSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDL8n5Z2dH3vX9pN1wK4jL0wDQYJKoZ
...
```

**HTTP Response**:
```http
HTTP/1.1 200 OK
Content-Type: application/pkcs7-mime
Content-Length: 1456

MIIGXwYJKoZIhvcNAQcCoIIGUDCCBkwCAQExADALBgkqhkiG9w0BBwGgggYyMIID
XTCCAkWgAwIBAgIRAKL8n5Z2dH3vX9pN1wK4jL0wDQYJKoZIhvcNAQELBQAwSDEL
MAkGA1UEBhMCVVMxCzAJBgNVBAgMAkNBMRQwEgYDVQQKDAtTbWFsbHN0ZXBsMRYw
FAYDVQQDDA1TbWFsbHN0ZXAgQ0EwHhcNMjUxMDI0MTAwMDE1WhcNMjUxMDI0MTAx
MDE1WjAYMRYwFAYDVQQDDA1jbGllbnQtZGV2aWNlLTAwMTCCASIwDQYJKoZIhvcN
...
```

#### Step 5: Parse PKCS#7 Response and Extract Certificate

```powershell
# Decode base64 response to binary DER
$pkcs7Der = [Convert]::FromBase64String($response)

# Parse PKCS#7 SignedData structure
$signedCms = New-Object System.Security.Cryptography.Pkcs.SignedCms
$signedCms.Decode($pkcs7Der)

# Extract certificate from PKCS#7 container
$clientCertificate = $signedCms.Certificates[0]

Write-Log -Level INFO "Certificate parsed successfully: Subject=$($clientCertificate.Subject), Expiry=$($clientCertificate.NotAfter)"

# Convert certificate to PEM format
$certPem = "-----BEGIN CERTIFICATE-----`n"
$certPem += [Convert]::ToBase64String($clientCertificate.Export('Cert'), 'InsertLineBreaks')
$certPem += "`n-----END CERTIFICATE-----`n"
```

#### Step 6: Install Certificate and Private Key to Volume

```powershell
# Write certificate (public information, world-readable)
Set-Content -Path "/certs/client/client.crt" -Value $certPem -NoNewline

# Write private key with restrictive permissions (CRITICAL SECURITY)
Set-Content -Path "/certs/client/client.key" -Value $privateKeyPem -NoNewline

# Set restrictive permissions on private key (Unix)
chmod 0600 /certs/client/client.key

Write-Log -Level INFO "Initial enrollment successful, certificate installed to /certs/client/client.crt"
Write-Log -Level INFO "Certificate valid until: $($clientCertificate.NotAfter) UTC (10 minute lifetime)"
```

**Installed Files**:
- `/certs/client/client.crt` (permissions: 0644) - PEM-encoded X.509 certificate
- `/certs/client/client.key` (permissions: 0600) - PEM-encoded RSA private key

---

### Workflow Part 2: Re-Enrollment (Certificate Renewal)

**Time Elapsed**: 8 minutes (80% of 10-minute certificate lifetime)

#### Step 1: Agent Detects Certificate Approaching Expiration

```powershell
# Read existing certificate
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2("/certs/client/client.crt")

# Calculate lifetime percentage elapsed
$lifetime = ($cert.NotAfter - $cert.NotBefore).TotalSeconds
$elapsed = ([DateTime]::UtcNow - $cert.NotBefore).TotalSeconds
$percentElapsed = ($elapsed / $lifetime) * 100

Write-Log -Level INFO "Certificate lifetime: ${percentElapsed}% elapsed (threshold: 75%)"

if ($percentElapsed -gt 75) {
    Write-Log -Level INFO "Re-enrollment threshold exceeded, performing certificate renewal"
    $enrollmentType = "re-enroll"
}
```

#### Step 2: Generate New RSA-2048 Key Pair (Key Rotation)

```powershell
# Generate FRESH key pair for new certificate (key rotation best practice)
$newRsa = [System.Security.Cryptography.RSA]::Create(2048)

# Export new private key to PEM
$newPrivateKeyBytes = $newRsa.ExportRSAPrivateKey()
$newPrivateKeyPem = "-----BEGIN RSA PRIVATE KEY-----`n"
$newPrivateKeyPem += [Convert]::ToBase64String($newPrivateKeyBytes, 'InsertLineBreaks')
$newPrivateKeyPem += "`n-----END RSA PRIVATE KEY-----`n"

Write-Log -Level INFO "Generated new RSA-2048 key pair for certificate renewal (key rotation)"
```

#### Step 3: Generate New CSR with Same Subject

```powershell
# Use same subject as existing certificate
$subject = $cert.Subject  # "CN=client-device-001"
$subjectDN = New-Object System.Security.Cryptography.X509Certificates.X500DistinguishedName($subject)

# Create CSR with new public key
$certRequest = New-Object System.Security.Cryptography.X509Certificates.CertificateRequest(
    $subjectDN,
    $newRsa,
    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
)

$csrDer = $certRequest.CreateSigningRequest()
$csrBase64 = [Convert]::ToBase64String($csrDer)
```

#### Step 4: Load Existing Certificate for mTLS Authentication

```powershell
# Use OpenSSL to create temporary PFX from PEM cert + key
$pfxPath = "/tmp/client-mtls-$(Get-Random).pfx"
$pfxPassword = "temp-$(Get-Random)"

openssl pkcs12 -export `
    -in /certs/client/client.crt `
    -inkey /certs/client/client.key `
    -out $pfxPath `
    -password "pass:$pfxPassword"

# Load PFX with private key for mTLS
$certWithKey = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
    $pfxPath,
    $pfxPassword,
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
)

Write-Log -Level INFO "Loaded existing certificate for mTLS authentication: $($certWithKey.Thumbprint)"
```

#### Step 5: Submit CSR to Re-Enrollment Endpoint with mTLS

```powershell
Write-Log -Level INFO "Submitting CSR to EST re-enrollment endpoint with mTLS authentication"

$response = Invoke-RestMethod `
    -Uri "https://pki:9000/.well-known/est/est-provisioner/simplereenroll" `
    -Method Post `
    -Certificate $certWithKey `
    -ContentType "application/pkcs10" `
    -Body $csrBase64

# Clean up temporary PFX
Remove-Item $pfxPath -Force
```

**HTTP Request** (simplified - TLS layer handles client certificate):
```http
POST /.well-known/est/est-provisioner/simplereenroll HTTP/1.1
Host: pki:9000
Content-Type: application/pkcs10
Content-Length: 892

MIICmzCCAYMCAQAwGDEWMBQGA1UEAwwNY2xpZW50LWRldmljZS0wMDEwggEiMA0G
CSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCm8p5Z2dH3vX9pN1wK4jL0wDQYJKoZ
...
(Note: Different CSR bytes due to new public key)
```

**TLS Handshake** (before HTTP request):
```
Client -> Server: ClientHello
Server -> Client: ServerHello, Certificate, CertificateRequest
Client -> Server: Certificate (client.crt), CertificateVerify (signed with client.key)
Server: Validate client certificate chain, expiration, revocation
TLS handshake complete with mutual authentication
```

**HTTP Response**:
```http
HTTP/1.1 200 OK
Content-Type: application/pkcs7-mime
Content-Length: 1456

MIIGXwYJKoZIhvcNAQcCoIIGUDCCBkwCAQExADALBgkqhkiG9w0BBwGgggYyMIID
XTCCAkWgAwIBAgIRANm9q6Z3eI4wY2qW8tH5mN4wDQYJKoZIhvcNAQELBQAwSDEL
...
(New certificate with different serial number and validity period)
```

#### Step 6: Parse and Install New Certificate

```powershell
# Parse PKCS#7 response (same as initial enrollment)
$pkcs7Der = [Convert]::FromBase64String($response)
$signedCms = New-Object System.Security.Cryptography.Pkcs.SignedCms
$signedCms.Decode($pkcs7Der)

$newCertificate = $signedCms.Certificates[0]

Write-Log -Level INFO "New certificate parsed: Subject=$($newCertificate.Subject), Expiry=$($newCertificate.NotAfter)"

# Convert to PEM
$newCertPem = "-----BEGIN CERTIFICATE-----`n"
$newCertPem += [Convert]::ToBase64String($newCertificate.Export('Cert'), 'InsertLineBreaks')
$newCertPem += "`n-----END CERTIFICATE-----`n"

# Atomic replacement: Write to temp files, then move
Set-Content -Path "/certs/client/client.crt.new" -Value $newCertPem -NoNewline
Set-Content -Path "/certs/client/client.key.new" -Value $newPrivateKeyPem -NoNewline
chmod 0600 /certs/client/client.key.new

# Atomic move (overwrite old files)
Move-Item -Path "/certs/client/client.crt.new" -Destination "/certs/client/client.crt" -Force
Move-Item -Path "/certs/client/client.key.new" -Destination "/certs/client/client.key" -Force

Write-Log -Level INFO "Re-enrollment successful, certificate renewed"
Write-Log -Level INFO "Old certificate expiry: $($cert.NotAfter), New certificate expiry: $($newCertificate.NotAfter)"
Write-Log -Level INFO "Certificate lifetime extended by 10 minutes"
```

**Workflow Complete**: Client certificate has been renewed with a fresh key pair, extending the validity period by 10 minutes. The agent will continue to monitor the new certificate and trigger re-enrollment again when 75% of the new lifetime has elapsed (in ~7.5 minutes).

---

## 9. step-ca Specific Implementation Notes

### 9.1. Provisioner Naming

The step-ca EST provisioner is configured with the name `est-provisioner` in the PoC `provisioners.json` file. This means all EST endpoint paths use the format:

```
/.well-known/est/{provisioner}/...  →  /.well-known/est/est-provisioner/...
```

When implementing the EST client, construct URLs using:

```powershell
$baseUrl = "https://pki:9000"
$provisioner = "est-provisioner"
$simpleenrollUrl = "$baseUrl/.well-known/est/$provisioner/simpleenroll"
$simplereenrollUrl = "$baseUrl/.well-known/est/$provisioner/simplereenroll"
$cacertsUrl = "$baseUrl/.well-known/est/$provisioner/cacerts"
```

**Important**: The provisioner name `est-provisioner` is specific to this PoC configuration. Production deployments may use different provisioner names, which should be configurable via environment variables.

### 9.2. Certificate Duration Configuration

The step-ca PoC is configured with short certificate lifetimes to demonstrate rapid renewal cycles:

- **Default Duration**: 10 minutes (`defaultTLSCertDuration: "10m"`)
- **Minimum Duration**: 5 minutes (`minTLSCertDuration: "5m"`)
- **Maximum Duration**: 24 hours (`maxTLSCertDuration: "24h"`)

Production step-ca deployments typically use longer durations (30-90 days for client certificates). The ECA-EST agent is configured to renew at **75% of certificate lifetime**, which translates to:

- 10-minute cert: Renew at 7.5 minutes (~2.5 minutes remaining)
- 30-day cert: Renew at 22.5 days (~7.5 days remaining)
- 90-day cert: Renew at 67.5 days (~22.5 days remaining)

This aggressive renewal threshold (75%) provides a safety margin for transient failures and ensures certificates are renewed well before expiration. The renewal threshold should be configurable via environment variables for different operational requirements.

**Configuration Example**:
```json
{
  "type": "EST",
  "name": "est-provisioner",
  "claims": {
    "minTLSCertDuration": "5m",
    "maxTLSCertDuration": "24h",
    "defaultTLSCertDuration": "10m"
  }
}
```

### 9.3. Bootstrap Token Configuration

The PoC uses a static bootstrap token for demonstration purposes. In production deployments, bootstrap tokens should be:

1. **Securely Provisioned**: Tokens should be generated during device manufacturing or initial deployment
2. **Stored Securely**: Encrypted at rest, restricted file permissions, hardware TPM integration
3. **Rotated Periodically**: Tokens should expire and be replaced on a regular schedule
4. **Single-Use (Optional)**: For high-security environments, tokens can be configured for single-use and expire after first enrollment
5. **Audited**: Token usage should be logged for security monitoring

**step-ca Bootstrap Token Configuration** (example):
step-ca EST provisioners can be configured with bootstrap tokens in the provisioner configuration or via external authentication providers (OIDC, OAuth2). For simplicity, this PoC uses a static token configured via environment variables.

Production deployments should implement secure token provisioning mechanisms such as:
- Cloud secret management services (AWS Secrets Manager, Azure Key Vault)
- Hardware TPM attestation
- PKI-based device identity (pre-provisioned device certificates)

### 9.4. step-ca Health Check

The step-ca container exposes a health check endpoint for monitoring:

```
GET https://pki:9000/health
```

**Response** (200 OK):
```json
{
  "status": "ok"
}
```

The ECA-EST agent can optionally check this endpoint before attempting EST operations to detect CA unavailability early and avoid unnecessary retries:

```powershell
try {
    $health = Invoke-RestMethod -Uri "https://pki:9000/health" -TimeoutSec 5
    if ($health.status -ne "ok") {
        Write-Log -Level WARN "step-ca health check failed: $($health.status), deferring enrollment"
        return
    }
} catch {
    Write-Log -Level WARN "step-ca health check unavailable, proceeding with enrollment attempt"
}
```

### 9.5. CA Certificate Trust Configuration

The ECA-EST agent must trust the step-ca root and intermediate CA certificates for HTTPS communication. In the PoC Docker environment, this can be configured by:

1. **Container Build-Time Installation**:
   ```dockerfile
   COPY pki/certs/root_ca.crt /usr/local/share/ca-certificates/step-ca-root.crt
   COPY pki/certs/intermediate_ca.crt /usr/local/share/ca-certificates/step-ca-intermediate.crt
   RUN update-ca-certificates
   ```

2. **Runtime Installation** (using `/cacerts` endpoint):
   ```powershell
   # Fetch CA certificates from step-ca
   $response = Invoke-RestMethod `
       -Uri "https://pki:9000/.well-known/est/est-provisioner/cacerts" `
       -Method Get `
       -SkipCertificateCheck  # Required for first fetch

   # Parse and install to system trust store
   # (See section 6.4 for complete example)
   ```

3. **Development/Testing** (skip certificate validation):
   ```powershell
   # NOT FOR PRODUCTION
   $response = Invoke-RestMethod `
       -Uri "https://pki:9000/.well-known/est/est-provisioner/simpleenroll" `
       -SkipCertificateCheck
   ```

Production deployments must distribute the step-ca root CA certificate to all agent containers and add it to the system trust store. Skipping certificate validation is acceptable for PoC/testing but creates security vulnerabilities (MITM attacks) in production.

### 9.6. EST vs. ACME Protocol Comparison

Both EST and ACME are implemented in this PoC for different certificate types:

| Feature | EST (Client Certificates) | ACME (Server Certificates) |
|---------|--------------------------|---------------------------|
| **Primary Use Case** | Client authentication (mTLS) | Server authentication (HTTPS) |
| **Authentication** | Bootstrap token (initial), mTLS (renewal) | JWS signature (account key) |
| **Domain Validation** | None (token-based trust) | HTTP-01 challenge (domain control) |
| **Content Types** | PKCS#10 (CSR), PKCS#7 (cert) | JSON (requests), PEM (cert) |
| **Complexity** | Lower (fewer steps, simpler auth) | Higher (account management, challenges, polling) |
| **Standardization** | RFC 7030 | RFC 8555 |
| **step-ca Provisioner** | `est-provisioner` | `acme` |

**When to Use**:
- **EST**: Client certificates for service-to-service mTLS, device identity, API authentication
- **ACME**: Server certificates for public HTTPS endpoints, TLS termination, web servers

---

## Conclusion

This EST Protocol Reference provides comprehensive guidance for implementing the ECA-EST agent's client certificate lifecycle management workflow. The document covers all essential EST protocol operations used in the PoC, with detailed request/response examples, authentication mechanism explanation (bootstrap token and mTLS), content type encoding (PKCS#10 and PKCS#7), robust error handling strategies, and step-ca specific implementation notes.

**Key Takeaways**:
- EST protocol enables fully automated client certificate management with dual authentication (token and mTLS)
- Bootstrap token authentication provides secure initial enrollment for devices without existing certificates
- mTLS re-enrollment enables automated renewal without operator intervention once initial certificate is installed
- PKCS#10 (CSR) and PKCS#7 (certificate) formats require careful base64 encoding and parsing using .NET cryptography classes
- Comprehensive error handling with exponential backoff ensures resilience to transient failures
- Automatic recovery from certificate expiration (403 errors) enables self-healing without operator intervention
- step-ca provides a production-ready EST implementation suitable for edge PKI deployments with configurable certificate lifetimes

**Next Steps**: Use this reference as the authoritative specification for implementing the `EstClient.psm1` module in tasks I3.T3-I3.T6, ensuring protocol compliance and robust error handling throughout the EST client implementation.

---

**Document Version**: 1.0
**Last Updated**: 2025-10-24
**Word Count**: 9,847 words
