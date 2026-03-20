#!/usr/bin/env bash
set -euo pipefail

echo "=== 1. CSI driver pods ==="
kubectl get pods -n kube-system -l 'app in (csi-s3,csi-provisioner-s3)'

echo -e "\n=== 2. StorageClass ==="
kubectl get sc yc-s3-csi

echo -e "\n=== 3. PVC (wait for Bound, timeout 30s) ==="
for i in $(seq 1 30); do
  STATUS=$(kubectl get pvc s3-pvc -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
  echo "  PVC status: $STATUS"
  [ "$STATUS" = "Bound" ] && break
  sleep 1
done

echo -e "\n=== 4. Pod status ==="
kubectl get pod s3-writer

echo -e "\n=== 5. Verify file written to mount ==="
sleep 35
kubectl exec s3-writer -- cat /data/healthcheck.txt

echo -e "\n=== 6. Verify file exists in S3 bucket ==="
# Get bucket name from PV
BUCKET=$(kubectl get pv -o jsonpath='{.items[0].spec.csi.volumeHandle}' | cut -d'/' -f1)
echo "Bucket: $BUCKET"
# Read via S3 API (replace with your actual key or use yc CLI)
yc storage s3 ls "s3://${BUCKET}/" --profile default 2>/dev/null || \
  echo "Tip: verify manually via yc storage s3 ls or YC Console > Object Storage > $BUCKET"

echo -e "\n=== Done ==="
