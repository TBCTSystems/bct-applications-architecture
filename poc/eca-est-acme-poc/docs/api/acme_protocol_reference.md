# ACME Protocol Reference - ECA PoC

## Document Overview

This document provides a comprehensive reference for the ACME (Automatic Certificate Management Environment) protocol implementation used in the Edge Certificate Agent (ECA) Proof of Concept system. It describes the protocol endpoints, request/response formats, authentication mechanism, error handling strategies, and provides concrete examples for implementing the ACME client workflow.

**Scope**: This reference focuses specifically on the ACME protocol subset used by the ECA-ACME agent for automated server certificate lifecycle management with HTTP-01 challenge validation. This document covers the integration with Smallstep step-ca as the Certificate Authority.

**Intended Audience**: Developers implementing ACME client logic for the ECA-ACME agent, system architects reviewing the protocol implementation, and operators troubleshooting certificate renewal issues.

**Related Documentation**: See `docs/ARCHITECTURE.md` for complete system architecture and `docs/diagrams/acme_renewal_sequence.mmd` for detailed interaction flow diagrams.

## 1. Protocol Overview

### 1.1. ACME Protocol Introduction

ACME (Automatic Certificate Management Environment) is a standardized protocol defined in **RFC 8555** that enables automated certificate management between clients and Certificate Authorities. Originally developed by Let's Encrypt and the Internet Security Research Group (ISRG), ACME eliminates manual certificate operations by providing a machine-to-machine protocol for certificate issuance, renewal, and revocation.

The protocol is designed around RESTful HTTP APIs with JSON payloads, making it accessible to a wide variety of programming languages and platforms. ACME's primary innovation is the concept of **automated domain control validation**, where the CA can cryptographically verify that a client controls a domain name before issuing certificates for that domain.

### 1.2. ACME in the ECA PoC Context

The ECA-ACME agent implements ACME protocol v2 (as defined in RFC 8555) to manage server certificates for the NGINX target service. The implementation uses the **HTTP-01 challenge** validation method, where domain control is proven by placing a specific token at a well-known HTTP URL path on the domain being validated.

**Key workflow phases**:
1. **Account Registration**: One-time account creation with the CA using a public/private key pair for request authentication
2. **Order Creation**: Requesting a certificate for specific domain names
3. **Authorization & Challenge**: Receiving challenge details and preparing for domain validation
4. **Challenge Completion**: Placing the token file where the CA can validate it via HTTP
5. **Challenge Validation**: CA validates domain control by fetching the token
6. **Order Finalization**: Submitting the Certificate Signing Request (CSR) to the CA
7. **Certificate Download**: Retrieving the signed certificate chain

The ECA PoC integrates with **Smallstep step-ca** as the Certificate Authority. step-ca provides a modern, cloud-native PKI platform with full ACME v2 protocol support, making it ideal for containerized edge environments. The CA is configured with short-lived certificates (10 minute default lifetime in the PoC) to demonstrate rapid renewal cycles and automated lifecycle management.

### 1.3. Implementation Scope

**Supported Features**:
- ACME v2 protocol (RFC 8555 compliant)
- HTTP-01 challenge validation (domain control proof via HTTP token)
- RSA-2048 and ECDSA P-256 key generation
- Account key-based request authentication using JWS (JSON Web Signature)
- Certificate chain download in PEM format
- Exponential backoff retry logic for transient errors
- Rate limiting awareness and backoff with jitter

**Not Implemented** (out of scope for this PoC):
- DNS-01 challenge validation (requires DNS provider integration)
- TLS-ALPN-01 challenge validation (requires TLS server modification)
- Certificate revocation (optional for short-lived certificates)
- External Account Binding (EAB) for restricted CA access
- Wildcard certificates (requires DNS-01 challenge)

This focused implementation scope aligns with the PoC objectives of demonstrating automated server certificate management for containerized services using the most straightforward validation method.

## 2. Authentication Mechanism (JSON Web Signature)

### 2.1. JWS Overview

ACME protocol requests are authenticated using **JWS (JSON Web Signature)** as defined in RFC 7515. Unlike traditional API authentication using tokens or passwords, ACME uses asymmetric cryptography where each ACME account is identified by a public/private key pair. The client signs every request with its account private key, and the CA validates the signature using the account's registered public key.

This approach provides several security advantages:
- **No shared secrets**: The CA never possesses the client's private key
- **Request integrity**: Signatures protect against request tampering in transit
- **Non-repudiation**: Signed requests provide cryptographic proof of origin
- **Replay protection**: Nonces prevent replay attacks

### 2.2. JWS Structure in ACME

A JWS-signed ACME request consists of three base64url-encoded components concatenated with period separators:

```
{protected header}.{payload}.{signature}
```

**Example JWS Structure**:
```json
eyJhbGciOiJFUzI1NiIsImtpZCI6Imh0dHBzOi8vcGtpOjkwMDAvYWNtZS9hY21lL2FjY3QvMTIzIiwibm9uY2UiOiJhYmMxMjMiLCJ1cmwiOiJodHRwczovL3BraSI6OTAwMC9hY21lL2FjbWUvbmV3LW9yZGVyIn0.eyJpZGVudGlmaWVycyI6W3sidHlwZSI6ImRucyIsInZhbHVlIjoidGFyZ2V0LXNlcnZlciJ9XX0.MEUCIQCcG0NhZrZxMp1zC_JrN5IvWbF6KVmH0yTb8xLHp9jN0AIgR3vN0P8kL9xQ5bZm6tY8uWrT4jHbN2qL5kF6gH7pXc
```

Each component has a specific purpose:

1. **Protected Header** (decoded):
```json
{
  "alg": "ES256",
  "kid": "https://pki:9000/acme/acme/acct/123",
  "nonce": "abc123",
  "url": "https://pki:9000/acme/acme/new-order"
}
```

2. **Payload** (decoded):
```json
{
  "identifiers": [
    {
      "type": "dns",
      "value": "target-server"
    }
  ]
}
```

3. **Signature**: Raw cryptographic signature bytes (base64url-encoded)

### 2.3. JWS Protected Header Fields

**Required Fields**:
- **`alg`**: Signature algorithm identifier
  - `RS256`: RSA with SHA-256 (for RSA account keys)
  - `ES256`: ECDSA with P-256 curve and SHA-256 (for ECDSA account keys)

- **`nonce`**: Replay protection token obtained from CA's `newNonce` endpoint
  - CA provides fresh nonces via `Replay-Nonce` HTTP header in every response
  - Each nonce can only be used once
  - Client must request a new nonce for each signed request

- **`url`**: Full URL of the ACME endpoint being called
  - Prevents signature reuse across different endpoints
  - Must exactly match the request URL (including scheme, host, path)

