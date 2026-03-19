#!/bin/bash
# ============================================================================
# Script 4: Configure Kubernetes authentication in Vault
# ============================================================================

set -e

echo "========================================="
echo "Configuring Kubernetes authentication..."
echo "========================================="

# Check if root token exists
if [ ! -f "vault-root-token.txt" ]; then
    echo "Error: vault-root-token.txt not found."
    echo "Please run ./03-init-vault.sh first."
    exit 1
fi

# Get Vault pod
VAULT_POD=$(kubectl get pods -n vault -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')

# Apply vault-auth ServiceAccount and RBAC
echo "Applying vault-auth ServiceAccount and RBAC..."
kubectl apply -f ../manifests/vault-auth-rbac.yaml
echo "vault-auth ServiceAccount created."

# Read root token
ROOT_TOKEN=$(cat vault-root-token.txt)

# Get Kubernetes cluster info
K8S_HOST=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}')
# Remove protocol from host for Vault
K8S_HOST=${K8S_HOST#https://}
K8S_HOST=${K8S_HOST#http://}

# Get Kubernetes CA certificate (save to file for proper JSON handling)
kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > /tmp/vault-k8s-ca.crt

# Get service account JWT (use kubectl create token for K8s 1.24+)
SA_JWT=$(kubectl create token vault-auth -n vault --duration=24h)

echo "Kubernetes API host: $K8S_HOST"
echo "Service Account: vault-auth"
echo "Service Account JWT obtained"

# Port-forward to Vault
echo ""
echo "Setting up port-forward to Vault..."
kubectl port-forward -n vault "$VAULT_POD" 8200:8200 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

# Cleanup function
cleanup() {
    kill $PF_PID 2>/dev/null || true
    rm -f /tmp/vault-k8s-ca.crt /tmp/vault-k8s-config.json
}
trap cleanup EXIT

VAULT_ADDR="http://127.0.0.1:8200"
VAULT_HEADER="X-Vault-Token: $ROOT_TOKEN"

echo "Port-forward established"

# Enable Kubernetes auth method
echo ""
echo "Enabling Kubernetes auth method..."
AUTH_METHODS=$(curl -s -H "$VAULT_HEADER" "$VAULT_ADDR/v1/sys/auth")
if echo "$AUTH_METHODS" | grep -q 'kubernetes/'; then
    echo "Kubernetes auth already enabled. Skipping."
else
    curl -s -X POST -H "$VAULT_HEADER" "$VAULT_ADDR/v1/sys/auth/kubernetes" \
        -d '{"type":"kubernetes"}'
    echo "Kubernetes auth enabled."
fi

# Configure Kubernetes auth method using python3 for proper JSON escaping
echo "Configuring Kubernetes auth method..."
python3 -c "
import json
ca_cert = open('/tmp/vault-k8s-ca.crt').read()
config = {
    'kubernetes_host': 'https://$K8S_HOST',
    'kubernetes_ca_cert': ca_cert,
    'token_reviewer_jwt': '''$SA_JWT'''
}
with open('/tmp/vault-k8s-config.json', 'w') as f:
    json.dump(config, f)
"
curl -s -X POST -H "$VAULT_HEADER" -H "Content-Type: application/json" \
    "$VAULT_ADDR/v1/auth/kubernetes/config" \
    -d @/tmp/vault-k8s-config.json
echo "Kubernetes auth configured."

# Write the otus-policy
echo ""
echo "Writing Vault policy: otus-policy..."
curl -s -X PUT -H "$VAULT_HEADER" -H "Content-Type: application/json" \
    "$VAULT_ADDR/v1/sys/policies/acl/otus-policy" \
    -d '{
        "policy": "path \"otus/data/cred\" {\n  capabilities = [\"read\", \"list\"]\n}\npath \"otus/metadata/cred\" {\n  capabilities = [\"read\", \"list\"]\n}\npath \"otus/*\" {\n  capabilities = [\"list\"]\n}"
    }'
echo "Policy written."

# Create the otus role
echo "Creating Vault role: otus..."
curl -s -X POST -H "$VAULT_HEADER" -H "Content-Type: application/json" \
    "$VAULT_ADDR/v1/auth/kubernetes/role/otus" \
    -d '{
        "bound_service_account_names": "vault-auth",
        "bound_service_account_namespaces": "vault",
        "policies": ["otus-policy"],
        "ttl": "24h"
    }'
echo "Role created."

# Verify
echo ""
echo "Verifying role:"
curl -s -H "$VAULT_HEADER" "$VAULT_ADDR/v1/auth/kubernetes/role/otus" | python3 -m json.tool

echo ""
echo "========================================="
echo "Kubernetes authentication configured!"
echo "========================================="
echo ""
echo "Next step: Run ./05-install-eso.sh"
echo ""
