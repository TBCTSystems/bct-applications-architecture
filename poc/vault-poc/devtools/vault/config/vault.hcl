ui = true
disable_mlock = true

listener "tcp" {
  address             = "0.0.0.0:8200"
  tls_cert_file       = "/certs/vault.crt"
  tls_key_file        = "/certs/vault.key"
  tls_client_ca_file  = "/certs/ca.crt"
}

storage "file" {
  path = "/vault/file"
}