**Key Identification** (one of the following):
- **`kid`**: Account key identifier URL (used for authenticated requests after account creation)
  - Format: `https://pki:9000/acme/{provisioner}/acct/{accountId}`
  - Used for all requests except initial account registration

- **`jwk`**: Embedded account public key (used only for new account registration)
  - Contains the full public key in JSON Web Key format
  - Only used when `kid` is not yet available (before account creation)

### 2.4. JWS Signing Process

**Implementation Steps**:

1. **Construct Protected Header**:
   ```powershell
   $protectedHeader = @{
       alg = "ES256"
       kid = $accountKeyId
       nonce = $currentNonce
       url = $requestUrl
   } | ConvertTo-Json -Compress
   ```

2. **Base64url Encode Protected Header**:
   ```powershell
   $protectedBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($protectedHeader)) -replace '\+', '-' -replace '/', '_' -replace '=', ''
   ```

3. **Base64url Encode Payload**:
   ```powershell
   $payloadJson = $requestBody | ConvertTo-Json -Compress
   $payloadBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payloadJson)) -replace '\+', '-' -replace '/', '_' -replace '=', ''
   ```

4. **Create Signing Input**:
   ```powershell
   $signingInput = "$protectedBase64.$payloadBase64"
   ```

5. **Generate Signature**:
   ```powershell
   $signatureBytes = $accountPrivateKey.SignData([Text.Encoding]::ASCII.GetBytes($signingInput), [Security.Cryptography.HashAlgorithmName]::SHA256)
   $signatureBase64 = [Convert]::ToBase64String($signatureBytes) -replace '\+', '-' -replace '/', '_' -replace '=', ''
   ```

6. **Construct Final JWS**:
   ```json
   {
     "protected": "eyJhbGciOi...",
     "payload": "eyJpZGVudGl...",
     "signature": "MEUCIQCc..."
   }
   ```

This JWS object is sent as the HTTP request body with `Content-Type: application/jose+json`.

### 2.5. Nonce Management

The CA provides a fresh nonce in the `Replay-Nonce` HTTP response header after every ACME request. Clients must:
1. Extract the nonce from the response header
2. Use it for the next request
3. Never reuse nonces across multiple requests

**Initial Nonce Retrieval**:
```
HEAD https://pki:9000/acme/acme/new-nonce
Response Headers:
  Replay-Nonce: Xj2k9pQmnVz8sG7aL4bN1rC3tY5wH6uD
```

The ECA-ACME agent maintains a nonce cache and automatically refreshes it as needed during the request workflow.

## 3. Account Management

### 3.1. Discover ACME Directory

Before performing any ACME operations, the client must discover the CA's endpoint URLs by fetching the ACME directory.

**Endpoint**: `GET /acme/{provisioner}/directory`

**step-ca Concrete Path**: `GET /acme/acme/directory` (where `acme` is the provisioner name)

**Request**:
- No authentication required (public endpoint)
- No request body

**Example Request**:
```http
GET /acme/acme/directory HTTP/1.1
Host: pki:9000
```

**Response** (200 OK):
```json
{
  "newNonce": "https://pki:9000/acme/acme/new-nonce",
  "newAccount": "https://pki:9000/acme/acme/new-account",
  "newOrder": "https://pki:9000/acme/acme/new-order",
  "revokeCert": "https://pki:9000/acme/acme/revoke-cert",
  "keyChange": "https://pki:9000/acme/acme/key-change",
  "meta": {
    "termsOfService": "https://example.com/acme/terms",
    "website": "https://github.com/smallstep/certificates",
    "caaIdentities": ["pki"]
  }
}
```

**Response Fields**:
- **`newNonce`**: URL to obtain replay nonces
- **`newAccount`**: URL for account creation/retrieval
- **`newOrder`**: URL to create new certificate orders
- **`revokeCert`**: URL to revoke certificates (not used in PoC)
- **`keyChange`**: URL to change account keys (not used in PoC)
- **`meta`**: CA metadata including terms of service and website

The client should cache these URLs for the duration of the agent session to avoid repeated directory lookups.

### 3.2. Create or Retrieve ACME Account

ACME accounts are identified by public/private key pairs. The client creates an account by sending its public key to the CA. If an account with that public key already exists, the CA returns the existing account details (idempotent operation).

**Endpoint**: `POST /acme/{provisioner}/new-account`

**step-ca Concrete Path**: `POST /acme/acme/new-account`

**Authentication**: JWS-signed request using `jwk` (embedded public key) in protected header

**Request Payload**:
```json
{
  "termsOfServiceAgreed": true,
  "contact": [
    "mailto:admin@example.com"
  ]
}
```

**Payload Fields**:
- **`termsOfServiceAgreed`**: Boolean indicating acceptance of CA's terms (required by most CAs)
- **`contact`**: Array of contact URIs (email, phone) for account recovery and notifications (optional but recommended)

**Example Request** (JWS-signed):
```json
{
  "protected": "eyJhbGciOiJFUzI1NiIsImp3ayI6eyJrdHkiOiJFQyIsImNydiI6IlAtMjU2IiwieCI6IjE4d0hMZUlnVzl3eVh5WWRpeFQ3LWlfNVozMk1wOUFqTWFjLUFsSU5lU2ciLCJ5IjoiSGxxX0JQWHBYVHQ2TTRldldRVkRCNGRCX2VQYWJLcnU5YU85MUFqX3NfSSJ9LCJub25jZSI6ImFiYzEyMyIsInVybCI6Imh0dHBzOi8vcGtpOjkwMDAvYWNtZS9hY21lL25ldy1hY2NvdW50In0",
  "payload": "eyJ0ZXJtc09mU2VydmljZUFncmVlZCI6dHJ1ZSwiY29udGFjdCI6WyJtYWlsdG86YWRtaW5AZXhhbXBsZS5jb20iXX0",
  "signature": "MEUCIQDzL9P3cN6kV8sR4pZ5tX7mW9qY3fG8hJ2nK4lM6vT9wgIgB7xP2dQ5sH9vK3jR8nL6mT4wY2pV7sG9hK5nM3xQ8zA"
}
```

**Response** (201 Created for new account, 200 OK for existing account):
```json
{
  "status": "valid",
  "contact": [
    "mailto:admin@example.com"
  ],
  "orders": "https://pki:9000/acme/acme/acct/evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ-PCt92wr-oA/orders"
}
```

**Response Headers**:
```http
Location: https://pki:9000/acme/acme/acct/evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ-PCt92wr-oA
Replay-Nonce: Xj2k9pQmnVz8sG7aL4bN1rC3tY5wH6uD
```

**Important**: The `Location` header contains the **account key identifier (kid)** which must be used in the `kid` field of all subsequent JWS-signed requests. The client must extract and cache this value.

