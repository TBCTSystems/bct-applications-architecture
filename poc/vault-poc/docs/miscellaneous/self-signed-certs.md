# Generate Certificates (Self-Signed)

> ⚠️ This is only required if you don’t have real certificates from a trusted CA. In production, you’d get a valid certificate so users don’t have to manually trust your CA.

## Generate a CA private key
```bash
openssl genrsa -out ca.key 2048
```
Verification:
```bash
ls
ca.key
```

## Create a Root CA
```bash
openssl req -x509 -new -nodes -key ca.key -sha256 -days 365 -out ca.crt -subj "/C=US/ST=MyState/L=MyCity/O=MyOrg/OU=DevOps/CN=MyRootCA"
```
Verification:
```bash
ls
ca.crt  ca.key
```

##Create Vault Server Certificate

Generate a private key for Vault:

```bash
openssl genrsa -out vault.key 2048
```

Manually create a file named `vault.ext` with the following content:
```
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
IP.1 = 127.0.0.1
```

This ensures the server certificate is valid for connections to `localhost` or `127.0.0.1`.

Create a CSR:
```bash
openssl req -new -key vault.key \
  -out vault.csr \
  -subj "/C=US/ST=MyState/L=MyCity/O=MyOrg/OU=Server/CN=localhost"
```

Sign the server cert:
```bash
openssl x509 -req -in vault.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out vault.crt -days 365 -sha256 \
  -extfile vault.ext
```

Verification:

```bash
ls
```

Expected files:
```
ca.crt   ca.key   ca.srl
vault.key   vault.csr   vault.crt   vault.ext
```

## Create a Client Certificate (for .NET)

As the goal is to authenticate the .NET app to Vault with cert-based auth, you need a client certificate signed by the same CA.

Generate a private key for the client:
```bash
openssl genrsa -out client.key 2048
```

Create a CSR (Common Name = dotnet-client):
```bash
openssl req -new -key client.key \
  -out client.csr \
  -subj "/C=US/ST=MyState/L=MyCity/O=MyOrg/OU=Client/CN=dotnet-client"
```

Manually create a file named `client.ext` with:
```ini
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
```

Explanation: This indicates the certificate is intended for client authentication (`extendedKeyUsage = clientAuth`).

Sign the client certificate using your CA:
```bash
openssl x509 -req -in client.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out client.crt -days 365 -sha256 \
  -extfile client.ext
```

Verification:
```bash
ls | grep client
```
Expected new files related to the client:
```
client.key   client.csr   client.crt   client.ext
```

### Create a PFX for .NET

If your .NET app prefers a .pfx or .p12 file:
```bash
openssl pkcs12 -export \
  -out client.pfx \
  -inkey client.key \
  -in client.crt \
  -certfile ca.crt \
  -passout pass:
```
(Leaving `-passout pass:` blank sets no password. Or replace with a real pass, e.g. `-passout pass:changeit`.)

Verification:
```bash
ls | grep client
```
```
client.key   client.csr   client.crt   client.ext   client.pfx
```

`.pfx` files bundle the client certificate and private key in one password-protected file that’s easy for .NET to load.
