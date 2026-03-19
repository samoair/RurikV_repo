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

# Clean up leftover resources from previous installs
kubectl delete mutatingwebhookconfiguration vault-agent-injector-cfg --ignore-not-found --force --grace-period=0 2>/dev/null || true
# Delete ConfigMap to avoid Helm field manager conflicts (Helm will recreate it)
kubectl delete configmap vault-config -n vault --ignore-not-found --wait=false 2>/dev/null || true
sleep 3

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

echo "Waiting for Vault pods to start..."
sleep 30

# Check if ConfigMap needs patching (only patch if HOST_IP is still present)
echo "Checking Vault ConfigMap..."
CONFIG_DATA=$(kubectl get configmap vault-config -n vault -o jsonpath='{.data.extraconfig-from-values\.hcl}' 2>/dev/null || true)

if echo "$CONFIG_DATA" | grep -q 'HOST_IP'; then
    echo "Patching Vault ConfigMap for Consul address..."
    kubectl get configmap vault-config -n vault -o json | python3 -c "
import json, sys
cm = json.load(sys.stdin)
data = cm['data'].get('extraconfig-from-values.hcl', '')
if 'HOST_IP:8500' in data:
    cm['data']['extraconfig-from-values.hcl'] = data.replace('HOST_IP:8500', 'consul-consul-server.consul.svc.cluster.local:8500')
json.dump(cm, sys.stdout)
" | kubectl replace -f - 2>/dev/null

    # Remove annotation again so next Helm upgrade doesn't conflict
    kubectl annotate configmap vault-config -n vault kubectl.kubernetes.io/last-applied-configuration- --ignore-not-found 2>/dev/null || true

    echo "Restarting Vault pods to pick up patched config..."
    kubectl delete pod -n vault -l app.kubernetes.io/name=vault --force --grace-period=0 2>/dev/null || true
    sleep 30
else
    echo "ConfigMap already has correct Consul address. Skipping patch."
fi

echo "========================================="
echo "Vault installation completed!"
echo "========================================="
echo ""
echo "Vault pods:"
kubectl get pods -n vault
echo ""
echo "Next step: Run ./03-init-vault.sh"
echo ""