**Response Fields**:
- **`status`**: Account status (`valid`, `deactivated`, `revoked`)
- **`contact`**: Confirmed contact information
- **`orders`**: URL to retrieve list of orders for this account

## 4. Order Lifecycle

The order lifecycle is the core ACME workflow where the client requests a certificate, proves domain control, submits a CSR, and downloads the issued certificate.

### 4.1. Create New Order

The client initiates certificate issuance by creating an order that specifies the domain names to be included in the certificate.

**Endpoint**: `POST /acme/{provisioner}/new-order`

**step-ca Concrete Path**: `POST /acme/acme/new-order`

**Authentication**: JWS-signed request using `kid` (account key identifier)

**Request Payload**:
```json
{
  "identifiers": [
    {
      "type": "dns",
      "value": "target-server"
    }
  ]
}
```

**Payload Fields**:
- **`identifiers`**: Array of domain identifiers to be included in the certificate
  - **`type`**: Identifier type (always `"dns"` for domain names)
  - **`value`**: Fully qualified domain name (FQDN) or hostname

For multiple domains (Subject Alternative Names):
```json
{
  "identifiers": [
    {"type": "dns", "value": "target-server"},
    {"type": "dns", "value": "www.target-server"},
    {"type": "dns", "value": "api.target-server"}
  ]
}
```

**Example Request** (JWS-signed):
```json
{
  "protected": "eyJhbGciOiJFUzI1NiIsImtpZCI6Imh0dHBzOi8vcGtpOjkwMDAvYWNtZS9hY21lL2FjY3QvZXZhR3hmQURzNnBTUmIyTEF2OUlaZjE3RHQzanV4R0otUEN0OTJ3ci1vQSIsIm5vbmNlIjoiWGoyazlwUW1uVno4c0c3YUw0Yk4xckMzdFk1d0g2dUQiLCJ1cmwiOiJodHRwczovL3BraToxOTAwMC9hY21lL2FjbWUvbmV3LW9yZGVyIn0",
  "payload": "eyJpZGVudGlmaWVycyI6W3sidHlwZSI6ImRucyIsInZhbHVlIjoidGFyZ2V0LXNlcnZlciJ9XX0",
  "signature": "MEUCIQDVZ3nX9pK7sR8mT4wY2pV7sG9hK5nM3xQ8zAIgB7xP2dQ5sH9vK3jR8nL6mT4wY2pV7sG9"
}
```

**Response** (201 Created):
```json
{
  "status": "pending",
  "expires": "2025-10-24T11:00:00Z",
  "identifiers": [
    {
      "type": "dns",
      "value": "target-server"
    }
  ],
  "authorizations": [
    "https://pki:9000/acme/acme/authz/dGFyZ2V0LXNlcnZlcg"
  ],
  "finalize": "https://pki:9000/acme/acme/order/MTEyMzQ1Njc4OQ/finalize"
}
```

**Response Headers**:
```http
Location: https://pki:9000/acme/acme/order/MTEyMzQ1Njc4OQ
Replay-Nonce: Yh3k9pQmnVz8sG7aL4bN1rC3tY5wH6uE
```

**Response Fields**:
- **`status`**: Order status (`pending` initially, transitions to `ready`, `processing`, `valid`, or `invalid`)
- **`expires`**: ISO 8601 timestamp when order expires if not completed
- **`identifiers`**: Echo of requested domain identifiers
- **`authorizations`**: Array of authorization URLs (one per identifier)
- **`finalize`**: URL to submit CSR when authorizations are complete

The client must store the `Location` header value (order URL) and the `authorizations` array for the next steps.

### 4.2. Get Authorization Details

Each domain identifier in an order requires authorization (proof of domain control). The client retrieves authorization details to obtain the challenge information.

**Endpoint**: `GET /acme/{provisioner}/authz/{authzId}`

**step-ca Concrete Path**: `GET /acme/acme/authz/dGFyZ2V0LXNlcnZlcg`

**Authentication**: No authentication required (authorization URLs contain unguessable tokens)

**Request**:
```http
GET /acme/acme/authz/dGFyZ2V0LXNlcnZlcg HTTP/1.1
Host: pki:9000
```

**Response** (200 OK):
```json
{
  "status": "pending",
  "expires": "2025-10-24T11:00:00Z",
  "identifier": {
    "type": "dns",
    "value": "target-server"
  },
  "challenges": [
    {
      "type": "http-01",
      "status": "pending",
      "url": "https://pki:9000/acme/acme/challenge/dGFyZ2V0LXNlcnZlcg/aHR0cC0wMQ",
      "token": "evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ"
    }
  ]
}
```

**Response Fields**:
- **`status`**: Authorization status (`pending`, `valid`, `invalid`, `expired`)
- **`expires`**: ISO 8601 timestamp when authorization expires
- **`identifier`**: Domain identifier being authorized
- **`challenges`**: Array of available challenge types (step-ca provides HTTP-01 for this provisioner)

**Challenge Object Fields**:
- **`type`**: Challenge type (`http-01`, `dns-01`, `tls-alpn-01`)
- **`status`**: Challenge status (`pending`, `processing`, `valid`, `invalid`)
- **`url`**: URL to notify CA that challenge is ready for validation
- **`token`**: Random token that must be served for HTTP-01 validation

The client must extract the `token` and `url` values for HTTP-01 challenge completion.

### 4.3. Complete HTTP-01 Challenge

The HTTP-01 challenge requires the client to prove domain control by serving a specific file at a well-known HTTP URL. The CA will make an HTTP GET request to validate the token.

**Preparation Steps**:

1. **Construct Key Authorization**:
   ```
   keyAuthorization = token + "." + base64url(SHA256(accountPublicKeyJWK))
   ```

   Where `accountPublicKeyJWK` is the JSON representation of the account public key.

2. **Place Token File**:
   - Write the key authorization to a file accessible at:
     ```
     http://{domain}/.well-known/acme-challenge/{token}
     ```

   - For `target-server` domain with token `evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ`:
     ```
     http://target-server/.well-known/acme-challenge/evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ
     ```

   - File content: Plain text key authorization (no HTML, no whitespace trimming)
   - Content-Type: `text/plain` or `application/octet-stream`

**Example Key Authorization**:
```
evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ.9jg46WB3rR_AHD-EBXdN7cBkH1WOu0tA3M9fm21mqTI
```

**Notify CA of Readiness**:

Once the token file is accessible, the client notifies the CA to perform validation.

**Endpoint**: `POST /acme/{provisioner}/challenge/{challengeId}`

**step-ca Concrete Path**: `POST /acme/acme/challenge/dGFyZ2V0LXNlcnZlcg/aHR0cC0wMQ`

