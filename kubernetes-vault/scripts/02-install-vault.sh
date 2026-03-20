#!/bin/bash
# ============================================================================
# Script 2: Install Vault in HA mode with Consul storage
# Includes initialization, unsealing, and KV secret creation
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

# Wait for any previous namespace deletion to complete
echo "Waiting for namespace to be ready..."
for i in $(seq 1 30); do
    if kubectl get namespace vault -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Active"; then
        echo "Namespace is ready."
        break
    fi
    echo "  Waiting... ($i/30)"
    sleep 2
done

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

# Wait for Vault pods to be ready
echo "Waiting for Vault pods..."
kubectl wait --for=condition=Initialized pod -n vault -l app.kubernetes.io/name=vault --timeout=60s 2>/dev/null || true
sleep 5

# Get first Vault pod
VAULT_POD=$(kubectl get pods -n vault -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')
echo "Using Vault pod: $VAULT_POD"

# ============================================================================
# Initialize Vault if needed
# ============================================================================
echo ""
echo "========================================="
echo "Initializing Vault..."
echo "========================================="

# Check initialization status via HTTP API
INIT_RESPONSE=$(kubectl exec -n vault "$VAULT_POD" -- /bin/sh -c \
    "wget -q -O - http://127.0.0.1:8200/v1/sys/init" 2>/dev/null || echo '{}')
INITIALIZED=$(echo "$INIT_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('initialized', False))" 2>/dev/null || echo "False")

if [ "$INITIALIZED" = "True" ]; then
    echo "Vault is already initialized."

    # Check if we have saved init data
    if [ -f vault-init.json ] && [ -s vault-init.json ]; then
        echo "Using existing vault-init.json"
    else
        echo "WARNING: Vault is initialized but vault-init.json not found locally."
        echo "Unseal keys are unknown. Vault may need manual unsealing."
        echo "Cannot proceed with automatic unsealing."
        kubectl get pods -n vault
        exit 1
    fi
else
    echo "Initializing Vault (1 key, threshold 1)..."
    INIT_RESPONSE=$(kubectl exec -n vault "$VAULT_POD" -- /bin/sh -c \
        "wget -q -O - --post-data='{\"secret_shares\":1,\"secret_threshold\":1}' --header='Content-Type: application/json' http://127.0.0.1:8200/v1/sys/init")
    echo "$INIT_RESPONSE" | python3 -m json.tool
    echo "$INIT_RESPONSE" > vault-init.json

    ROOT_TOKEN=$(echo "$INIT_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['root_token'])")
    echo "$ROOT_TOKEN" > vault-root-token.txt
    chmod 600 vault-root-token.txt
    echo ""
    echo "Root token saved to: vault-root-token.txt"
    echo "Init data saved to: vault-init.json"
fi

# ============================================================================
# Unseal Vault
# ============================================================================
echo ""
echo "========================================="
echo "Unsealing Vault..."
echo "========================================="

ROOT_TOKEN=$(cat vault-root-token.txt 2>/dev/null)
UNSEAL_KEY=$(jq -r '.keys_base64[0]' vault-init.json)

# Unseal ALL vault pods for HA (each pod has its own seal)
echo "Unsealing all Vault pods..."
for POD in $(kubectl get pods -n vault -l app.kubernetes.io/name=vault -o jsonpath='{.items[*].metadata.name}'); do
    SEAL_RESPONSE=$(kubectl exec -n vault "$POD" -- /bin/sh -c \
        "wget -q -O - http://127.0.0.1:8200/v1/sys/seal-status" 2>/dev/null || true)
    if echo "$SEAL_RESPONSE" | grep -q '"sealed":false'; then
        echo "  $POD: already unsealed"
    else
        echo -n "  $POD: unsealing..."
        UNSEAL_RESULT=$(kubectl exec -n vault "$POD" -- /bin/sh -c \
            "wget -q -O - --post-data='{\"key\": \"$UNSEAL_KEY\"}' --header='Content-Type: application/json' http://127.0.0.1:8200/v1/sys/unseal" 2>/dev/null || true)
        if echo "$UNSEAL_RESULT" | grep -q '"sealed":false'; then
            echo " done"
        else
            echo " FAILED"
            echo "    $UNSEAL_RESULT"
        fi
    fi
done

# Wait for Vault HA leader election
echo ""
echo "Waiting for Vault leader election..."
for i in $(seq 1 30); do
    HA_STATUS=$(kubectl exec -n vault "$VAULT_POD" -- /bin/sh -c \
        "wget -q -O - http://127.0.0.1:8200/v1/sys/health" 2>/dev/null || true)
    if echo "$HA_STATUS" | grep -q '"initialized":true'; then
        echo "  Vault leader elected and ready."
        break
    fi
    echo -n "  Waiting... ($i/30)"
    sleep 2
done

# ============================================================================
# Configure Vault: KV engine + secret
# ============================================================================
echo ""
echo "========================================="
echo "Configuring Vault secrets..."
echo "========================================="

# Port-forward to Vault
echo "Setting up port-forward..."
kubectl port-forward -n vault "$VAULT_POD" 8200:8200 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

# Cleanup function
cleanup() {
    kill $PF_PID 2>/dev/null || true
}
trap cleanup EXIT

VAULT_ADDR="http://127.0.0.1:8200"
VAULT_HEADER="X-Vault-Token: $ROOT_TOKEN"

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

# Verify
echo ""
echo "Verifying secret:"
curl -s -H "$VAULT_HEADER" "$VAULT_ADDR/v1/otus/data/cred" | python3 -c "
import json, sys
data = json.load(sys.stdin)['data']['data']
print(f\"  username: {data['username']}\")
print(f\"  password: {data['password']}\")
"

# ============================================================================
# Done
# ============================================================================
echo ""
echo "========================================="
echo "Vault installation completed!"
echo "========================================="
echo ""
kubectl get pods -n vault
echo ""
echo "Next step: Run ./04-configure-k8s-auth.sh"
echo ""
