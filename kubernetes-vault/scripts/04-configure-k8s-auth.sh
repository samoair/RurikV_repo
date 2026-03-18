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

# Get Kubernetes cluster info
K8S_HOST=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}')
# Remove protocol from host for Vault
K8S_HOST=${K8S_HOST#https://}
K8S_HOST=${K8S_HOST#http://}

# Get Kubernetes CA certificate and save to file
kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > k8s-ca.crt

# Get service account JWT
SECRET_NAME=$(kubectl get sa -n vault vault-auth -o jsonpath='{.secrets[0].name}')
SA_JWT=$(kubectl get secret -n vault "$SECRET_NAME" -o jsonpath='{.data.token}' | base64 -d)

echo "Kubernetes API host: $K8S_HOST"
echo "Service Account: vault-auth"
echo "Service Account JWT obtained"
echo "CA certificate saved to k8s-ca.crt"

# Port-forward to Vault
echo ""
echo "Setting up port-forward to Vault..."
kubectl port-forward -n vault "$VAULT_POD" 8200:8200 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

# Cleanup function
cleanup() {
    kill $PF_PID 2>/dev/null || true
}
trap cleanup EXIT

# Export VAULT_ADDR and VAULT_TOKEN for local vault CLI
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN=$(cat vault-root-token.txt)

echo "Port-forward established"

# Enable Kubernetes auth method
echo ""
echo "Enabling Kubernetes auth method..."
kubectl exec -n vault "$VAULT_POD" -- vault auth enable kubernetes

# Copy the CA certificate into the Vault pod
echo "Copying CA certificate into Vault pod..."
kubectl cp k8s-ca.crt "$VAULT_POD":/tmp/k8s-ca.crt -n vault

# Configure Kubernetes auth method using the local Vault CLI with port-forward
echo "Configuring Kubernetes auth method..."
vault write auth/kubernetes/config \
  kubernetes_host="$K8S_HOST" \
  kubernetes_ca_cert=@k8s-ca.crt \
  token_reviewer_jwt="$SA_JWT"

# Write the otus-policy
echo ""
echo "Writing Vault policy: otus-policy..."
vault policy write otus-policy - <<EOF
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
EOF

# Create the otus role
echo "Creating Vault role: otus..."
vault write auth/kubernetes/role/otus \
  bound_service_account_names=vault-auth \
  bound_service_account_namespaces=vault \
  policies=otus-policy \
  ttl=24h

echo ""
echo "========================================="
echo "Kubernetes authentication configured!"
echo "========================================="
echo ""
echo "Verify configuration:"
echo "  vault read auth/kubernetes/role/otus"
echo "  vault policy read otus-policy"
echo ""
echo "Test authentication:"
echo "  vault write auth/kubernetes/login role=otus jwt=\$SA_JWT"
echo ""
echo "Next step: Run ./05-install-eso.sh"
echo ""
