#!/usr/bin/env bash
################################################################################
# step-ca Container Entrypoint Wrapper
#
# Purpose: Orchestrate two-stage PKI initialization and startup
#
# Execution Flow:
#   1. Run init-pki.sh to initialize CA (if needed)
#   2. Start step-ca in background
#   3. Wait for step-ca to become healthy
#   4. Run configure-provisioners.sh to add ACME/EST provisioners
#   5. Bring step-ca to foreground (keep container running)
#
# This approach ensures provisioner configuration happens AFTER step-ca is
# running and healthy, avoiding the circular dependency that caused infinite
# restart loops.
#
################################################################################

set -euo pipefail

readonly CONFIG_FILE="/home/step/config/ca.json"

log_info() {
    echo "[ENTRYPOINT] $1"
}

log_error() {
    echo "[ENTRYPOINT ERROR] $1" >&2
}

################################################################################
# Main Execution
################################################################################

log_info "Starting step-ca container initialization..."

# -------------------------------------------------------------------------
# Stage 1: Initialize CA (idempotent)
# -------------------------------------------------------------------------

log_info "Stage 1: Use base image's entrypoint for initialization..."

# The base image's /entrypoint.sh script handles DOCKER_STEPCA_INIT_* variables properly
# Instead of reimplementing that logic, just call it directly
# But we need to run it in a way that lets us continue afterward

# Check if CA is already initialized
if [ -f "/home/step/certs/root_ca.crt" ]; then
    log_info "CA already initialized, skipping base entrypoint"
else
    log_info "CA not initialized, calling base image entrypoint to initialize..."

    # Source the base image entrypoint to get its initialization logic
    # This properly handles DOCKER_STEPCA_INIT_* without TTY issues
    if [ -f "/entrypoint.sh" ]; then
        # Run the base entrypoint in initialization mode
        # The base entrypoint will call step ca init properly
        source /entrypoint.sh || {
            log_error "Base entrypoint initialization failed"
            exit 1
        }
    else
        log_error "/entrypoint.sh not found"
        exit 1
    fi

    log_info "Base entrypoint initialization complete"
fi

# -------------------------------------------------------------------------
# Stage 2: Start step-ca in background
# -------------------------------------------------------------------------

log_info "Stage 2: Starting step-ca service in background..."

# Start step-ca in background with proper signal handling
step-ca "/home/step/config/ca.json" --password-file=<(echo "") &
STEP_CA_PID=$!

log_info "step-ca started with PID ${STEP_CA_PID}"

# Give it a moment to start listening
sleep 3

# -------------------------------------------------------------------------
# Stage 3: Configure provisioners
# -------------------------------------------------------------------------

log_info "Stage 3: Configuring ACME and EST provisioners..."

if /usr/local/bin/configure-provisioners.sh; then
    log_info "Provisioner configuration completed successfully"
else
    log_error "Provisioner configuration failed"
    # Kill step-ca and exit
    kill "${STEP_CA_PID}" 2>/dev/null || true
    exit 1
fi

# -------------------------------------------------------------------------
# Stage 4: Keep container running with step-ca
# -------------------------------------------------------------------------

log_info "Initialization complete. step-ca is running and configured."
log_info "Bringing step-ca to foreground..."

# Wait for step-ca process to exit (keeps container alive)
# This also ensures proper signal handling for graceful shutdown
wait "${STEP_CA_PID}"
EXIT_CODE=$?

log_info "step-ca exited with code ${EXIT_CODE}"
exit ${EXIT_CODE}
