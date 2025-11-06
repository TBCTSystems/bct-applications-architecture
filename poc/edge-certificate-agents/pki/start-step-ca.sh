#!/bin/bash
# Wrapper script that delegates to base image entrypoint for initialization
# then runs provisioner configuration

set -euo pipefail

echo "[START] PKI wrapper script starting..."

PASSWORD_FILE="/home/step/secrets/password"
STEP_CA_PASSWORD_ARGS=()

ensure_password_args() {
    if [ -f "$PASSWORD_FILE" ]; then
        STEP_CA_PASSWORD_ARGS=("--password-file=$PASSWORD_FILE")
    elif [ -f "/home/step/password" ]; then
        mkdir -p "$(dirname "$PASSWORD_FILE")"
        cp /home/step/password "$PASSWORD_FILE"
        chmod 600 "$PASSWORD_FILE"
        STEP_CA_PASSWORD_ARGS=("--password-file=$PASSWORD_FILE")
        echo "[INFO] Restored password file to $PASSWORD_FILE"
    elif [ -n "${DOCKER_STEPCA_INIT_PASSWORD:-}" ]; then
        mkdir -p "$(dirname "$PASSWORD_FILE")"
        printf "%s" "${DOCKER_STEPCA_INIT_PASSWORD}" > "$PASSWORD_FILE"
        chmod 600 "$PASSWORD_FILE"
        STEP_CA_PASSWORD_ARGS=("--password-file=$PASSWORD_FILE")
        echo "[INFO] Created password file from DOCKER_STEPCA_INIT_PASSWORD"
    else
        STEP_CA_PASSWORD_ARGS=()
        echo "[WARN] Password file $PASSWORD_FILE not found; starting without password file"
    fi
}

start_step_ca() {
    step-ca /home/step/config/ca.json "${STEP_CA_PASSWORD_ARGS[@]}" &
    STEP_CA_PID=$!
}

start_crl_refresh_loop() {
    local crl_script="/home/step/scripts/generate-crl.sh"
    local loop_pid_file="/home/step/.crl_loop.pid"

    if [ ! -x "$crl_script" ]; then
        echo "[CRL] WARNING: CRL generation script missing or not executable"
        return
    fi

    if [ -f "$loop_pid_file" ]; then
        local existing_pid=""
        if [ -r "$loop_pid_file" ]; then
            existing_pid="$(cat "$loop_pid_file")"
        fi
        if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
            echo "[CRL] Stopping existing CRL refresh loop (PID $existing_pid)"
            kill "$existing_pid" 2>/dev/null || true
        fi
        rm -f "$loop_pid_file"
    fi

    echo "[CRL] Running initial CRL generation..."
    if ! "$crl_script"; then
        echo "[CRL] WARNING: Initial CRL generation failed"
    fi

    echo "[CRL] Starting background CRL refresh loop..."
    (
        while true; do
            sleep 3600
            "$crl_script" || echo "[CRL] WARNING: Scheduled CRL generation failed" >&2
        done
    ) &
    echo $! > "$loop_pid_file"
}

ensure_crl_services() {
    local http_script="/home/step/scripts/serve-crl-http.sh"

    if [ -x "$http_script" ]; then
        if ! "$http_script"; then
            echo "[CRL-HTTP] WARNING: Failed to configure nginx-based CRL server"
        fi
    else
        echo "[CRL-HTTP] WARNING: CRL HTTP script not found or not executable"
    fi

    start_crl_refresh_loop
}

# Function to check if step-ca is running
check_step_ca_running() {
    if ! kill -0 "$STEP_CA_PID" 2>/dev/null; then
        echo "[ERROR] step-ca process died unexpectedly" >&2
        return 1
    fi
    return 0
}

# Check if CA is already initialized
if [ ! -f "/home/step/config/ca.json" ]; then
    echo "[INIT] CA not initialized - using base image entrypoint for first-time setup"

    # Call the base image's entrypoint which handles DOCKER_STEPCA_INIT_ vars properly
    ensure_password_args
    exec /usr/local/bin/docker-entrypoint.sh step-ca "${STEP_CA_PASSWORD_ARGS[@]}" /home/step/config/ca.json
else
    echo "[START] CA already initialized"

    # Start step-ca in background
    echo "[START] Starting step-ca service in background..."
    ensure_password_args
    start_step_ca

    # Verify process started
    sleep 2
    if ! check_step_ca_running; then
        echo "[ERROR] Failed to start step-ca" >&2
        exit 1
    fi

    # Wait for step-ca to be healthy
    echo "[INIT] Waiting for step-ca to be ready..."
    healthy=false
    for i in $(seq 1 30); do
        if ! check_step_ca_running; then
            echo "[ERROR] step-ca process died while waiting for health check" >&2
            exit 1
        fi
        if curl -k -f https://localhost:9000/health > /dev/null 2>&1; then
            echo "[INIT] step-ca is healthy"
            healthy=true
            break
        fi
        echo "[INIT] Attempt $i/30: waiting for step-ca..."
        sleep 2
    done

    if [ "$healthy" = false ]; then
        echo "[ERROR] step-ca failed to become healthy within 60 seconds" >&2
        exit 1
    fi

    # Run provisioner configuration if not done yet
    if [ ! -f "/home/step/.provisioners_configured" ]; then
        echo "[INIT] Configuring ACME and EST provisioners..."
        if [ -f "/usr/local/bin/configure-provisioners.sh" ]; then
            if ! /usr/local/bin/configure-provisioners.sh; then
                echo "[ERROR] Failed to configure provisioners" >&2
                exit 1
            fi
            touch /home/step/.provisioners_configured
            # Restart step-ca to load the new provisioners
            echo "[INIT] Restarting step-ca to load provisioners..."
            kill "$STEP_CA_PID"
            sleep 2
            start_step_ca
            sleep 5
        fi
    else
        echo "[START] Provisioners already configured"
    fi

    # Enable and configure CRL if not done yet
    if [ ! -f "/home/step/.crl_configured" ]; then
        echo "[INIT] Enabling CRL support..."
        if [ -f "/home/step/scripts/enable-crl.sh" ]; then
            if ! /home/step/scripts/enable-crl.sh; then
                echo "[ERROR] Failed to enable CRL" >&2
                exit 1
            fi
            touch /home/step/.crl_configured
            # Restart step-ca to apply CRL configuration
            echo "[INIT] Restarting step-ca to enable CRL..."
            kill "$STEP_CA_PID"
            sleep 2
            start_step_ca
            sleep 5
        fi
    else
        echo "[START] CRL already configured"
    fi

    # Setup CRL generation and HTTP serving
    echo "[INIT] Setting up CRL generation and HTTP server..."
    ensure_crl_services

    # Wait for step-ca process
    echo "[START] step-ca initialization complete, monitoring process..."
    wait $STEP_CA_PID
fi
