storage "file" {
  path = "/bao/data"   # Directory where OpenBao will store its data
}

listener "tcp" {
  address                            = "0.0.0.0:8200"
  tls_cert_file                      = "/bao/certs/server.crt"
  tls_key_file                       = "/bao/certs/server.key"
  tls_disable                        = false
  tls_require_and_verify_client_cert = true   # Enable mTLS
  tls_client_ca_file                 = "/bao/certs/client-ca.crt"  # Client CA to trust
}

