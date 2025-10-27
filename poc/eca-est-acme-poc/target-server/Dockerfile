# ==============================================================================
# NGINX Target Server Dockerfile - HTTPS Service with Automated Certificate Management
# ==============================================================================
#
# This Dockerfile builds the ECA PoC target server container that demonstrates
# practical server certificate usage in a production-like scenario. The server
# serves HTTPS traffic using certificates automatically managed by the ACME agent
# and supports optional mutual TLS authentication for EST-issued client certificates.
#
# Build Context: target-server/ (this directory)
# Build Command (standalone): docker build -t eca-target-server:latest target-server/
# Build Command (compose): docker-compose build target-server
#
# Container Purpose:
#   - Serve HTTPS traffic using server certificates from the ACME agent
#   - Respond to HTTP-01 ACME challenge requests on port 80
#   - Support graceful configuration reload for zero-downtime certificate updates
#   - Optionally validate client certificates for mutual TLS authentication
#   - Provide demonstration web page showing connection status
#
# Container Initialization Flow:
#   1. Container starts and NGINX reads configuration from /etc/nginx/nginx.conf
#   2. NGINX binds to ports 80 (HTTP) and 443 (HTTPS)
#   3. Port 80 serves ACME HTTP-01 challenges from /challenge/.well-known/acme-challenge/
#   4. Port 443 serves HTTPS traffic using certificates from /certs/server/ volume
#   5. On certificate renewal, ACME agent sends SIGHUP to trigger graceful reload
#   6. NGINX reloads configuration without dropping connections (zero-downtime)
#
# Volume Requirements:
#   - /certs/server: Shared volume with eca-acme-agent for certificate delivery
#     - server.crt: Server certificate (public certificate chain)
#     - server.key: Server private key (protected with 600 permissions)
#   - /challenge: Shared volume with eca-acme-agent for HTTP-01 challenge tokens
#     - ACME agent writes tokens to /.well-known/acme-challenge/ subdirectory
#     - NGINX serves these tokens via HTTP on port 80
#   - /etc/ssl/certs: Optional volume mount for step-ca root CA certificate
#     - Required for mTLS client certificate validation
#     - Can be mounted at runtime instead of copied during build
#
# Port Exposure:
#   - 443/tcp: HTTPS traffic (TLS 1.3, high-security ciphers)
#   - 80/tcp: HTTP traffic (ACME HTTP-01 challenge validation only)
#
# Configuration Files:
#   - /etc/nginx/nginx.conf: Main NGINX configuration
#     - Defines HTTP server on port 80 for ACME challenges
#     - Defines HTTPS server on port 443 for application traffic
#     - Configures TLS 1.3, cipher suites, mTLS client authentication
#     - Implements security headers (HSTS, X-Frame-Options, etc.)
#   - /usr/share/nginx/html/index.html: Demonstration web page
#     - Displays connection status, certificate validity, mTLS status
#     - Shows current server time and connection security information
#
# Signal Handling:
#   - SIGHUP: Graceful configuration reload (triggered by ACME agent on cert renewal)
#   - SIGTERM: Graceful shutdown (waits for active connections to complete)
#   - SIGQUIT: Quick shutdown (immediate termination)
#
# Dependencies:
#   - eca-acme-agent: Provides server certificates via /certs/server volume
#   - eca-pki: Provides root CA certificate for mTLS client validation (optional)
#   - Docker network: Requires connectivity to ACME agent for docker exec reload
#
# Security Notes:
#   - NGINX runs as non-root user (nginx) inside container
#   - TLS 1.3 only (no TLS 1.2 or older protocols)
#   - High-security cipher suites only (no weak or deprecated ciphers)
#   - HSTS header enabled (31536000 seconds = 1 year)
#   - Client certificate validation is optional (supports both mTLS and regular HTTPS)
#
# ==============================================================================

# ==============================================================================
# Base Image: Official NGINX Alpine Linux Image
# ==============================================================================
# Using nginx:1.25-alpine for minimal image size (~42 MB) and security
# Alpine Linux provides small attack surface and fast startup times
# Version 1.25 includes TLS 1.3 support and modern security features
FROM nginx:1.25-alpine

