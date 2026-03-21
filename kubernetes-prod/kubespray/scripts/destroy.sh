#!/usr/bin/env bash
# ─── Destroy all VMs ────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"

cd "$TF_DIR"
terraform init
terraform destroy -auto-approve
