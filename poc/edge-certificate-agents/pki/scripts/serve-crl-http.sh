#!/bin/bash
# ==============================================================================
# Serve CRL via HTTP using unprivileged nginx instance
# ==============================================================================
# Configures and starts nginx in user space to expose CRL artifacts on port 9001.
# Designed to run as the non-root 'step' user inside the step-ca container.
# ==============================================================================

set -euo pipefail

CRL_DIR="/home/step/crl"
NGINX_BASE="/home/step/nginx-crl"
NGINX_CONF="${NGINX_BASE}/nginx.conf"
LOG_DIR="${NGINX_BASE}/logs"
PID_FILE="${NGINX_BASE}/nginx.pid"

echo "[CRL-HTTP] Preparing nginx workspace at ${NGINX_BASE}..."

mkdir -p "$CRL_DIR" "$LOG_DIR" \
         "${NGINX_BASE}/temp/client_body" \
         "${NGINX_BASE}/temp/proxy" \
         "${NGINX_BASE}/temp/fastcgi" \
         "${NGINX_BASE}/temp/uwsgi" \
         "${NGINX_BASE}/temp/scgi"

cat > "$NGINX_CONF" <<EOF
worker_processes  1;
error_log  ${LOG_DIR}/error.log;
pid        ${PID_FILE};

events {
    worker_connections  1024;
}

http {
    access_log  ${LOG_DIR}/access.log;
    sendfile    on;
    tcp_nopush  on;
    client_body_temp_path ${NGINX_BASE}/temp/client_body;
    proxy_temp_path       ${NGINX_BASE}/temp/proxy;
    fastcgi_temp_path     ${NGINX_BASE}/temp/fastcgi;
    uwsgi_temp_path       ${NGINX_BASE}/temp/uwsgi;
    scgi_temp_path        ${NGINX_BASE}/temp/scgi;

    server {
        listen       9001;
        listen       [::]:9001;
        server_name  _;

        add_header Cache-Control "no-cache";

        location = /crl {
            return 301 /crl/;
        }

        location /crl/ {
            alias ${CRL_DIR}/;
            autoindex off;
            types { application/pkix-crl crl; }
            default_type application/octet-stream;
            try_files \$uri \$uri/ =404;
        }

        location /health {
            access_log off;
            return 200 "CRL server healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
EOF

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
    echo "[CRL-HTTP] Reloading existing nginx instance..."
    nginx -p "$NGINX_BASE" -c "$NGINX_CONF" -s reload
else
    echo "[CRL-HTTP] Starting nginx for CRL serving..."
    nginx -p "$NGINX_BASE" -c "$NGINX_CONF"
fi

echo "[CRL-HTTP] nginx ready on port 9001 (serving ${CRL_DIR})"
