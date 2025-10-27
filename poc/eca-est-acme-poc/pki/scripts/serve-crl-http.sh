#!/bin/bash
# ==============================================================================
# Serve CRL via HTTP using nginx
# ==============================================================================
# This script configures and starts nginx to serve CRL files via HTTP
# The CRL will be accessible at http://pki:9000/crl/ca.crl
#
# Note: step-ca runs on HTTPS (port 9000), so we use a different port for HTTP
# or configure nginx as a reverse proxy with additional static file serving.
# ==============================================================================

set -e

NGINX_CONF="/etc/nginx/http.d/crl.conf"
CRL_DIR="/home/step/crl"

echo "[CRL-HTTP] Configuring nginx to serve CRL files..."

# Create nginx configuration for CRL endpoint
mkdir -p "$(dirname "$NGINX_CONF")"

cat > "$NGINX_CONF" <<'EOF'
# CRL HTTP Server Configuration
server {
    listen 9001;
    server_name pki localhost;

    # CRL directory
    location /crl/ {
        alias /home/step/crl/;
        autoindex on;
        add_header Content-Type application/pkix-crl;
        add_header Cache-Control "max-age=3600, must-revalidate";
    }

    # Health check
    location /health {
        access_log off;
        return 200 "CRL server healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

echo "[CRL-HTTP] nginx configuration created at $NGINX_CONF"

# Test nginx configuration
if command -v nginx > /dev/null 2>&1; then
    echo "[CRL-HTTP] Testing nginx configuration..."
    nginx -t
    echo "[CRL-HTTP] Starting nginx..."
    nginx
    echo "[CRL-HTTP] nginx started successfully"
    echo "[CRL-HTTP] CRL accessible at http://pki:9001/crl/ca.crl"
else
    echo "[CRL-HTTP] WARNING: nginx not found - install with 'apk add nginx'"
fi