**Authentication**: JWS-signed request using `kid`

**Request Payload**:
```json
{}
```

**Important**: The payload is an empty JSON object `{}`. The POST request simply signals readiness; no additional data is required.

**Example Request** (JWS-signed):
```json
{
  "protected": "eyJhbGciOiJFUzI1NiIsImtpZCI6Imh0dHBzOi8vcGtpOjkwMDAvYWNtZS9hY21lL2FjY3QvZXZhR3hmQURzNnBTUmIyTEF2OUlaZjE3RHQzanV4R0otUEN0OTJ3ci1vQSIsIm5vbmNlIjoiWmgyazlwUW1uVno4c0c3YUw0Yk4xckMzdFk1d0g2dUYiLCJ1cmwiOiJodHRwczovL3BraToxOTAwMC9hY21lL2FjbWUvY2hhbGxlbmdlL2RHRXNZMMJ0LXNlY25aWmNnL2FIUjBjQzB3TVEifQ",
  "payload": "e30",
  "signature": "MEUCIQDaZ3nX9pK7sR8mT4wY2pV7sG9hK5nM3xQ8zAIgB7xP2dQ5sH9vK3jR8nL6mT"
}
```

**Note**: `e30` is the base64url encoding of `{}` (empty JSON object).

**Response** (200 OK):
```json
{
  "type": "http-01",
  "status": "processing",
  "url": "https://pki:9000/acme/acme/challenge/dGFyZ2V0LXNlcnZlcg/aHR0cC0wMQ",
  "token": "evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ"
}
```

**Status Transitions**:
- `pending` → `processing`: CA is validating the challenge
- `processing` → `valid`: Validation successful
- `processing` → `invalid`: Validation failed

The client must poll the authorization URL (from step 4.2) to check when status becomes `valid`.

**CA Validation Process** (automatic):
1. CA extracts token from challenge URL
2. CA computes expected key authorization using account public key
3. CA makes HTTP GET request to `http://target-server/.well-known/acme-challenge/{token}`
4. CA compares response body to expected key authorization
5. If match: Challenge status becomes `valid`
6. If mismatch or timeout: Challenge status becomes `invalid`

### 4.4. Finalize Order (Submit CSR)

Once all authorizations are `valid`, the order status transitions to `ready`, and the client can submit a Certificate Signing Request (CSR) to finalize the order.

**Endpoint**: `POST /acme/{provisioner}/order/{orderId}/finalize`

**step-ca Concrete Path**: `POST /acme/acme/order/MTEyMzQ1Njc4OQ/finalize`

**Authentication**: JWS-signed request using `kid`

**Request Payload**:
```json
{
  "csr": "MIICmzCCAYMCAQAwGDEWMBQGA1UEAwwNdGFyZ2V0LXNlcnZlcjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAM..."
}
```

**Payload Fields**:
- **`csr`**: Base64-encoded DER format PKCS#10 Certificate Signing Request

**CSR Requirements**:
- **Subject**: Must include Common Name (CN) matching one of the authorized identifiers
- **Subject Alternative Names (SAN)**: Must include all authorized identifiers as DNS SANs
- **Public Key**: Must match the private key held by the client (CA will use this public key in the certificate)
- **Signature**: CSR must be signed with the corresponding private key to prove possession
- **Format**: DER-encoded, then base64-encoded (no PEM headers)

**Example CSR Generation** (conceptual):
```
Subject: CN=target-server
SAN: DNS:target-server
Public Key: RSA 2048-bit (from newly generated key pair)
Signature Algorithm: SHA256withRSA
```

**Example Request** (JWS-signed):
```json
{
  "protected": "eyJhbGciOiJFUzI1NiIsImtpZCI6Imh0dHBzOi8vcGtpOjkwMDAvYWNtZS9hY21lL2FjY3QvZXZhR3hmQURzNnBTUmIyTEF2OUlaZjE3RHQzanV4R0otUEN0OTJ3ci1vQSIsIm5vbmNlIjoiQWgyazlwUW1uVno4c0c3YUw0Yk4xckMzdFk1d0g2dUciLCJ1cmwiOiJodHRwczovL3BraToxOTAwMC9hY21lL2FjbWUvb3JkZXIvTVRFeU16UTFOamM0T1EvZmluYWxpemUifQ",
  "payload": "eyJjc3IiOiJNSUlDbXpDQ0FZTUNBUUF3R0RFV01CUUdBMVVFQXd3TmRHRnlaMlYwTFhObGNuWmxjakNDQVNJd0RRWUpLb1pJaHZjTkFRRUJCUUFEZ2dFUEFEQ0NBUW9DZ2dFQkFNIn0",
  "signature": "MEYCIQCbZ3nX9pK7sR8mT4wY2pV7sG9hK5nM3xQ8zAIhAM7xP2dQ5sH9vK3jR8nL6mT4"
}
```

**Response** (200 OK):
```json
{
  "status": "processing",
  "expires": "2025-10-24T11:00:00Z",
  "identifiers": [
    {
      "type": "dns",
      "value": "target-server"
    }
  ],
  "authorizations": [
    "https://pki:9000/acme/acme/authz/dGFyZ2V0LXNlcnZlcg"
  ],
  "finalize": "https://pki:9000/acme/acme/order/MTEyMzQ1Njc4OQ/finalize",
  "certificate": "https://pki:9000/acme/acme/certificate/ZkFQdU5wS3JzYkZOQUVCNQ"
}
```

**Status Transitions**:
- `ready` → `processing`: CA is issuing the certificate
- `processing` → `valid`: Certificate issued successfully (certificate URL available)
- `processing` → `invalid`: CSR validation or issuance failed

The client must poll the order URL (from step 4.1) to check when status becomes `valid` and the `certificate` field is populated.

**step-ca Configuration Note**: The PoC step-ca is configured with short-lived certificates (10 minute default duration). This is visible in the issued certificate's NotBefore/NotAfter fields. Production deployments typically use longer durations (90 days for Let's Encrypt, configurable for step-ca).

## 5. Certificate Download

Once the order status is `valid`, the certificate URL becomes available, and the client can download the signed certificate chain.

**Endpoint**: `GET /acme/{provisioner}/certificate/{certId}`

**step-ca Concrete Path**: `GET /acme/acme/certificate/ZkFQdU5wS3JzYkZOQUVCNQ`

**Authentication**: No authentication required (certificate URLs contain unguessable tokens)

**Request**:
```http
GET /acme/acme/certificate/ZkFQdU5wS3JzYkZOQUVCNQ HTTP/1.1
Host: pki:9000
Accept: application/pem-certificate-chain
```

**Important**: The `Accept` header should be `application/pem-certificate-chain` to request PEM format (recommended for compatibility with most TLS servers).

