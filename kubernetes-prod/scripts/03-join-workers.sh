#!/usr/bin/env bash
# ─── Join worker nodes to the cluster ───────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"

MASTER_IP=$(terraform -chdir="$TF_DIR" output -raw master_public_ip)
WORKER_IPS=$(terraform -chdir="$TF_DIR" output -raw worker_public_ips)

# Get the join command from master
echo "Fetching join command from master..."
JOIN_CMD=$(ssh ubuntu@"$MASTER_IP" "kubeadm token create --print-join-command")

# Join each worker
for WORKER_IP in $WORKER_IPS; do
  echo "Joining worker at $WORKER_IP..."
  ssh ubuntu@"$WORKER_IP" "sudo $JOIN_CMD"
done

echo ""
echo "=== Cluster status ==="
ssh ubuntu@"$MASTER_IP" "kubectl get nodes -o wide"
