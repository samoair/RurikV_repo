#!/bin/bash
# ============================================================================
# Script 1: Install Consul in HA mode
# ============================================================================

set -e

echo "========================================="
echo "Installing Consul in HA mode..."
echo "========================================="

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: kubectl is not configured or cluster is not accessible"
    echo "Please run: yc managed-kubernetes cluster get-credentials vault-cluster --external"
    exit 1
fi

# Create consul namespace
echo "Creating consul namespace..."
kubectl create namespace consul --dry-run=client -o yaml | kubectl apply -f -

# Add HashiCorp Helm repository
echo "Adding HashiCorp Helm repository..."
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Install Consul with 3 server replicas (HA mode)
echo "Installing Consul..."
helm upgrade --install consul hashicorp/consul \
  --namespace consul \
  --values ../helm/consul-values.yaml \
  --timeout 10m

echo "Waiting for Consul pods to be ready..."
kubectl wait --for=condition=ready pod -l app=consul,component=server -n consul --timeout=300s

echo "========================================="
echo "Consul installation completed!"
echo "========================================="
echo ""
echo "Consul UI URL:"
kubectl get svc consul-ui -n consul -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null && echo ""
echo "Consul pods:"
kubectl get pods -n consul -l app=consul
echo ""
echo "Check Consul status:"
echo "  kubectl get pods -n consul"
echo "  kubectl exec -n consul -it consul-0 -- consul members"
