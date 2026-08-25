#!/bin/bash
set -e

echo "=== Secure Democratic CSI Installation ==="
echo ""

# Check if API key is provided
if [ -z "$TRUENAS_API_KEY" ]; then
  echo "ERROR: TRUENAS_API_KEY environment variable not set"
  echo ""
  echo "Please set it first:"
  echo "  export TRUENAS_API_KEY='your-api-key-here'"
  echo ""
  echo "To create an API key:"
  echo "  1. SSH to TrueNAS: ssh -i ~/.ssh/coreos admin@192.168.31.99"
  echo "  2. Go to System > API Keys > Add"
  echo "  3. Create key for user 'k8s-csi' (or admin for testing)"
  exit 1
fi

echo "Step 1: Verify TrueNAS dataset exists..."
echo "Checking for ssd120/k8s-dynamic on TrueNAS..."
ssh -i ~/.ssh/coreos admin@192.168.31.99 "zfs list ssd120/k8s-dynamic" 2>/dev/null || {
  echo ""
  echo "Dataset not found. Creating it..."
  echo "Run on TrueNAS:"
  echo "  zfs create -o compression=lz4 ssd120/k8s-dynamic"
  echo "  zfs set quota=500G ssd120/k8s-dynamic"
  echo ""
  read -p "Press Enter after creating the dataset..."
}

echo ""
echo "Step 2: Add Helm repository..."
helm repo add democratic-csi https://democratic-csi.github.io/charts/
helm repo update

echo ""
echo "Step 3: Create namespace..."
kubectl create namespace democratic-csi --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Step 4: Install Democratic CSI..."
helm upgrade --install democratic-csi \
  democratic-csi/democratic-csi \
  --namespace democratic-csi \
  --values democratic-csi-values.yaml \
  --set-string driver.config.httpConnection.apiKey="$TRUENAS_API_KEY"

echo ""
echo "Step 5: Wait for controller to be ready..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=democratic-csi \
  -n democratic-csi \
  --timeout=120s

echo ""
echo "✅ Installation complete!"
echo ""
echo "Verify installation:"
echo "  kubectl get pods -n democratic-csi"
echo "  kubectl get storageclass truenas-nfs-csi"
echo ""
echo "Test with a PVC:"
echo "  kubectl apply -f test-pvc.yaml"
echo ""
echo "Security reminders:"
echo "  - Datasets are isolated to /mnt/ssd120/k8s-dynamic"
echo "  - ReclaimPolicy is Retain (data won't auto-delete)"
echo "  - Consider setting up Sealed Secrets for the API key"
