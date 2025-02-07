# For KV v2 secrets engine
path "secret/data/myapp/*" {
  capabilities = ["create", "update", "read", "delete", "list"]
}