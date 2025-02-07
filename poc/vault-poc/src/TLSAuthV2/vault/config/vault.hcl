ui = true                 # Enables Vault's built-in UI at https://localhost:8200/ui
disable_mlock = true      # Allow Vault to run without mlock. Usually needed in containers.

listener "tcp" {
  address             = "0.0.0.0:8200"                  # Listen on all interfaces inside Docker
  tls_cert_file       = "/vault/config/certs/vault.crt" # Path to the Vault server's TLS certificate
  tls_key_file        = "/vault/config/certs/vault.key" # Path to the Vault server's TLS private key
  tls_client_ca_file  = "/vault/config/certs/ca.crt"    # Trust this CA for client certs (mTLS)
}

storage "file" {
  path = "/vault/file"   # Simple file-based storage in the container's /vault/file directory
}