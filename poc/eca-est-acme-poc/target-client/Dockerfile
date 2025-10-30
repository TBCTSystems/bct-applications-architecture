# ==============================================================================
# Alpine Target Client Dockerfile - mTLS Testing Container
# ==============================================================================
#
# This Dockerfile builds the ECA PoC target client container that demonstrates
# practical client certificate usage for mutual TLS authentication. The client
# performs mTLS connectivity tests to target-server using certificates
# automatically managed by the EST agent.
#
# Build Context: target-client/ (this directory)
# Build Command (standalone): docker build -t eca-target-client:latest target-client/
# Build Command (compose): docker-compose build target-client
#
# Container Purpose:
#   - Test mutual TLS connectivity to target-server using EST-issued client certificates
#   - Validate certificate provisioning and renewal workflows
#   - Provide interactive shell access for manual testing via docker exec
#   - Demonstrate EST protocol client-side certificate lifecycle management
#
# Container Initialization Flow:
#   1. Container starts with CMD ["sleep", "infinity"] to remain running
#   2. EST agent provisions client certificate and key to /certs/client/ volume
#   3. Manual testing via: docker exec eca-target-client /usr/local/bin/test-mtls.sh
#   4. Test script validates certificates exist and performs mTLS handshake
#   5. Container runs indefinitely allowing repeated manual test execution
#
# Volume Requirements:
#   - /certs/client: Shared volume with eca-est-agent for certificate delivery
#     - client.crt: Client certificate (public certificate chain)
#     - client.key: Client private key (protected with 600 permissions)
#   - /certs/ca-root.crt: Step-CA root certificate for server validation (mounted at runtime)
#     - Enables curl to validate target-server's certificate chain
#     - Required for mTLS handshake trust establishment
#
# Testing Script:
#   - /usr/local/bin/test-mtls.sh: Comprehensive mTLS connectivity test
#     - Validates client certificate and key files exist
#     - Performs mTLS handshake using curl with --cert, --key, --cacert flags
#     - Verifies TLS handshake success and HTTP 200 response
#     - Includes colored output, error handling, and detailed logging
#
# Dependencies:
#   - eca-est-agent: Provides client certificates via /certs/client volume
#   - target-server: Endpoint for mTLS connectivity testing
#   - eca-pki: Provides root CA certificate for server validation
#   - Docker network: Requires DNS resolution for target-server hostname
#
# Security Notes:
#   - Container runs with default Alpine user (no elevated privileges)
#   - Client private key accessed via read-only volume mount
#   - No exposed ports (internal client-only container)
#   - Minimal package installation (bash, curl, openssl only)
#
# ==============================================================================

# ==============================================================================
# Base Image: Official Alpine Linux Image
# ==============================================================================
# Using alpine:latest for minimal image size (~7 MB base, ~22 MB with packages)
# Alpine Linux provides small attack surface, fast startup, and standard tooling
# apk package manager includes bash, curl, and openssl in official repositories
FROM alpine:latest

# ==============================================================================
# Package Installation: Install required tools for mTLS testing
# ==============================================================================

# Install bash, curl, and openssl packages with minimal footprint
# - bash: Required by test-mtls.sh shebang (#!/usr/bin/env bash) and script features
#   - Script uses bash-specific features: arrays, set -euo pipefail, process substitution
# - curl: Required for HTTPS/TLS connectivity testing with mTLS support
#   - Used with --cert, --key, --cacert flags for client certificate authentication
# - openssl: Standard TLS toolkit for certificate inspection and debugging
#   - Enables manual certificate validation and troubleshooting
# --no-cache flag prevents package index caching (reduces image size by ~1-2 MB)
RUN apk add --no-cache bash curl openssl

# ==============================================================================
# Test Script: Copy mTLS connectivity test script
# ==============================================================================

# Copy test-mtls.sh script to /usr/local/bin/ with execute permissions
# - Source: test-mtls.sh (234 lines, comprehensive mTLS test with error handling)
# - Destination: /usr/local/bin/test-mtls.sh (standard location, in PATH)
# - Permissions: 755 (rwxr-xr-x) set via --chmod flag (modern Docker 23.0+ syntax)
# - Alternative: COPY test-mtls.sh /usr/local/bin/test-mtls.sh + RUN chmod +x (old Docker)
# Rationale: Single atomic operation reduces layers and matches pki/Dockerfile pattern
COPY --chmod=755 test-mtls.sh /usr/local/bin/test-mtls.sh

# ==============================================================================
# Container Startup: Keep container running for manual testing
# ==============================================================================

# Start container with sleep infinity to allow docker exec testing
# - Array format (exec form) ensures proper signal handling (SIGTERM propagation)
# - Container remains running indefinitely until explicitly stopped
# - Enables manual test execution: docker exec eca-target-client /usr/local/bin/test-mtls.sh
# - docker-compose.yml may override this with 'command: sleep infinity' directive
# Rationale: Client container has no long-running services, only on-demand testing
#            sleep infinity is standard pattern for interactive/testing containers
CMD ["sleep", "infinity"]
