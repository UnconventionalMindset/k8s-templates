#!/bin/bash

echo "=== Democratic CSI Security Verification ==="
echo ""

echo "1. Checking storage class configuration..."
RECLAIM=$(kubectl get storageclass truenas-nfs-csi -o jsonpath='{.reclaimPolicy}')
if [ "$RECLAIM" == "Retain" ]; then
  echo "  ✅ ReclaimPolicy: Retain (safe - won't auto-delete)"
else
  echo "  ⚠️  ReclaimPolicy: $RECLAIM (WARNING: may delete data!)"
fi

echo ""
echo "2. Checking CSI controller pods..."
kubectl get pods -n democratic-csi -o wide

echo ""
echo "3. Checking for any PVs created..."
kubectl get pv -l csi.storage.k8s.io/provisioner=org.democratic-csi.nfs

echo ""
echo "4. Verifying TrueNAS dataset structure..."
ssh -i ~/.ssh/coreos admin@192.168.31.99 "zfs list -r ssd120/k8s-dynamic" || {
  echo "  ⚠️  Cannot connect to TrueNAS or dataset doesn't exist"
}

echo ""
echo "5. Checking NFS shares (should only show CSI-managed ones)..."
ssh -i ~/.ssh/coreos admin@192.168.31.99 "zfs get -r sharenfs ssd120/k8s-dynamic | grep -v off || echo 'No NFS shares active'" || true

echo ""
echo "6. Verifying no secrets are exposed..."
kubectl get secret -n democratic-csi -o yaml | grep -i "api" && {
  echo "  ⚠️  API key found in secret (this is expected, but ensure it's not in git)"
} || {
  echo "  ℹ️  API key location varies by installation method"
}

echo ""
echo "Security Checklist:"
echo "  [ ] ReclaimPolicy is Retain"
echo "  [ ] API key is not committed to git"
echo "  [ ] Only K8s nodes (192.168.31.192, 193) can access NFS"
echo "  [ ] Dataset isolated to /mnt/ssd120/k8s-dynamic"
echo "  [ ] Regular backups configured (your existing Kopia)"
echo ""
echo "Manual checks:"
echo "  - Review CSI logs: kubectl logs -n democratic-csi -l app.kubernetes.io/name=democratic-csi"
echo "  - Check TrueNAS audit log for API activity"
echo "  - Verify your manual datasets are untouched"
