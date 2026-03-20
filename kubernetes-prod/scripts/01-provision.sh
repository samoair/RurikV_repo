#!/usr/bin/env bash
# ─── Provision VMs with Terraform ───────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"

cd "$TF_DIR"

terraform init
terraform plan -out=tfplan
terraform apply tfplan

echo "=== VMs provisioned ==="
echo "Master public IP:  $(terraform output -raw master_public_ip)"
echo "Master internal IP: $(terraform output -raw master_internal_ip)"
echo "Worker public IPs:  $(terraform output -raw worker_public_ips)"
echo ""
echo "Wait ~3 minutes for cloud-init to finish, then run 02-init-master.sh"
