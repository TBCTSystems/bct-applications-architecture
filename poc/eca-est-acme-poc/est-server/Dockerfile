# ==============================================================================
# EST Server Dockerfile - Foundries.io EST Server (Modified for PoC)
# ==============================================================================
#
# This Dockerfile builds the Foundries.io EST server for PoC demonstration.
# Due to Cisco libEST OpenSSL 3.0 compatibility issues and GlobalSign registry
# unavailability, we're using the foundries.io server in a simplified mode
# that accepts all enrollment requests to demonstrate the EST agent lifecycle.
#
# Build Context: est-server/
# Build Command: docker build -t eca-est-server:latest .
#
# Container Initialization Flow:
#   1. Container starts and runs init-est.sh script
#   2. Init script requests intermediate CA certificate from step-ca
#   3. Init script requests TLS certificate for EST server from step-ca
#   4. EST server starts and listens on port 8443
#   5. Health check validates EST /cacerts endpoint availability
#
# Volume Requirements:
#   - /est/data: Persistent storage for certificates and keys
#   - /home/step: Access to step-ca root certificate
#
# Port Exposure:
#   - 8443: HTTPS EST endpoint
#
# ==============================================================================

# Stage 1: Build the EST server binary
FROM golang:1.21-alpine AS builder

WORKDIR /build

# Install git for go get
RUN apk add --no-cache git make

# Clone and build the Foundries.io EST server
RUN git clone https://github.com/foundriesio/estserver.git . && \
    make bin/estserver

# ==============================================================================

# Stage 2: Runtime image
FROM alpine:latest

# Install runtime dependencies
# Add edge/community repository for step-cli package
RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \
    apk add --no-cache \
    bash \
    curl \
    ca-certificates \
    openssl \
    step-cli

# Copy EST server binary from builder
COPY --from=builder /build/bin/estserver /usr/local/bin/estserver
RUN chmod +x /usr/local/bin/estserver

# Create EST data directory
RUN mkdir -p /est/data /est/secrets

# Copy initialization and startup scripts
COPY --chmod=755 init-est.sh /usr/local/bin/init-est.sh
COPY --chmod=755 start-est.sh /usr/local/bin/start-est.sh

# Health check using EST /cacerts endpoint (RFC 7030)
HEALTHCHECK --interval=10s \
            --timeout=5s \
            --start-period=30s \
            --retries=5 \
  CMD curl -k -f https://localhost:8443/.well-known/est/cacerts || exit 1

# Expose EST port
EXPOSE 8443

# Run initialization and start script
ENTRYPOINT ["/usr/local/bin/start-est.sh"]