# Install OpenSSL for temporary self-signed certificate generation
# Required by bootstrap entrypoint script to create initial certificates
# before ACME agent obtains real certificates
RUN apk add --no-cache openssl

# ==============================================================================
# Configuration Files: Copy NGINX configuration and web content
# ==============================================================================

# Copy NGINX configuration to standard location
# This configuration file defines both HTTP (port 80) and HTTPS (port 443) server blocks
# - HTTP block exclusively handles ACME HTTP-01 challenge validation
# - HTTPS block provides TLS 1.3 secure connections with optional mTLS
# Source: nginx.conf (from build context target-server/)
# Destination: /etc/nginx/nginx.conf (NGINX default configuration path)
COPY nginx.conf /etc/nginx/nginx.conf

# Copy demonstration HTML page to web root
# This page displays connection status, certificate information, and mTLS status
# Includes responsive CSS, JavaScript for dynamic content, and security information
# Source: index.html (from build context target-server/)
# Destination: /usr/share/nginx/html/index.html (NGINX default document root)
COPY index.html /usr/share/nginx/html/index.html

# ==============================================================================
# Directory Structure: Create ACME challenge directory
# ==============================================================================

# Create directory structure for ACME HTTP-01 challenge validation
# - ACME agent writes challenge tokens to this directory via shared volume
# - NGINX serves these tokens via HTTP on port 80 at /.well-known/acme-challenge/
# - Directory must exist with 755 permissions for proper access by NGINX
# - Parent directories created with -p flag (mkdir --parents)
# Rationale: nginx.conf references /challenge/.well-known/acme-challenge/ as root
#            for HTTP-01 challenge location, so directory must exist at container startup
RUN mkdir -p /challenge/.well-known/acme-challenge && chmod 755 /challenge

# ==============================================================================
# Bootstrap Entrypoint: Handle certificate bootstrap problem
# ==============================================================================

# Copy custom entrypoint script that generates temporary self-signed certificates
# This solves the chicken-and-egg problem where:
# - NGINX requires SSL certificates to start
# - But ACME agent needs NGINX running to complete HTTP-01 validation
# - Solution: Start with temporary self-signed certificate, replace with real certificate later
# Source: docker-entrypoint.sh (from build context target-server/)
# Destination: /usr/local/bin/bootstrap-entrypoint.sh
COPY docker-entrypoint.sh /usr/local/bin/bootstrap-entrypoint.sh

# Make entrypoint script executable
RUN chmod +x /usr/local/bin/bootstrap-entrypoint.sh

# ==============================================================================
# Network Configuration: Expose container ports
# ==============================================================================

# Expose port 443 for HTTPS traffic
# - Primary application endpoint using TLS 1.3 encryption
# - Serves static content from /usr/share/nginx/html/
# - Uses certificates from /certs/server/ volume (mounted at runtime)
EXPOSE 443

# Expose port 80 for HTTP traffic
# - Exclusively used for ACME HTTP-01 challenge validation
# - Serves challenge tokens from /challenge/.well-known/acme-challenge/
# - All non-challenge requests are redirected to HTTPS (301)
EXPOSE 80

# ==============================================================================
# Container Startup: Bootstrap entrypoint with NGINX foreground execution
# ==============================================================================

# Set bootstrap entrypoint that creates temporary certificates if needed
# This entrypoint script:
# 1. Checks if /certs/server/server.crt and server.key exist
# 2. If not, generates temporary self-signed certificate
# 3. Calls the standard NGINX Docker entrypoint script
# 4. NGINX starts in foreground mode (daemon off)
ENTRYPOINT ["/usr/local/bin/bootstrap-entrypoint.sh"]

# Default command passed to entrypoint (standard NGINX startup)
# - Array format (exec form) ensures proper signal handling for graceful reload
# - SIGHUP signals trigger configuration reload without downtime (for cert renewal)
# - SIGTERM signals trigger graceful shutdown waiting for active connections
# - PID 1 receives signals directly from Docker (required for docker kill/stop)
# Rationale: Docker containers require foreground processes; daemon mode would
#            cause container to exit immediately after NGINX forks to background
CMD ["nginx", "-g", "daemon off;"]
