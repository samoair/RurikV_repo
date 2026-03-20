#!/usr/bin/env bash
# ─── Install Flannel CNI on master ─────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/yc_key}"

MASTER_IP=$(terraform -chdir="$TF_DIR" output -raw master_public_ip)

echo "Installing Flannel CNI..."
ssh -i "$SSH_KEY" ubuntu@"$MASTER_IP" <<'REMOTE'
set -euo pipefail

kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Wait for Flannel pods to become ready
echo "Waiting for Flannel pods..."
kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=120s

echo ""
echo "=== Cluster nodes ==="
kubectl get nodes -o wide
REMOTE
