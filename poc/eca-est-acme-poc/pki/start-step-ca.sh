#!/bin/bash
# Wrapper script that delegates to base image entrypoint for initialization
# then runs provisioner configuration

set -e

echo "[START] PKI wrapper script starting..."

# Check if CA is already initialized
if [ ! -f "/home/step/config/ca.json" ]; then
    echo "[INIT] CA not initialized - using base image entrypoint for first-time setup"

    # Call the base image's entrypoint which handles DOCKER_STEPCA_INIT_ vars properly
    exec /usr/local/bin/docker-entrypoint.sh step-ca --password-file=/home/step/secrets/password /home/step/config/ca.json
else
    echo "[START] CA already initialized"

    # Start step-ca in background
    echo "[START] Starting step-ca service in background..."
    step-ca /home/step/config/ca.json --password-file=/home/step/secrets/password &
    STEP_CA_PID=$!

    # Wait for step-ca to be healthy
    echo "[INIT] Waiting for step-ca to be ready..."
    for i in $(seq 1 30); do
        if curl -k -f https://localhost:9000/health > /dev/null 2>&1; then
            echo "[INIT] step-ca is healthy"
            break
        fi
        echo "[INIT] Attempt $i/30: waiting for step-ca..."
        sleep 2
    done

    # Run provisioner configuration if not done yet
    if [ ! -f "/home/step/.provisioners_configured" ]; then
        echo "[INIT] Configuring ACME and EST provisioners..."
        if [ -f "/usr/local/bin/configure-provisioners.sh" ]; then
            /usr/local/bin/configure-provisioners.sh
            touch /home/step/.provisioners_configured
            # Restart step-ca to load the new provisioners
            echo "[INIT] Restarting step-ca to load provisioners..."
            kill $STEP_CA_PID
            sleep 2
            step-ca /home/step/config/ca.json --password-file=/home/step/secrets/password &
            STEP_CA_PID=$!
            sleep 5
        fi
    else
        echo "[START] Provisioners already configured"
    fi

    # Enable and configure CRL if not done yet
    if [ ! -f "/home/step/.crl_configured" ]; then
        echo "[INIT] Enabling CRL support..."
        if [ -f "/home/step/scripts/enable-crl.sh" ]; then
            /home/step/scripts/enable-crl.sh
            touch /home/step/.crl_configured
            # Restart step-ca to apply CRL configuration
            echo "[INIT] Restarting step-ca to enable CRL..."
            kill $STEP_CA_PID
            sleep 2
            step-ca /home/step/config/ca.json --password-file=/home/step/secrets/password &
            STEP_CA_PID=$!
            sleep 5
        fi
    else
        echo "[START] CRL already configured"
    fi

    # Setup CRL generation and HTTP serving
    echo "[INIT] Setting up CRL generation and HTTP server..."
    if [ -f "/home/step/scripts/setup-crl-cron.sh" ]; then
        /home/step/scripts/setup-crl-cron.sh
    fi
    if [ -f "/home/step/scripts/serve-crl-http.sh" ]; then
        /home/step/scripts/serve-crl-http.sh &
    fi

    # Wait for step-ca process
    echo "[START] step-ca initialization complete, monitoring process..."
    wait $STEP_CA_PID
fi