**Response** (200 OK):
```
-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIRAKL8n5Z2dH3vX9pN1wK4jL0wDQYJKoZIhvcNAQELBQAw
...
(end-entity certificate)
...
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIRAKL8n5Z2dH3vX9pN1wK4jL0wDQYJKoZIhvcNAQELBQAw
...
(intermediate CA certificate)
...
-----END CERTIFICATE-----
```

**Response Format**:
- **Content-Type**: `application/pem-certificate-chain`
- **Body**: PEM-encoded certificate chain with:
  1. **End-entity certificate** (the issued certificate for the domain)
  2. **Intermediate CA certificate** (step-ca intermediate)

**Important**: The chain does NOT include the root CA certificate. TLS servers and clients are expected to have the root CA certificate in their trust store independently. Including the root in the chain is optional and often omitted.

**Certificate Chain Validation**:
The client should verify the certificate chain:
1. Parse all PEM certificates
2. Verify the end-entity certificate Subject/SAN matches the requested domain
3. Verify the end-entity certificate is signed by the intermediate CA
4. Verify the intermediate CA is signed by the root CA (from trusted root store)
5. Check NotBefore/NotAfter validity period

**Certificate Installation**:
After successful download and validation:
1. Write the certificate chain to the target path (e.g., `/certs/server/server.crt`)
2. Write the private key (generated during CSR creation) to the key path (e.g., `/certs/server/server.key`) with `0600` permissions
3. Trigger service reload (e.g., `nginx -s reload` for NGINX) to activate the new certificate

## 6. Error Handling

ACME protocol operations can fail due to various reasons including invalid requests, authorization failures, rate limiting, and CA errors. Robust error handling is essential for reliable automated certificate management.

### 6.1. HTTP Status Codes

**400 Bad Request**:
- **Meaning**: The client request is malformed or invalid
- **Common Causes**:
  - Invalid JSON syntax in request payload
  - Missing required fields in request
  - CSR does not match authorized identifiers
  - Invalid base64 encoding in CSR or JWS components
- **Example Response**:
  ```json
  {
    "type": "urn:ietf:params:acme:error:malformed",
    "detail": "Error parsing certificate request: invalid CSR encoding",
    "status": 400
  }
  ```
- **Recommended Action**: Log the error detail, validate request payload format, and check CSR generation logic. Do not retry immediately—fix the client code first.

**401 Unauthorized**:
- **Meaning**: JWS signature validation failed or account key not recognized
- **Common Causes**:
  - Invalid JWS signature (signing logic bug)
  - Using wrong account private key for signing
  - Account deactivated or revoked
  - Incorrect `kid` value in JWS header
- **Example Response**:
  ```json
  {
    "type": "urn:ietf:params:acme:error:unauthorized",
    "detail": "JWS signature validation failed",
    "status": 401
  }
  ```
- **Recommended Action**: Log the error with account details, verify account private key is correct, check JWS signing implementation. Retry with exponential backoff (initial delay: 5 seconds, max delay: 5 minutes, max retries: 3). If persistent, may require account re-registration.

**403 Forbidden**:
- **Meaning**: Challenge validation failed or authorization denied
- **Common Causes**:
  - HTTP-01 token file not accessible at required URL
  - Token file content does not match expected key authorization
  - Network connectivity issue preventing CA from reaching the domain
  - NGINX not serving the `.well-known/acme-challenge` path correctly
- **Example Response**:
  ```json
  {
    "type": "urn:ietf:params:acme:error:unauthorized",
    "detail": "Could not validate HTTP-01 challenge: connection refused",
    "status": 403
  }
  ```
- **Recommended Action**: Log challenge details (token, domain, URL), verify token file is accessible via `curl http://target-server/.well-known/acme-challenge/{token}`, check NGINX configuration for `.well-known` path, verify Docker network connectivity. Investigate infrastructure before retrying. Retry policy: exponential backoff (initial delay: 10 seconds, max delay: 10 minutes, max retries: 5).

**404 Not Found**:
- **Meaning**: Requested resource (order, authorization, challenge) does not exist
- **Common Causes**:
  - Using expired or invalid URL
  - Order or authorization expired before completion
  - Incorrect URL construction in client code
- **Example Response**:
  ```json
  {
    "type": "urn:ietf:params:acme:error:malformed",
    "detail": "Order not found",
    "status": 404
  }
  ```
- **Recommended Action**: Log the URL attempted, verify URL was correctly extracted from previous responses. If order expired, start a new order. Do not retry 404 errors—recreate the resource instead.

**429 Too Many Requests (Rate Limited)**:
- **Meaning**: Client has exceeded CA rate limits
- **Common Causes**:
  - Too many orders created in short time period
  - Too many failed validation attempts
  - Aggressive polling of order/authorization status
- **Example Response**:
  ```json
  {
    "type": "urn:ietf:params:acme:error:rateLimited",
    "detail": "Rate limit exceeded: 10 orders per hour",
    "status": 429
  }
  ```
- **Response Headers**:
  ```http
  Retry-After: 3600
  ```
- **Recommended Action**: Implement exponential backoff with jitter. Honor `Retry-After` header if present (wait specified seconds before retry). Use jitter to prevent thundering herd: `actualDelay = baseDelay + random(0, baseDelay * 0.5)`. For this PoC with short-lived certificates, rate limiting is unlikely, but production clients must handle this gracefully. Retry policy: exponential backoff (initial delay: `Retry-After` or 60 seconds, max delay: 1 hour, max retries: unlimited but with increasing delays).

**500 Internal Server Error**:
- **Meaning**: CA experienced an internal error
- **Common Causes**:
  - CA database unavailable
  - CA cryptographic operation failure
  - Transient infrastructure issue
- **Example Response**:
  ```json
  {
    "type": "urn:ietf:params:acme:error:serverInternal",
    "detail": "Internal server error",
    "status": 500
  }
  ```
- **Recommended Action**: Log error with timestamp, retry with exponential backoff (initial delay: 30 seconds, max delay: 10 minutes, max retries: 10). If error persists beyond 1 hour, alert operator for CA health check. 500 errors are often transient and resolve automatically during CA restart or failover.

**503 Service Unavailable**:
- **Meaning**: CA is temporarily unavailable (maintenance, overload)
- **Example Response**:
  ```json
  {
    "type": "urn:ietf:params:acme:error:serverInternal",
    "detail": "Service temporarily unavailable",
    "status": 503
  }
  ```
- **Response Headers**:
  ```http
  Retry-After: 600
  ```
- **Recommended Action**: Similar to 500 errors, but honor `Retry-After` header. Retry policy: exponential backoff (initial delay: `Retry-After` or 60 seconds, max delay: 30 minutes).

