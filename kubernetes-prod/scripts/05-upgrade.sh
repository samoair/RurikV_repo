#!/usr/bin/env bash
# ─── Upgrade Kubernetes cluster from 1.34.x to 1.35.x ──────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/yc_key}"

MASTER_IP=$(terraform -chdir="$TF_DIR" output -raw master_public_ip)
WORKER_IPS=$(terraform -chdir="$TF_DIR" output -json worker_public_ips | jq -r '.[]')

# ─── Upgrade master ─────────────────────────────────────────────────────────
echo "=== Upgrading master node ==="

ssh -i "$SSH_KEY" ubuntu@"$MASTER_IP" <<'REMOTE'
set -euo pipefail

echo "Current version:"
kubectl version --client

# Switch apt repo to 1.35 and upgrade kubeadm first
echo "Switching to Kubernetes 1.35 repo..."
sudo sed -i 's|stable:/v1.34|stable:/v1.35|g' /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y --allow-change-held-packages kubeadm=1.35.*

echo "Checking upgrade plan..."
sudo kubeadm upgrade plan

echo "Applying upgrade to v1.35..."
TARGET_VERSION=$(sudo kubeadm upgrade plan 2>&1 | grep -oP 'v1\.35\.\d+' | head -1)
sudo kubeadm upgrade apply "$TARGET_VERSION" -y

echo "Upgrading kubelet and kubectl..."
sudo apt-get install -y --allow-change-held-packages kubelet=1.35.* kubectl=1.35.*
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Update kubeconfig (certificates were rotated during upgrade)
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

echo "Master upgraded."
REMOTE

# ─── Upgrade workers one by one ────────────────────────────────────────────
for WORKER_IP in $WORKER_IPS; do
  WORKER_NAME=$(ssh -i "$SSH_KEY" ubuntu@"$MASTER_IP" "kubectl get nodes -o wide | grep $WORKER_IP | awk '{print \$1}'" || true)
  if [ -z "$WORKER_NAME" ]; then
    WORKER_NAME=$(ssh -i "$SSH_KEY" ubuntu@"$WORKER_IP" "hostname")
  fi

  echo "=== Upgrading worker $WORKER_NAME ($WORKER_IP) ==="

  # Cordon and drain from master
  echo "Cordoning and draining $WORKER_NAME..."
  ssh -i "$SSH_KEY" ubuntu@"$MASTER_IP" "kubectl cordon $WORKER_NAME && kubectl drain $WORKER_NAME --ignore-daemonsets --delete-emptydir-data"

  # Upgrade on the worker
  echo "Running kubeadm upgrade on $WORKER_NAME..."
  ssh -i "$SSH_KEY" ubuntu@"$WORKER_IP" <<'REMOTE_WORKER'
set -euo pipefail

# Kill unattended-upgrades if holding dpkg lock
sudo systemctl stop unattended-upgrades 2>/dev/null || true
sudo killall apt-get dpkg unattended-upgr 2>/dev/null || true
sleep 2
sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock
sudo dpkg --configure -a

sudo sed -i 's|stable:/v1.34|stable:/v1.35|g' /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y --allow-change-held-packages kubeadm=1.35.*
sudo kubeadm upgrade node
sudo apt-get install -y --allow-change-held-packages kubelet=1.35.*
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
REMOTE_WORKER

  # Uncordon from master
  echo "Uncordoning $WORKER_NAME..."
  ssh -i "$SSH_KEY" ubuntu@"$MASTER_IP" "kubectl uncordon $WORKER_NAME"

  echo "$WORKER_NAME upgraded."
done

echo ""
echo "=== Cluster status after upgrade ==="
ssh -i "$SSH_KEY" ubuntu@"$MASTER_IP" "kubectl get nodes -o wide"
