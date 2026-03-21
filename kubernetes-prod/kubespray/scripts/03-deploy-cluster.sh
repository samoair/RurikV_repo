#!/usr/bin/env bash
# ─── Deploy HA Kubernetes cluster with Kubespray ───────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INV_DIR="$SCRIPT_DIR/../inventory"
TF_DIR="$SCRIPT_DIR/../terraform"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/yc_key}"

# ─── Prepare Kubespray source ──────────────────────────────────────────────
KUBESPRAY_DIR="${KUBESPRAY_DIR:-$HOME/kubespray}"
if [ ! -d "$KUBESPRAY_DIR" ]; then
  echo "Cloning Kubespray..."
  git clone --depth 1 https://github.com/kubernetes-sigs/kubespray.git "$KUBESPRAY_DIR"
fi

# Copy our inventory and group_vars into kubespray
K8S_INV="$KUBESPRAY_DIR/inventory/ha-cluster"
mkdir -p "$K8S_INV/group_vars/all" "$K8S_INV/group_vars/k8s_cluster"

cp "$INV_DIR/inventory.ini" "$K8S_INV/inventory.ini"
cp "$INV_DIR/group_vars/all/all.yml" "$K8S_INV/group_vars/all/all.yml"
cp "$INV_DIR/group_vars/k8s_cluster/k8s-cluster.yml" "$K8S_INV/group_vars/k8s_cluster/k8s-cluster.yml"

# Add master public IPs to supplementary_addresses_in_ssl_keys
MASTER_PUB_IPS=$(terraform -chdir="$TF_DIR" output -json master_public_ips | jq -r '.[]')
SSL_ADDRS=""
for ip in $MASTER_PUB_IPS; do
  SSL_ADDRS="${SSL_ADDRS}  - $ip\n"
done
if [ -n "$SSL_ADDRS" ]; then
  echo -e "# Auto-generated from Terraform outputs\nsupplementary_addresses_in_ssl_keys:\n$SSL_ADDRS" >> "$K8S_INV/group_vars/k8s_cluster/k8s-cluster.yml"
fi

echo "Inventory copied to $K8S_INV/"

# ─── Set up Python venv with compatible Python 3.12 ────────────────────────
VENV_DIR="$KUBESPRAY_DIR/venv"
PYTHON3_12="/opt/homebrew/bin/python3.12"

if [ ! -f "$PYTHON3_12" ]; then
  echo "Installing python@3.12 via brew..."
  brew install python@3.12
fi

if [ ! -d "$VENV_DIR" ]; then
  echo "Creating venv with Python 3.12..."
  "$PYTHON3_12" -m venv "$VENV_DIR"
  source "$VENV_DIR/bin/activate"
  pip install -r "$KUBESPRAY_DIR/requirements.txt"
else
  source "$VENV_DIR/bin/activate"
fi

# ─── Deploy ────────────────────────────────────────────────────────────────
echo "Deploying HA Kubernetes cluster..."
cd "$KUBESPRAY_DIR"
ansible-playbook -i inventory/ha-cluster/inventory.ini cluster.yml \
  -b -v \
  --private-key="$SSH_KEY" \
  --ssh-extra-args "-o StrictHostKeyChecking=no"