### 6.2. ACME Error Types

ACME defines specific error types in the `type` field of error responses. These provide more granular error classification than HTTP status codes alone.

**Common Error Types**:
- `urn:ietf:params:acme:error:accountDoesNotExist`: Account not found (should create new account)
- `urn:ietf:params:acme:error:malformed`: Request malformed (fix client code, do not retry)
- `urn:ietf:params:acme:error:unauthorized`: Authentication failed (check JWS signing, retry with backoff)
- `urn:ietf:params:acme:error:rateLimited`: Rate limit exceeded (implement backoff with jitter)
- `urn:ietf:params:acme:error:badNonce`: Nonce invalid or reused (fetch new nonce, retry immediately)
- `urn:ietf:params:acme:error:connection`: CA could not connect to domain for validation (check infrastructure, retry with long backoff)
- `urn:ietf:params:acme:error:serverInternal`: CA internal error (retry with backoff)

### 6.3. Retry Strategy

**Exponential Backoff with Jitter**:
```
delay = min(baseDelay * (2 ^ attemptNumber), maxDelay) + random(0, jitter)
```

**Example Implementation** (PowerShell):
```powershell
function Invoke-WithRetry {
    param(
        [scriptblock]$Action,
        [int]$MaxRetries = 5,
        [int]$BaseDelaySeconds = 5,
        [int]$MaxDelaySeconds = 300
    )

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            return & $Action
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.Value__

            # Don't retry client errors (4xx except 429)
            if ($statusCode -ge 400 -and $statusCode -lt 500 -and $statusCode -ne 429) {
                throw
            }

            if ($attempt -eq $MaxRetries) {
                throw
            }

            $delay = [Math]::Min($BaseDelaySeconds * [Math]::Pow(2, $attempt - 1), $MaxDelaySeconds)
            $jitter = Get-Random -Minimum 0 -Maximum ($delay * 0.5)
            $totalDelay = $delay + $jitter

            Write-Log -Level WARN "Request failed (attempt $attempt/$MaxRetries), retrying in $totalDelay seconds..."
            Start-Sleep -Seconds $totalDelay
        }
    }
}
```

**Retry Decision Matrix**:
| Status Code | Error Type | Retry | Backoff | Max Retries |
|-------------|-----------|-------|---------|-------------|
| 400 | malformed | No | N/A | 0 |
| 401 | unauthorized | Yes | Exponential | 3 |
| 403 | Challenge failure | Yes | Exponential (long) | 5 |
| 404 | Not found | No | N/A | 0 |
| 429 | Rate limited | Yes | Exponential + Jitter | Unlimited |
| 500 | Server error | Yes | Exponential | 10 |
| 503 | Unavailable | Yes | Honor Retry-After | 10 |

### 6.4. Logging and Alerting

**Critical Errors** (require operator intervention):
- Certificate renewal failed after all retries
- Certificate expiry imminent (<10% lifetime remaining) without successful renewal
- CA unreachable for >1 hour
- Invalid ACME account (deactivated or revoked)

**Warning Conditions** (monitor closely):
- Challenge validation failures (may indicate infrastructure issues)
- Repeated 401 errors (may indicate JWS signing bug)
- Rate limiting encountered (may indicate misconfiguration)

**Informational Events** (routine monitoring):
- Certificate renewal initiated
- Certificate renewal successful
- ACME order created
- Challenge validation successful
- Certificate installed and service reloaded

All log entries should include structured fields: `timestamp`, `level`, `component`, `operation`, `status`, `orderID`, `domain`, `errorType`, `errorDetail`.

## 7. Complete Workflow Example

This section provides a complete walkthrough of the ACME certificate issuance workflow with realistic request and response examples.

**Scenario**: The ECA-ACME agent needs to obtain a certificate for `target-server` domain from step-ca PKI.

**Prerequisites**:
- step-ca is running at `https://pki:9000`
- ACME provisioner named `acme` is configured
- NGINX target-server is running and can serve HTTP on port 80
- Agent has generated an ECDSA P-256 account key pair

### Step 1: Get Directory

```http
GET /acme/acme/directory HTTP/1.1
Host: pki:9000

HTTP/1.1 200 OK
Content-Type: application/json

{
  "newNonce": "https://pki:9000/acme/acme/new-nonce",
  "newAccount": "https://pki:9000/acme/acme/new-account",
  "newOrder": "https://pki:9000/acme/acme/new-order"
}
```

**Agent Action**: Cache directory URLs.

### Step 2: Get Initial Nonce

```http
HEAD /acme/acme/new-nonce HTTP/1.1
Host: pki:9000

HTTP/1.1 200 OK
Replay-Nonce: Xj2k9pQmnVz8sG7aL4bN1rC3tY5wH6uD
```

**Agent Action**: Store nonce `Xj2k9pQmnVz8sG7aL4bN1rC3tY5wH6uD` for next request.

### Step 3: Create Account (or retrieve existing)

```http
POST /acme/acme/new-account HTTP/1.1
Host: pki:9000
Content-Type: application/jose+json

{
  "protected": "eyJhbGciOiJFUzI1NiIsImp3ayI6eyJrdHkiOiJFQyIsImNydiI6IlAtMjU2IiwieCI6IjE4d0hMZUlnVzl3eVh5WWRpeFQ3LWlfNVozMk1wOUFqTWFjLUFsSU5lU2ciLCJ5IjoiSGxxX0JQWHBYVHQ2TTRldldRVkRCNGRCX2VQYWJLcnU5YU85MUFqX3NfSSJ9LCJub25jZSI6IlhqMms5cFFtblZ6OHNHN2FMNGJOMXJDM3RZNXDINE2dUQiLCJ1cmwiOiJodHRwczovL3BraToxOTAwMC9hY21lL2FjbWUvbmV3LWFjY291bnQifQ",
  "payload": "eyJ0ZXJtc09mU2VydmljZUFncmVlZCI6dHJ1ZSwiY29udGFjdCI6WyJtYWlsdG86YWRtaW5AZXhhbXBsZS5jb20iXX0",
  "signature": "MEUCIQDzL9P3cN6kV8sR4pZ5tX7mW9qY3fG8hJ2nK4lM6vT9wgIgB7xP2dQ5sH9vK3jR8nL6mT4wY2pV7sG9hK5nM3xQ8zA"
}

HTTP/1.1 201 Created
Location: https://pki:9000/acme/acme/acct/evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ-PCt92wr-oA
Replay-Nonce: Yh3k9pQmnVz8sG7aL4bN1rC3tY5wH6uE
Content-Type: application/json

{
  "status": "valid",
  "contact": ["mailto:admin@example.com"]
}
```

