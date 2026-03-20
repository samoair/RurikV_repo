#!/usr/bin/env bash
# ─── Upgrade Kubernetes cluster from 1.34.x to 1.35.x ──────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"

MASTER_IP=$(terraform -chdir="$TF_DIR" output -raw master_public_ip)
WORKER_IPS=$(terraform -chdir="$TF_DIR" output -raw worker_public_ips)

# ─── Upgrade master ─────────────────────────────────────────────────────────
echo "=== Upgrading master node ==="

ssh ubuntu@"$MASTER_IP" <<'REMOTE'
set -euo pipefail

echo "Current version:"
kubectl version --short

echo "Checking upgrade plan..."
sudo kubeadm upgrade plan

echo "Applying upgrade to v1.35..."
sudo kubeadm upgrade apply v1.35.x -y

echo "Upgrading kubelet and kubectl..."
sudo apt-get update
sudo apt-get install -y --allow-change-held-packages kubelet=1.35.* kubectl=1.35.*
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet

echo "Master upgraded."
REMOTE

# ─── Upgrade workers one by one ────────────────────────────────────────────
for WORKER_IP in $WORKER_IPS; do
  WORKER_NAME=$(ssh ubuntu@"$MASTER_IP" "kubectl get nodes -o wide | grep $WORKER_IP | awk '{print \$1}'" || true)
  if [ -z "$WORKER_NAME" ]; then
    # Fallback: derive name from internal IP mapping
    WORKER_NAME=$(ssh ubuntu@"$WORKER_IP" "hostname")
  fi

  echo "=== Upgrading worker $WORKER_NAME ($WORKER_IP) ==="

  # Cordon and drain from master
  echo "Cordoning and draining $WORKER_NAME..."
  ssh ubuntu@"$MASTER_IP" "kubectl cordon $WORKER_NAME && kubectl drain $WORKER_NAME --ignore-daemonsets --delete-emptydir-data"

  # Upgrade on the worker
  echo "Running kubeadm upgrade on $WORKER_NAME..."
  ssh ubuntu@"$WORKER_IP" <<'REMOTE_WORKER'
set -euo pipefail

sudo apt-get update
sudo apt-get install -y --allow-change-held-packages kubeadm=1.35.*
sudo kubeadm upgrade node
sudo apt-get install -y --allow-change-held-packages kubelet=1.35.*
sudo apt-mark hold kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet
REMOTE_WORKER

  # Uncordon from master
  echo "Uncordoning $WORKER_NAME..."
  ssh ubuntu@"$MASTER_IP" "kubectl uncordon $WORKER_NAME"

  echo "$WORKER_NAME upgraded."
done

echo ""
echo "=== Cluster status after upgrade ==="
ssh ubuntu@"$MASTER_IP" "kubectl get nodes -o wide"
