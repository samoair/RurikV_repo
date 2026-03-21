# Kubernetes HA Cluster with Kubespray

## Objective

Deploy a highly available Kubernetes cluster with 3 control-plane nodes and 2 worker nodes using Kubespray on Yandex Cloud.

## Infrastructure

| Role            | Count | vCPU | RAM   | OS           |
|-----------------|-------|------|-------|--------------|
| Control Plane   | 3     | 2    | 8 GB  | Ubuntu 22.04 |
| Worker          | 2     | 2    | 8 GB  | Ubuntu 22.04 |

## Architecture

```
                  ┌──────────────────────────────────┐
                  │   nginx load balancer (per node) │
                  │        localhost:6443            │
                  └──────────┬───────────────────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
         ┌────┴────┐    ┌────┴────┐    ┌────┴────┐
         │ master1 │    │ master2 │    │ master3 │
         │ etcd1   │    │ etcd2   │    │ etcd3   │
         │ API     │    │ API     │    │ API     │
         └─────────┘    └─────────┘    └─────────┘
              │              │              │
              └──────────────┼──────────────┘
                             │
                    ┌────────┴────────┐
                    │                 │
               ┌────┴────┐       ┌────┴────┐
               │ worker1 │       │ worker2 │
               └─────────┘       └─────────┘
```

Stacked etcd topology: each master runs API server, scheduler, controller-manager, and etcd.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.0
- [Yandex Cloud CLI](https://cloud.yandex.ru/docs/cli/quickstart) — authenticated (`yc init`)
- Python 3.12 (`brew install python@3.12`) — Ansible requires 3.10-3.12
- SSH key at `~/.ssh/yc_key`

## Quick Start

### 1. Provision VMs

```bash
cd kubespray
./scripts/01-provision.sh
```

### 2. Generate Kubespray Inventory

```bash
./scripts/02-generate-inventory.sh
```

This generates `inventory/inventory.ini` with IPs from Terraform outputs. Optionally add master public IPs to `supplementary_addresses_in_ssl_keys` in `inventory/group_vars/k8s_cluster/k8s-cluster.yml` for external API access.

### 3. Deploy Cluster

```bash
./scripts/03-deploy-cluster.sh
```

This will:
1. Clone Kubespray (if not already present at `~/kubespray`)
2. Install Ansible dependencies (`pip install -r requirements.txt`)
3. Copy inventory and group_vars
4. Run `ansible-playbook -i inventory/ha-cluster/inventory.ini cluster.yml`

### 4. Verify

After deployment, kubeconfig is saved locally. To check:

```bash
export KUBECONFIG=~/kubespray/inventory/ha-cluster/artifacts/admin.conf
kubectl get nodes -o wide
```
The kubeconfig points to the internal IP 192.168.20.15 which is unreachable from your local machine. You need an SSH
 tunnel.
 
 find the master public IP:

 terraform -chdir=terraform output -json master_public_ips | jq -r '.[0]'

 #### Forward localhost:6443 to master1 via SSH tunnel
 ssh -i ~/.ssh/yc_key -L 6443:192.168.20.15:6443 -fN ubuntu@<MASTER1_PUBLIC_IP>

 sed -i '' 's|server: https://192.168.20.15:6443|server: https://127.0.0.1:6443|' ~/kubespray/inventory/ha-cluster/artifacts/admin.conf

 #### Now kubectl will work
 kubectl get nodes -o wide

 The internal IP is only reachable from within the YC network. The SSH tunnel makes it accessible locally on
 localhost:6443.

Expected output:

```
NAME      STATUS   ROLES           AGE   VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION   CONTAINER-RUNTIME
master1   Ready    control-plane   10m   v1.34.x   192.168.20.x   <none>        Ubuntu 22.04 LTS     5.15.x           containerd://x.x.x
master2   Ready    control-plane   10m   v1.34.x   192.168.20.x   <none>        Ubuntu 22.04 LTS     5.15.x           containerd://x.x.x
master3   Ready    control-plane   10m   v1.34.x   192.168.20.x   <none>        Ubuntu 22.04 LTS     5.15.x           containerd://x.x.x
worker1   Ready    <none>          10m   v1.34.x   192.168.20.x   <none>        Ubuntu 22.04 LTS     5.15.x           containerd://x.x.x
worker2   Ready    <none>          10m   v1.34.x   192.168.20.x   <none>        Ubuntu 22.04 LTS     5.15.x           containerd://x.x.x
```

## Cleanup

```bash
./scripts/destroy.sh
```

## File Structure

```
kubespray/
├── README.md
├── scripts/
│   ├── 01-provision.sh           # Create 5 VMs with Terraform
│   ├── 02-generate-inventory.sh  # Generate Kubespray inventory from TF outputs
│   ├── 03-deploy-cluster.sh      # Run Kubespray Ansible playbook
│   └── destroy.sh                # Destroy all VMs
├── terraform/
│   ├── main.tf                   # 3 masters + 2 workers in YC
│   └── variables.tf              # SSH key path
└── inventory/
    ├── inventory.ini             # Generated (committed as example)
    └── group_vars/
        ├── all/
        │   └── all.yml           # Load balancer settings
        └── k8s_cluster/
            └── k8s-cluster.yml   # CNI, CIDRs, SSL addresses
```
