FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Step CLI
RUN wget -O step.deb https://github.com/smallstep/cli/releases/download/v0.25.0/step-cli_0.25.0_amd64.deb \
    && dpkg -i step.deb \
    && rm step.deb

# Create application directory
WORKDIR /app

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ ./src/
COPY main.py .

# Create directories for certificates and logs
RUN mkdir -p certs logs config

# Create non-root user
RUN useradd -m -u 1001 certrenew
RUN chown -R certrenew:certrenew /app
USER certrenew

# Set up environment
ENV PYTHONPATH=/app
ENV CERT_RENEWAL_LOG_LEVEL=INFO
ENV CERT_RENEWAL_CERT_STORAGE_PATH=/app/certs

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python main.py status --format json > /dev/null || exit 1

# Default command
CMD ["python", "main.py", "daemon"]