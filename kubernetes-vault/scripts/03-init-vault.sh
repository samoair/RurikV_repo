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

# Function to call Vault HTTP API inside the pod (for operations that need TTY)
vault_api() {
    local method=$1
    local path=$2
    local data=$3
    if [ -n "$data" ]; then
        kubectl exec -n vault "$VAULT_POD" -- /bin/sh -c \
            "wget -q -O - --post-data='$data' --header='Content-Type: application/json' http://127.0.0.1:8200/v1$path"
    else
        kubectl exec -n vault "$VAULT_POD" -- /bin/sh -c \
            "wget -q -O - --method=$method http://127.0.0.1:8200/v1$path"
    fi
}

# Check if Vault is already initialized
INIT_STATUS=$(vault_exec status 2>&1 || true)
if echo "$INIT_STATUS" | grep -q 'Initialized.*true'; then
    echo "Vault is already initialized."
    echo "Skipping initialization."
else
    echo "Initializing Vault..."
    # Use HTTP API for init (avoids TTY requirement)
    INIT_RESPONSE=$(vault_api POST "sys/init" '{"secret_shares":1,"secret_threshold":1}')
    echo "$INIT_RESPONSE" | python3 -m json.tool
    echo "$INIT_RESPONSE" > vault-init.json

    echo ""
    echo "Unseal keys have been saved to: vault-init.json"
    echo ""

    # Save root token
    ROOT_TOKEN=$(echo "$INIT_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['root_token'])")
    echo "$ROOT_TOKEN" > vault-root-token.txt
    chmod 600 vault-root-token.txt
    echo "Root token saved to: vault-root-token.txt"
fi

# Read root token
ROOT_TOKEN=$(cat vault-root-token.txt 2>/dev/null)

# Check if Vault is sealed and unseal if needed
SEAL_STATUS=$(vault_exec status 2>&1 || true)
if echo "$SEAL_STATUS" | grep -q 'Sealed.*true'; then
    if [ ! -f vault-init.json ]; then
        echo "Error: Vault is sealed but vault-init.json not found. Cannot unseal."
        exit 1
    fi

    echo "========================================="
    echo "Unsealing Vault..."
    echo "========================================="

    # Unseal using HTTP API (vault operator unseal requires TTY)
    UNSEAL_KEY=$(jq -r '.keys_base64[0]' vault-init.json)
    UNSEAL_RESULT=$(kubectl exec -n vault "$VAULT_POD" -- /bin/sh -c \
        "wget -q -O - --post-data='{\"key\": \"$UNSEAL_KEY\"}' --header='Content-Type: application/json' http://127.0.0.1:8200/v1/sys/unseal")

    if echo "$UNSEAL_RESULT" | grep -q '"sealed":false'; then
        echo "Vault unsealed successfully!"
    else
        echo "WARNING: Vault may still be sealed."
        echo "Result: $UNSEAL_RESULT"
    fi

    echo ""
    echo "Vault status:"
    vault_exec status || true
else
    echo "Vault is already unsealed."
fi

# Port-forward to Vault for local API access
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

# Configure Vault via port-forward using local curl
VAULT_ADDR="http://127.0.0.1:8200"
VAULT_HEADER="X-Vault-Token: $ROOT_TOKEN"

echo ""
echo "========================================="
echo "Configuring Vault..."
echo "========================================="

# Check if KV engine already enabled at /otus
echo "Checking KV secrets engine at /otus..."
MOUNTS=$(curl -s -H "$VAULT_HEADER" "$VAULT_ADDR/v1/sys/mounts")
if echo "$MOUNTS" | python3 -c "import json,sys; data=json.load(sys.stdin); sys.exit(0 if 'otus/' in data.get('data',{}) else 1)" 2>/dev/null; then
    echo "KV engine already enabled at /otus. Skipping."
else
    echo "Enabling KV secrets engine at /otus..."
    curl -s -X POST -H "$VAULT_HEADER" "$VAULT_ADDR/v1/sys/mounts/otus" \
        -d '{"type":"kv-v2"}'
    echo "KV engine enabled."
fi

# Create secret otus/cred
echo "Creating secret otus/cred..."
curl -s -X POST -H "$VAULT_HEADER" -H "Content-Type: application/json" \
    "$VAULT_ADDR/v1/otus/data/cred" \
    -d '{"data":{"username":"otus","password":"asajkjkahs"}}'
echo "Secret created."

# Verify secret
echo ""
echo "Verifying secret:"
curl -s -H "$VAULT_HEADER" "$VAULT_ADDR/v1/otus/data/cred" | python3 -m json.tool

echo ""
echo "========================================="
echo "Vault initialization completed!"
echo "========================================="
echo ""
echo "Next step: Run ./04-configure-k8s-auth.sh"
echo ""
