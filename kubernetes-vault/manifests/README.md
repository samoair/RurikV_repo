# Kubernetes Vault Homework Manifests

This directory contains Kubernetes manifests for the Vault homework assignment.

## Files

### 1. Namespace Manifests
- `namespaces.yaml` - Creates `consul` and `vault` namespaces

### 2. Service Account and RBAC
- `vault-auth-rbac.yaml` - ServiceAccount `vault-auth` and ClusterRoleBinding with `system:auth-delegator` role

### 3. Vault Policy
- `otus-policy.hcl` - Vault policy for accessing `/otus/cred` secrets with read and list capabilities

### 4. SecretStore CRD
- `secretstore.yaml` - SecretStore custom resource configured to access Vault using the `otus` role and `vault-auth` service account

### 5. ExternalSecret CRD
- `externalsecret.yaml` - ExternalSecret custom resource that fetches `/otus/cred` from Vault and creates `otus-cred` secret

## Usage

### Apply all manifests in order:
```bash
# 1. Create namespaces
kubectl apply -f namespaces.yaml

# 2. Create service account and RBAC
kubectl apply -f vault-auth-rbac.yaml

# 3. After Vault is initialized and configured, apply SecretStore
kubectl apply -f secretstore.yaml

# 4. Verify SecretStore is ready
kubectl get secretstore -n vault

# 5. Apply ExternalSecret
kubectl apply -f externalsecret.yaml

# 6. Verify the secret was created
kubectl get secret otus-cred -n vault -o yaml

# 7. Verify secret contents
kubectl get secret otus-cred -n vault -o jsonpath='{.data}' | jq
```

## Prerequisites

Before applying these manifests, ensure that:
1. Consul is installed and running in `consul` namespace
2. Vault is installed and running in `vault` namespace
3. Vault is initialized and unsealed
4. Vault has KV secrets engine enabled at `/otus`
5. Vault has secret `/otus/cred` with `username` and `password` keys
6. Vault Kubernetes auth method is enabled and configured
7. Vault role `otus` is created with policy `otus-policy`

## Troubleshooting

### Check SecretStore status:
```bash
kubectl describe secretstore vault-backend -n vault
```

### Check ExternalSecret status:
```bash
kubectl describe externalsecret otus-cred -n vault
```

### Check Vault role:
```bash
vault read auth/kubernetes/role/otus
```

### Check Vault policy:
```bash
vault policy read otus-policy
```
