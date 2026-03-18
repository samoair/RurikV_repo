#!/bin/bash
# ============================================================================
# Script 5: Install External Secrets Operator and apply manifests
# ============================================================================

set -e

echo "========================================="
echo "Installing External Secrets Operator..."
echo "========================================="

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: kubectl is not configured or cluster is not accessible"
    exit 1
fi

# Add ESO Helm repository
echo "Adding External Secrets Operator Helm repository..."
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install External Secrets Operator
echo "Installing External Secrets Operator..."
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace vault \
  --values ../helm/eso-values.yaml \
  --create-namespace \
  --timeout 10m

echo "Waiting for ESO pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=external-secrets -n vault --timeout=300s

echo "========================================="
echo "External Secrets Operator installed!"
echo "========================================="
echo ""
echo "ESO pods:"
kubectl get pods -n vault -l app.kubernetes.io/name=external-secrets

# Apply manifests
echo ""
echo "========================================="
echo "Applying Kubernetes manifests..."
echo "========================================="

# Apply namespaces (should already exist)
echo "Applying namespaces..."
kubectl apply -f ../manifests/namespaces.yaml

# Apply service account and RBAC
echo "Applying vault-auth service account and RBAC..."
kubectl apply -f ../manifests/vault-auth-rbac.yaml

# Wait a bit for service account to be ready
sleep 2

# Apply SecretStore
echo "Applying SecretStore..."
kubectl apply -f ../manifests/secretstore.yaml

echo "Waiting for SecretStore to be ready..."
sleep 5

# Check SecretStore status
echo ""
echo "SecretStore status:"
kubectl get secretstore -n vault
kubectl describe secretstore vault-backend -n vault | tail -20

# Apply ExternalSecret
echo ""
echo "Applying ExternalSecret..."
kubectl apply -f ../manifests/externalsecret.yaml

echo "Waiting for ExternalSecret to sync..."
sleep 10

# Check ExternalSecret status
echo ""
echo "ExternalSecret status:"
kubectl get externalsecret -n vault
kubectl describe externalsecret otus-cred -n vault | tail -20

# Check if the secret was created
echo ""
echo "Checking for otus-cred secret..."
if kubectl get secret otus-cred -n vault &>/dev/null; then
    echo "========================================="
    echo "SUCCESS! Secret otus-cred created!"
    echo "========================================="
    echo ""
    echo "Secret details:"
    kubectl get secret otus-cred -n vault -o yaml
    echo ""
    echo "Secret contents (decoded):"
    echo "Username: $(kubectl get secret otus-cred -n vault -o jsonpath='{.data.username}' | base64 -d)"
    echo "Password: $(kubectl get secret otus-cred -n vault -o jsonpath='{.data.password}' | base64 -d)"
    echo ""
else
    echo "========================================="
    echo "WARNING: Secret otus-cred not found!"
    echo "========================================="
    echo ""
    echo "Check ExternalSecret status for errors:"
    echo "  kubectl describe externalsecret otus-cred -n vault"
    echo ""
    echo "Check ESO controller logs:"
    echo "  kubectl logs -n vault -l app.kubernetes.io/name=external-secrets"
    echo ""
fi

echo "========================================="
echo "Setup completed!"
echo "========================================="
echo ""
echo "To verify everything is working:"
echo "  kubectl get secretstore -n vault"
echo "  kubectl get externalsecret -n vault"
echo "  kubectl get secret otus-cred -n vault -o yaml"
echo ""
