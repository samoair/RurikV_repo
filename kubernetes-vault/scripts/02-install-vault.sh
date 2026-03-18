#!/bin/bash
# ============================================================================
# Script 2: Install Vault in HA mode with Consul storage
# ============================================================================

set -e

echo "========================================="
echo "Installing Vault in HA mode..."
echo "========================================="

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: kubectl is not configured or cluster is not accessible"
    echo "Please run: yc managed-kubernetes cluster get-credentials vault-cluster --external"
    exit 1
fi

# Check if Consul is ready
echo "Checking Consul status..."
if ! kubectl get pods -n consul -l app=consul,component=server 2>/dev/null | grep -q Running; then
    echo "Error: Consul is not ready. Please install Consul first."
    echo "Run: ./01-install-consul.sh"
    exit 1
fi

# Create vault namespace
echo "Creating vault namespace..."
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -

# Add HashiCorp Helm repository (if not already added)
echo "Ensuring HashiCorp Helm repository..."
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
helm repo update

# Install Vault with Consul HA storage
echo "Installing Vault..."
helm upgrade --install vault hashicorp/vault \
  --namespace vault \
  --values ../helm/vault-values.yaml \
  --timeout 10m

echo "Waiting for Vault pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n vault --timeout=300s || true

echo "========================================="
echo "Vault installation completed!"
echo "========================================="
echo ""
echo "Vault pods:"
kubectl get pods -n vault -l app.kubernetes.io/name=vault
echo ""
echo "Next steps:"
echo "  1. Run: ./03-init-vault.sh"
echo "  2. Unseal Vault (follow instructions)"
echo ""
