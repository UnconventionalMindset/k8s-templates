# Democratic CSI for TrueNAS - Secure Setup

This directory contains a **secure** Democratic CSI configuration that automatically creates ZFS datasets on your TrueNAS.

## What This Solves

### Your Current Problems:
1. ❌ PVCs sometimes bind to wrong PVs (jellyfin-cache ↔ jellyfin-metadata swapped)
2. ❌ Manual dataset creation every time

### What Democratic CSI Provides:
1. ✅ Automatic ZFS dataset creation via TrueNAS API
2. ✅ Each PVC gets its own unique dataset
3. ✅ No more wrong bindings
4. ✅ ZFS benefits: compression, snapshots, quotas

## Security Features

This setup includes multiple security layers:

- 🔒 **Isolated dataset**: Only manages `/mnt/ssd120/k8s-dynamic`
- 🔒 **Retain policy**: Never auto-deletes data
- 🔒 **IP whitelist**: Only your K8s nodes can access
- 🔒 **Resource limits**: Prevents runaway creation
- 🔒 **Audit logging**: Track all API calls

## Quick Start

### 1. Prepare TrueNAS

```bash
# SSH to TrueNAS
ssh -i ~/.ssh/coreos admin@192.168.31.99

# Create isolated parent dataset
zfs create -o compression=lz4 ssd120/k8s-dynamic
zfs set quota=500G ssd120/k8s-dynamic

# Create API key in TrueNAS UI
# System > API Keys > Add
# Copy the key (shown only once!)
```

### 2. Install Democratic CSI

```bash
cd /home/jac/homelab/k8s-templates/apps/storage/democratic-csi

# Set API key (don't commit this!)
export TRUENAS_API_KEY='your-api-key-here'

# Install
./install.sh
```

### 3. Test It

```bash
# Create test PVC
kubectl apply -f test-pvc.yaml

# Watch it get created
kubectl get pvc test-democratic-csi -w

# Verify dataset on TrueNAS
ssh -i ~/.ssh/coreos admin@192.168.31.99 "zfs list ssd120/k8s-dynamic"

# Should show: ssd120/k8s-dynamic/default/test-democratic-csi

# Cleanup
kubectl delete -f test-pvc.yaml
```

## Usage Examples

### Simple PVC (Automatic Dataset)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: myapp-data
  namespace: myapp
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: truenas-nfs-csi  # That's it!
  resources:
    requests:
      storage: 10Gi
```

This automatically creates: `/mnt/ssd120/k8s-dynamic/myapp/myapp-data`

### With Snapshots (Optional)

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: myapp-snapshot
  namespace: myapp
spec:
  volumeSnapshotClassName: truenas-nfs-snap
  source:
    persistentVolumeClaimName: myapp-data
```

## Migration Strategy

You have 3 options:

### Option A: Hybrid (Recommended)
- Keep critical apps on manual datasets (Immich, Jellyfin)
- Use CSI for new/non-critical apps
- Best of both: control + convenience

### Option B: Full Migration
1. Backup data from existing PVs
2. Delete old PVC/PV pairs
3. Create new PVCs with `storageClassName: truenas-nfs-csi`
4. Restore data
5. Benefit: Everything automated going forward

### Option C: Fix Current Setup
- Don't use Democratic CSI at all
- Just add labels/selectors to fix binding issues
- See: `../fix-current-pvcs/README.md`

## Monitoring

```bash
# Check CSI pods
kubectl get pods -n democratic-csi

# View logs
kubectl logs -n democratic-csi -l app.kubernetes.io/name=democratic-csi

# Verify security
./verify-security.sh

# List all CSI-managed volumes
kubectl get pv -l csi.storage.k8s.io/provisioner=org.democratic-csi.nfs
```

## Backups

**CRITICAL**: Democratic CSI does NOT replace backups!

Continue using your existing backup strategy (Kopia). CSI-managed datasets are in:
- `/mnt/ssd120/k8s-dynamic/*`

Make sure Kopia includes this path.

## Troubleshooting

### PVC stuck in Pending
```bash
# Check CSI controller logs
kubectl logs -n democratic-csi -l app.kubernetes.io/component=controller

# Common issues:
# - API key wrong/expired
# - Dataset parent doesn't exist
# - Network issue with TrueNAS
```

### Dataset not created on TrueNAS
```bash
# Verify API connectivity
kubectl exec -n democratic-csi -l app.kubernetes.io/component=controller \
  -- curl -k https://192.168.31.99/api/v2.0/pool/dataset
```

### Wrong permissions
```bash
# Check NFS share settings on TrueNAS
ssh -i ~/.ssh/coreos admin@192.168.31.99 \
  "zfs get -r sharenfs ssd120/k8s-dynamic"
```

## Security Audit

Before going to production, review:

1. ✅ API key stored securely (not in git)
2. ✅ Only K8s nodes can access NFS (check TrueNAS logs)
3. ✅ ReclaimPolicy is Retain
4. ✅ Resource quotas set
5. ✅ Regular backups configured
6. ✅ Audit logs reviewed periodically

Run: `./verify-security.sh`

## Emergency Procedures

### Revoke CSI Access
```bash
# On TrueNAS: Delete API key
# System > API Keys > Delete

# CSI stops working but existing mounts stay active
```

### Complete Removal
```bash
# Uninstall CSI
helm uninstall democratic-csi -n democratic-csi

# Your data remains on TrueNAS in:
# /mnt/ssd120/k8s-dynamic/*

# Manually create PVs if needed to re-attach
```

## Comparison: CSI vs Manual

| Feature | Democratic CSI | Manual PV |
|---------|----------------|-----------|
| Dataset creation | Automatic | Manual |
| Wrong bindings | Never | Possible |
| ZFS snapshots | Built-in | Manual |
| Setup time | 5 min | 15 min/app |
| Control | Medium | Full |
| Risk | Low (with security) | Very Low |
| Best for | New apps, testing | Critical production |

## Next Steps

After installing:

1. Test with test-pvc.yaml
2. Run verify-security.sh
3. Create one non-critical app PVC
4. Monitor for 1 week
5. Gradually migrate more apps if comfortable

**Questions?** Check `security-setup.md` for detailed security analysis.