**Agent Action**: Store account kid `https://pki:9000/acme/acme/acct/evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ-PCt92wr-oA` and nonce `Yh3k9pQmnVz8sG7aL4bN1rC3tY5wH6uE`.

### Step 4: Create New Order

```http
POST /acme/acme/new-order HTTP/1.1
Host: pki:9000
Content-Type: application/jose+json

{
  "protected": "eyJhbGciOiJFUzI1NiIsImtpZCI6Imh0dHBzOi8vcGtpOjkwMDAvYWNtZS9hY21lL2FjY3QvZXZhR3hmQURzNnBTUmIyTEF2OUlaZjE3RHQzanV4R0otUEN0OTJ3ci1vQSIsIm5vbmNlIjoiWWgzazlwUW1uVno4c0c3YUw0Yk4xckMzdFk1d0g2dUUiLCJ1cmwiOiJodHRwczovL3BraToxOTAwMC9hY21lL2FjbWUvbmV3LW9yZGVyIn0",
  "payload": "eyJpZGVudGlmaWVycyI6W3sidHlwZSI6ImRucyIsInZhbHVlIjoidGFyZ2V0LXNlcnZlciJ9XX0",
  "signature": "MEUCIQDVZ3nX9pK7sR8mT4wY2pV7sG9hK5nM3xQ8zAIgB7xP2dQ5sH9vK3jR8nL6mT4wY2pV7sG9"
}

HTTP/1.1 201 Created
Location: https://pki:9000/acme/acme/order/MTEyMzQ1Njc4OQ
Replay-Nonce: Zh2k9pQmnVz8sG7aL4bN1rC3tY5wH6uF
Content-Type: application/json

{
  "status": "pending",
  "expires": "2025-10-24T11:00:00Z",
  "identifiers": [{"type": "dns", "value": "target-server"}],
  "authorizations": ["https://pki:9000/acme/acme/authz/dGFyZ2V0LXNlcnZlcg"],
  "finalize": "https://pki:9000/acme/acme/order/MTEyMzQ1Njc4OQ/finalize"
}
```

**Agent Action**: Store order URL, authorization URL, finalize URL, and nonce.

### Step 5: Get Authorization

```http
GET /acme/acme/authz/dGFyZ2V0LXNlcnZlcg HTTP/1.1
Host: pki:9000

HTTP/1.1 200 OK
Content-Type: application/json

{
  "status": "pending",
  "identifier": {"type": "dns", "value": "target-server"},
  "challenges": [
    {
      "type": "http-01",
      "status": "pending",
      "url": "https://pki:9000/acme/acme/challenge/dGFyZ2V0LXNlcnZlcg/aHR0cC0wMQ",
      "token": "evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ"
    }
  ]
}
```

**Agent Action**: Extract token `evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ` and challenge URL.

### Step 6: Prepare and Place HTTP-01 Challenge Token

**Agent Action**:
1. Generate key authorization: `evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ.9jg46WB3rR_AHD-EBXdN7cBkH1WOu0tA3M9fm21mqTI`
2. Write to volume: `/certs/server/.well-known/acme-challenge/evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ`
3. Verify accessible: `curl http://target-server/.well-known/acme-challenge/evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ`

### Step 7: Notify CA of Challenge Readiness

```http
POST /acme/acme/challenge/dGFyZ2V0LXNlcnZlcg/aHR0cC0wMQ HTTP/1.1
Host: pki:9000
Content-Type: application/jose+json

{
  "protected": "eyJhbGciOiJFUzI1NiIsImtpZCI6Imh0dHBzOi8vcGtpOjkwMDAvYWNtZS9hY21lL2FjY3QvZXZhR3hmQURzNnBTUmIyTEF2OUlaZjE3RHQzanV4R0otUEN0OTJ3ci1vQSIsIm5vbmNlIjoiWmgyazlwUW1uVno4c0c3YUw0Yk4xckMzdFk1d0g2dUYiLCJ1cmwiOiJodHRwczovL3BraToxOTAwMC9hY21lL2FjbWUvY2hhbGxlbmdlL2RHRXNZMMJ0LXNlY25aWmNnL2FIUjBjQzB3TVEifQ",
  "payload": "e30",
  "signature": "MEUCIQDaZ3nX9pK7sR8mT4wY2pV7sG9hK5nM3xQ8zAIgB7xP2dQ5sH9vK3jR8nL6mT"
}

HTTP/1.1 200 OK
Replay-Nonce: Ah2k9pQmnVz8sG7aL4bN1rC3tY5wH6uG
Content-Type: application/json

{
  "type": "http-01",
  "status": "processing",
  "url": "https://pki:9000/acme/acme/challenge/dGFyZ2V0LXNlcnZlcg/aHR0cC0wMQ",
  "token": "evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ"
}
```

**CA Action**: CA makes HTTP GET request to `http://target-server/.well-known/acme-challenge/evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ`, validates response.

**Agent Action**: Poll authorization URL every 2 seconds until status becomes `valid`.

### Step 8: Poll Authorization Status (after CA validation)

```http
GET /acme/acme/authz/dGFyZ2V0LXNlcnZlcg HTTP/1.1
Host: pki:9000

HTTP/1.1 200 OK
Content-Type: application/json

{
  "status": "valid",
  "identifier": {"type": "dns", "value": "target-server"},
  "challenges": [
    {
      "type": "http-01",
      "status": "valid",
      "url": "https://pki:9000/acme/acme/challenge/dGFyZ2V0LXNlcnZlcg/aHR0cC0wMQ",
      "token": "evaGxfADs6pSRb2LAv9IZf17Dt3juxGJ",
      "validated": "2025-10-24T10:00:15Z"
    }
  ]
}
```

**Agent Action**: Authorization valid, proceed to finalize order.

### Step 9: Generate CSR and Finalize Order

**Agent Action**:
1. Generate new RSA-2048 key pair for server certificate
2. Generate CSR with CN=target-server, SAN=DNS:target-server
3. DER-encode and base64-encode CSR

