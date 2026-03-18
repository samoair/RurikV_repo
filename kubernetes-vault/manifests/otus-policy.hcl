# ============================================================================
# Vault Policy: otus-policy
# This policy allows read and list access to secrets under /otus/ path
# ============================================================================
# Usage:
#   vault policy write otus-policy otus-policy.hcl
# ============================================================================

# Allow reading and listing the /otus/cred secret
path "otus/data/cred" {
  capabilities = ["read", "list"]
}

# Allow reading and listing the /otus path (KV v2 metadata)
path "otus/metadata/cred" {
  capabilities = ["read", "list"]
}

# Allow listing the otus directory
path "otus/*" {
  capabilities = ["list"]
}
