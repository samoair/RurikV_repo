#!/usr/bin/env bash
# ─── Provision 5 VMs (3 master + 2 worker) with Terraform ──────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"

cd "$TF_DIR"

terraform init
terraform plan -out=tfplan
terraform apply tfplan

echo ""
echo "=== VMs provisioned ==="
echo "Master public IPs:  $(terraform output -json master_public_ips  | jq -r '.[]' | tr '\n' ' ')"
echo "Master internal IPs: $(terraform output -json master_internal_ips | jq -r '.[]' | tr '\n' ' ')"
echo "Worker public IPs:  $(terraform output -json worker_public_ips  | jq -r '.[]' | tr '\n' ' ')"
echo "Worker internal IPs: $(terraform output -json worker_internal_ips | jq -r '.[]' | tr '\n' ' ')"
