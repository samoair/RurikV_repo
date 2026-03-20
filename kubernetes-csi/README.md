# Kubernetes CSI S3 — Yandex Cloud Object Storage

## Prerequisites

- Yandex Cloud account with Object Storage enabled
- `yc` CLI configured (`yc init`)
- Kubernetes cluster with privileged containers allowed
- `helm` and `jq` installed

## Quick Start

```bash
./run.sh && ./verify/verify.sh
```

`run.sh` automates everything:
1. Creates S3 bucket `k8s-csi-s3-bucket`
2. Creates service account `k8s-csi-sa` with `storage.editor` role
3. Generates access keys and patches `deploy/secret.yaml`
4. Installs CSI driver via Helm
5. Applies all Kubernetes manifests

## What Gets Created

| Resource | Name | Description |
|----------|------|-------------|
| S3 Bucket | `k8s-csi-s3-bucket` | Object storage backend |
| ServiceAccount | `k8s-csi-sa` | IAM identity with `storage.editor` role |
| K8s Secret | `csi-s3-secret` (kube-system) | Static access keys |
| StorageClass | `yc-s3-csi` | GeeseFS mounter, default class |
| PVC | `s3-pvc` | 5Gi RWX, auto-provisioned |
| Pod | `s3-writer` | Writes timestamp to `/data/healthcheck.txt` every 30s |

## Verify

```bash
./verify/verify.sh
```

Expected results:
- CSI driver pods are `Running` in `kube-system`
- PVC transitions to `Bound`
- Pod `s3-writer` is `Running`
- `/data/healthcheck.txt` contains timestamped entries
- File is visible in the S3 bucket via `yc storage s3 ls` or YC Console

## Manual Install

If you prefer step-by-step control instead of `run.sh`:

```bash
# 1. Create bucket
yc storage bucket create --name k8s-csi-s3-bucket --default-storage-class standard

# 2. Create service account + keys
yc iam service-account create --name k8s-csi-sa --folder-id $(yc config get folder-id)
yc resource-manager folder add-access-binding $(yc config get folder-id) \
  --subject serviceAccount:k8s-csi-sa --role storage.editor
yc iam access-key create --service-account-name k8s-csi-sa

# 3. Edit deploy/secret.yaml — insert your key_id and secret

# 4. Install CSI driver
helm repo add yandex-s3 https://yandex-cloud.github.io/k8s-csi-s3/charts
helm repo update
helm install csi-s3 yandex-s3/csi-s3 \
  --namespace kube-system \
  --set secret.accessKey=<KEY_ID> \
  --set secret.secretKey=<SECRET> \
  --set secret.endpoint=https://storage.yandexcloud.net \
  --set storageClass.name=yc-s3-csi \
  --set storageClass.singleBucket=k8s-csi-s3-bucket

# 5. Apply manifests
kubectl apply -f deploy/
```

## Cleanup

```bash
kubectl delete -f deploy/
helm uninstall csi-s3 --namespace kube-system
```
