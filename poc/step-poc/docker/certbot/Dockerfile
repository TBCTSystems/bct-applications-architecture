FROM certbot/certbot:latest

# Install additional tools for certificate management
RUN apk add --no-cache \
    curl \
    jq \
    openssl \
    bash \
    ca-certificates \
    wget

# Create directories for certificates and scripts
RUN mkdir -p /certs /ca-certs /scripts /var/log/certbot

# Copy certificate management scripts
COPY scripts/certbot-renew.sh /usr/local/bin/certbot-renew.sh
COPY scripts/certificate-monitor.sh /usr/local/bin/certificate-monitor.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/certbot-renew.sh
RUN chmod +x /usr/local/bin/certificate-monitor.sh

# Set working directory
WORKDIR /opt/certbot

# Default entrypoint
ENTRYPOINT ["/usr/local/bin/certbot-renew.sh"]