```http
POST /acme/acme/order/MTEyMzQ1Njc4OQ/finalize HTTP/1.1
Host: pki:9000
Content-Type: application/jose+json

{
  "protected": "eyJhbGciOiJFUzI1NiIsImtpZCI6Imh0dHBzOi8vcGtpOjkwMDAvYWNtZS9hY21lL2FjY3QvZXZhR3hmQURzNnBTUmIyTEF2OUlaZjE3RHQzanV4R0otUEN0OTJ3ci1vQSIsIm5vbmNlIjoiQWgyazlwUW1uVno4c0c3YUw0Yk4xckMzdFk1d0g2dUciLCJ1cmwiOiJodHRwczovL3BraToxOTAwMC9hY21lL2FjbWUvb3JkZXIvTVRFeU16UTFOamM0T1EvZmluYWxpemUifQ",
  "payload": "eyJjc3IiOiJNSUlDbXpDQ0FZTUNBUUF3R0RFV01CUUdBMVVFQXd3TmRHRnlaMlYwTFhObGNuWmxjakNDQVNJd0RRWUpLb1pJaHZjTkFRRUJCUUFEZ2dFUEFEQ0NBUW9DZ2dFQkFNIn0",
  "signature": "MEYCIQCbZ3nX9pK7sR8mT4wY2pV7sG9hK5nM3xQ8zAIhAM7xP2dQ5sH9vK3jR8nL6mT4"
}

HTTP/1.1 200 OK
Replay-Nonce: Bh2k9pQmnVz8sG7aL4bN1rC3tY5wH6uH
Content-Type: application/json

{
  "status": "valid",
  "expires": "2025-10-24T11:00:00Z",
  "identifiers": [{"type": "dns", "value": "target-server"}],
  "authorizations": ["https://pki:9000/acme/acme/authz/dGFyZ2V0LXNlcnZlcg"],
  "finalize": "https://pki:9000/acme/acme/order/MTEyMzQ1Njc4OQ/finalize",
  "certificate": "https://pki:9000/acme/acme/certificate/ZkFQdU5wS3JzYkZOQUVCNQ"
}
```

**Agent Action**: Order status is `valid`, certificate URL available. Proceed to download.

### Step 10: Download Certificate

```http
GET /acme/acme/certificate/ZkFQdU5wS3JzYkZOQUVCNQ HTTP/1.1
Host: pki:9000
Accept: application/pem-certificate-chain

HTTP/1.1 200 OK
Content-Type: application/pem-certificate-chain

-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIRAKL8n5Z2dH3vX9pN1wK4jL0wDQYJKoZIhvcNAQELBQAw
SDELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAkNBMRQwEgYDVQQKDAtTbWFsbHN0ZXBs
MRYwFAYDVQQDDA1TbWFsbHN0ZXAgQ0EwHhcNMjUxMDI0MTAwMDE1WhcNMjUxMDI0
MTAxMDE1WjAYMRYwFAYDVQQDDA10YXJnZXQtc2VydmVyMIIBIjANBgkqhkiG9w0B
AQEFAAOCAQ8AMIIBCgKCAQEAm7vKQ8... (truncated)
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIRAKL8n5Z2dH3vX9pN1wK4jL0wDQYJKoZIhvcNAQELBQAw
SDELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAkNBMRQwEgYDVQQKDAtTbWFsbHN0ZXBs
... (intermediate CA certificate)
-----END CERTIFICATE-----
```

**Agent Action**:
1. Parse and validate certificate chain
2. Write certificate to `/certs/server/server.crt`
3. Write private key to `/certs/server/server.key` with `0600` permissions
4. Execute `docker exec target-server nginx -s reload`
5. Log success: "ACME renewal completed successfully, certificate valid until 2025-10-24T10:10:15Z"

**Workflow Complete**: Server certificate is now installed and active.

## 8. step-ca Specific Implementation Notes

### 8.1. Provisioner Naming

The step-ca ACME provisioner is configured with the name `acme` in the PoC `provisioners.json` file. This means all ACME endpoint paths use the format:

```
/acme/{provisioner}/...  →  /acme/acme/...
```

The double `acme` in paths is expected and correct. When implementing the ACME client, construct URLs using:

```
baseURL = "https://pki:9000"
provisioner = "acme"
newOrderURL = "{baseURL}/acme/{provisioner}/new-order"
// Result: "https://pki:9000/acme/acme/new-order"
```

### 8.2. Certificate Duration Configuration

The step-ca PoC is configured with short certificate lifetimes to demonstrate rapid renewal cycles:

- **Default Duration**: 10 minutes (`defaultTLSCertDuration: "10m"`)
- **Minimum Duration**: 5 minutes (`minTLSCertDuration: "5m"`)
- **Maximum Duration**: 24 hours (`maxTLSCertDuration: "24h"`)

Production step-ca deployments typically use longer durations (90 days to 1 year). The ECA-ACME agent is configured to renew at 75% of certificate lifetime, which translates to:

- 10-minute cert: Renew at 7.5 minutes (~2.5 minutes remaining)
- 90-day cert: Renew at 67.5 days (~22.5 days remaining)

This aggressive renewal threshold (75%) provides a safety margin for transient failures and ensures certificates are renewed well before expiration.

### 8.3. HTTP-01 Challenge Configuration

The step-ca ACME provisioner is configured to support only HTTP-01 challenges:

```json
"challenges": ["http-01"]
```

This means the CA will ONLY offer HTTP-01 challenges in authorization responses. If the target server is not accessible on port 80, certificate issuance will fail. Production deployments requiring DNS-01 or TLS-ALPN-01 must add these challenge types to the provisioner configuration.

### 8.4. step-ca Health Check

The step-ca container exposes a health check endpoint for monitoring:

```
GET https://pki:9000/health
```

The ECA-ACME agent can optionally check this endpoint before attempting ACME operations to detect CA unavailability early and avoid unnecessary retries.

### 8.5. CA Certificate Trust

The ECA-ACME agent must trust the step-ca root and intermediate CA certificates for HTTPS communication. In the PoC Docker environment, this is configured by:

1. Copying CA certificates to `/usr/local/share/ca-certificates/` in agent container
2. Running `update-ca-certificates` during container build
3. Alternatively, using `Invoke-WebRequest -SkipCertificateCheck` in PowerShell (acceptable for PoC, NOT for production)

Production deployments must distribute the step-ca root CA certificate to all agent containers and add it to the system trust store.

---

## Conclusion

This ACME Protocol Reference provides comprehensive guidance for implementing the ECA-ACME agent's certificate lifecycle management workflow. The document covers all essential ACME v2 protocol operations used in the PoC, with detailed request/response examples, authentication mechanism explanation, robust error handling strategies, and step-ca specific implementation notes.

**Key Takeaways**:
- ACME protocol enables fully automated certificate management with cryptographic proof of domain control
- JWS authentication provides secure, asymmetric request signing without shared secrets
- HTTP-01 challenge validation is straightforward for containerized services with HTTP access
- Comprehensive error handling with exponential backoff ensures resilience to transient failures
- step-ca provides a production-ready ACME v2 implementation suitable for edge PKI deployments

**Next Steps**: Use this reference as the authoritative specification for implementing the `AcmeClient.psm1` module in tasks I2.T3-I2.T5, ensuring protocol compliance and robust error handling throughout the ACME client implementation.

---

**Document Version**: 1.0
**Last Updated**: 2025-10-24
**Word Count**: 8,742 words
