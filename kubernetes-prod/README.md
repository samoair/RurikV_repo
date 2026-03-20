# Kubernetes Production — Cluster Deployment & Upgrade

## Objective

Deploy a bare-metal Kubernetes cluster from scratch on Yandex Cloud VMs using `kubeadm` and perform a rolling upgrade to the latest version.

## Infrastructure

| Role   | Count | vCPU | RAM   | OS             |
|--------|-------|------|-------|----------------|
| Master | 1     | 2    | 8 GB  | Ubuntu 22.04   |
| Worker | 3     | 2    | 8 GB  | Ubuntu 22.04   |

**Kubernetes versions:**
- Initial: **1.34.x** (one minor below latest)
- Upgraded to: **1.35.x**

## How It Works

Terraform provisions 4 VMs with **cloud-init** that automatically performs all node preparation:
- Disables swap
- Enables kernel modules (`overlay`, `br_netfilter`)
- Configures sysctl for networking
- Installs `containerd` with SystemdCgroup
- Installs `kubeadm`, `kubelet`, `kubectl` v1.34.x (pinned)

After provisioning, shell scripts initialize the control plane, join workers, install Flannel, and perform the rolling upgrade.

## Quick Start

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.0
- [Yandex Cloud CLI](https://cloud.yandex.ru/docs/cli/quickstart) installed and authenticated (`yc init`)
- SSH key pair for VM access

### 1. Configure

Edit `terraform/terraform.tfvars` — set your folder ID:

```hcl
yc_folder_id = "<your-folder-id>"
```

### 2. Provision VMs

```bash
cd kubernetes-prod
./scripts/01-provision.sh
```

Wait ~3 minutes for cloud-init to complete on all nodes.

### 3. Initialize the control plane

```bash
./scripts/02-init-master.sh
```

### 4. Join worker nodes

```bash
./scripts/03-join-workers.sh
```

### 5. Install Flannel CNI

```bash
./scripts/04-apply-flannel.sh
```

### 6. Verify

```bash
ssh ubuntu@$(terraform -chdir=terraform output -raw master_public_ip) \
  "kubectl get nodes -o wide"
```

Expected output:

```
NAME     STATUS   ROLES           AGE   VERSION   INTERNAL-IP    OS-IMAGE       KERNEL-VERSION   CONTAINER-RUNTIME
master   Ready    control-plane   10m   v1.34.x   192.168.10.x  Ubuntu 22.04   5.15.x           containerd://1.7.x
worker1  Ready    <none>          5m    v1.34.x   192.168.10.x  Ubuntu 22.04   5.15.x           containerd://1.7.x
worker2  Ready    <none>          5m    v1.34.x   192.168.10.x  Ubuntu 22.04   5.15.x           containerd://1.7.x
worker3  Ready    <none>          5m    v1.34.x   192.168.10.x  Ubuntu 22.04   5.15.x           containerd://1.7.x
```

---

## Cluster Upgrade: 1.34.x → 1.35.x

```bash
./scripts/05-upgrade.sh
```

This script performs a rolling upgrade:
1. Upgrades master (control plane + kubelet)
2. For each worker: cordon → drain → upgrade → uncordon

Expected output after upgrade:

```
NAME     STATUS   ROLES           AGE   VERSION   INTERNAL-IP    OS-IMAGE       KERNEL-VERSION   CONTAINER-RUNTIME
master   Ready    control-plane   30m   v1.35.x   192.168.10.x  Ubuntu 22.04   5.15.x           containerd://1.7.x
worker1  Ready    <none>          25m   v1.35.x   192.168.10.x  Ubuntu 22.04   5.15.x           containerd://1.7.x
worker2  Ready    <none>          25m   v1.35.x   192.168.10.x  Ubuntu 22.04   5.15.x           containerd://1.7.x
worker3  Ready    <none>          25m   v1.35.x   192.168.10.x  Ubuntu 22.04   5.15.x           containerd://1.7.x
```

## Cleanup

```bash
./scripts/destroy.sh
```

## File Structure

```
kubernetes-prod/
├── README.md                           # This file
├── scripts/
│   ├── 01-provision.sh                 # Create VMs with Terraform
│   ├── 02-init-master.sh               # kubeadm init on master
│   ├── 03-join-workers.sh              # kubeadm join on workers
│   ├── 04-apply-flannel.sh             # Install Flannel CNI
│   ├── 05-upgrade.sh                   # Rolling upgrade to 1.35.x
│   └── destroy.sh                      # Destroy all VMs
└── terraform/
    ├── main.tf                         # YC VM definitions (compute_instance)
    ├── variables.tf                    # Input variables
    ├── terraform.tfvars                # Your values (folder ID, etc.)
    ├── cloud-init-master.yaml          # Master node bootstrap
    └── cloud-init-worker.yaml          # Worker node bootstrap
```
