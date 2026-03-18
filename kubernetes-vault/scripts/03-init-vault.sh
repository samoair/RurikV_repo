#!/bin/bash
# ============================================================================
# Script 3: Initialize Vault, unseal, and configure
# ============================================================================

set -e

echo "========================================="
echo "Initializing and configuring Vault..."
echo "========================================="

# Get first Vault pod
VAULT_POD=$(kubectl get pods -n vault -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')

if [ -z "$VAULT_POD" ]; then
    echo "Error: Vault pod not found. Is Vault installed?"
    exit 1
fi

echo "Using Vault pod: $VAULT_POD"

# Function to execute vault commands in the pod
vault_exec() {
    kubectl exec -n vault "$VAULT_POD" -- vault "$@"
}

# Check if Vault is already initialized
if vault_exec status -format json 2>/dev/null | grep -q '"initialized":true'; then
    echo "Vault is already initialized."
    echo "Skipping initialization."
else
    echo "Initializing Vault..."
    # Initialize Vault and save keys
    vault_exec init -key-shares=5 -key-threshold=3 -format=json > vault-init.json

    echo "========================================="
    echo "VAULT INITIALIZED!"
    echo "========================================="
    echo ""
    echo "Unseal keys have been saved to: vault-init.json"
    echo ""
    echo "IMPORTANT: Keep these keys safe! They are needed to unseal Vault."
    echo ""

    # Extract unseal keys and root token
    UNSEAL_KEYS=$(jq -r '.unseal_keys_b64[]' vault-init.json)
    ROOT_TOKEN=$(jq -r '.root_token' vault-init.json)

    echo "Root Token: $ROOT_TOKEN"
    echo ""
    echo "Unseal Keys:"
    echo "$UNSEAL_KEYS"
    echo ""

    # Save root token to file
    echo "$ROOT_TOKEN" > vault-root-token.txt
    chmod 600 vault-root-token.txt
    echo "Root token saved to: vault-root-token.txt"

    # Unseal Vault (need 3 keys out of 5)
    echo "========================================="
    echo "Unsealing Vault..."
    echo "========================================="

    # Get first 3 unseal keys
    KEY1=$(echo "$UNSEAL_KEYS" | sed -n '1p')
    KEY2=$(echo "$UNSEAL_KEYS" | sed -n '2p')
    KEY3=$(echo "$UNSEAL_KEYS" | sed -n '3p')

    echo "Unsealing with key 1..."
    vault_exec operator unseal "$KEY1" > /dev/null

    echo "Unsealing with key 2..."
    vault_exec operator unseal "$KEY2" > /dev/null

    echo "Unsealing with key 3..."
    vault_exec operator unseal "$KEY3" > /dev/null

    echo ""
    echo "Vault unsealed! Status:"
    vault_exec status
fi

# Export VAULT_ADDR and VAULT_TOKEN for local commands
export VAULT_ADDR='http://127.0.0.1:8200'
ROOT_TOKEN=$(cat vault-root-token.txt 2>/dev/null)
export VAULT_TOKEN="$ROOT_TOKEN"

# Port-forward to Vault
echo ""
echo "Setting up port-forward to Vault..."
kubectl port-forward -n vault "$VAULT_POD" 8200:8200 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

echo "Port-forward established (PID: $PF_PID)"

# Cleanup function
cleanup() {
    kill $PF_PID 2>/dev/null || true
}
trap cleanup EXIT

# Enable KV secrets engine at otus/
echo ""
echo "========================================="
echo "Configuring Vault..."
echo "========================================="

echo "Enabling KV secrets engine at /otus..."
vault_exec secrets enable -path=otus kv-v2

# Create secret otus/cred
echo "Creating secret otus/cred..."
vault_exec kv put otus/cred username="otus" password="asajkjkahs"

echo "Secret created. Verifying:"
vault_exec kv get otus/cred

echo ""
echo "========================================="
echo "Vault initialization completed!"
echo "========================================="
echo ""
echo "To interact with Vault locally:"
echo "  export VAULT_ADDR='http://127.0.0.1:8200'"
echo "  export VAULT_TOKEN=$(cat vault-root-token.txt)"
echo "  vault kv get otus/cred"
echo ""
echo "Next step: Run ./04-configure-k8s-auth.sh"
echo ""
