#!/usr/bin/env bash
# ─── Deploy HA Kubernetes cluster with Kubespray ───────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INV_DIR="$SCRIPT_DIR/../inventory"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/yc_key}"

# Check kubespray directory
KUBESPRAY_DIR="${KUBESPRAY_DIR:-$HOME/kubespray}"
if [ ! -d "$KUBESPRAY_DIR" ]; then
  echo "Cloning Kubespray..."
  git clone https://github.com/kubernetes-sigs/kubespray.git "$KUBESPRAY_DIR"
  cd "$KUBESPRAY_DIR"
  pip install -r requirements.txt
else
  echo "Using existing Kubespray at $KUBESPRAY_DIR"
fi

# Copy our inventory and group_vars into kubespray
cp "$INV_DIR/inventory.ini" "$KUBESPRAY_DIR/inventory/ha-cluster/inventory.ini"
mkdir -p "$KUBESPRAY_DIR/inventory/ha-cluster/group_vars/all"
mkdir -p "$KUBESPRAY_DIR/inventory/ha-cluster/group_vars/k8s_cluster"

cp "$INV_DIR/group_vars/all/all.yml" "$KUBESPRAY_DIR/inventory/ha-cluster/group_vars/all/all.yml"
cp "$INV_DIR/group_vars/k8s_cluster/k8s-cluster.yml" "$KUBESPRAY_DIR/inventory/ha-cluster/group_vars/k8s_cluster/k8s-cluster.yml"

# Deploy
echo "Deploying HA Kubernetes cluster..."
cd "$KUBESPRAY_DIR"
ansible-playbook -i inventory/ha-cluster/inventory.ini cluster.yml \
  -b -v \
  --private-key="$SSH_KEY"
