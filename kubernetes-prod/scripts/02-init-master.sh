#!/usr/bin/env bash
# ─── Initialize the Kubernetes control plane on the master node ──────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/yc_key}"

MASTER_IP=$(terraform -chdir="$TF_DIR" output -raw master_public_ip)

echo "SSH into master ($MASTER_IP) and running kubeadm init..."

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$MASTER_IP" <<'REMOTE'
set -euo pipefail

# Verify containerd is running
systemctl is-active containerd

# Get the internal IP of the master
MASTER_INTERNAL_IP=$(hostname -I | awk '{print $1}')
echo "Master internal IP: $MASTER_INTERNAL_IP"

# Initialize the cluster
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address="$MASTER_INTERNAL_IP"

# Configure kubectl for the current user
mkdir -p "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

# Print join command for workers
echo ""
echo "=== kubeadm join command ==="
kubeadm token create --print-join-command 2>/dev/null || sudo kubeadm token create --print-join-command
REMOTE
