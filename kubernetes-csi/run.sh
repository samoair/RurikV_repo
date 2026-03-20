#!/usr/bin/env bash
set -euo pipefail

BUCKET_NAME="k8s-csi-s3-bucket"
SA_NAME="k8s-csi-sa"
SECRET_FILE="deploy/secret.yaml"

echo "=== 1. Create S3 bucket ==="
yc storage bucket create \
  --name "$BUCKET_NAME" \
  --default-storage-class standard || echo "Bucket may already exist, continuing..."

echo -e "\n=== 2. Create ServiceAccount and generate access keys ==="
FOLDER_ID=$(yc config get folder-id)

yc iam service-account create \
  --name "$SA_NAME" \
  --folder-id "$FOLDER_ID" || echo "SA may already exist, continuing..."

SA_ID=$(yc iam service-account get "$SA_NAME" --format json | jq -r .id)

yc resource-manager folder add-access-binding "$FOLDER_ID" \
  --subject "serviceAccount:$SA_ID" \
  --role storage.editor || echo "Role may already be assigned, continuing..."

KEYS=$(yc iam access-key create --service-account-name "$SA_NAME" --format json)
ACCESS_KEY=$(echo "$KEYS" | jq -r .access_key.key_id)
SECRET_KEY=$(echo "$KEYS" | jq -r .secret)

echo "Access Key ID: $ACCESS_KEY"

echo -e "\n=== 3. Patch secret.yaml with credentials ==="
sed -i.bak \
  -e "s|<YOUR_ACCESS_KEY_ID>|$ACCESS_KEY|" \
  -e "s|<YOUR_SECRET_ACCESS_KEY>|$SECRET_KEY|" \
  "$SECRET_FILE"
rm -f "${SECRET_FILE}.bak"
echo "Secret updated."

echo -e "\n=== 4. Install CSI driver via Helm ==="
helm repo add yandex-s3 https://yandex-cloud.github.io/k8s-csi-s3/charts 2>/dev/null || true
helm repo update

helm upgrade --install csi-s3 yandex-s3/csi-s3 \
  --namespace kube-system \
  --create-namespace \
  --set secret.accessKey="$ACCESS_KEY" \
  --set secret.secretKey="$SECRET_KEY" \
  --set secret.endpoint=https://storage.yandexcloud.net \
  --set storageClass.name=yc-s3-csi \
  --set storageClass.singleBucket="$BUCKET_NAME"

echo -e "\n=== 5. Apply Kubernetes manifests ==="
kubectl apply -f deploy/

echo -e "\n=== Done. Run ./verify/verify.sh to check ==="
