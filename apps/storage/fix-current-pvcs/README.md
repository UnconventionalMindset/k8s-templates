# Fix Current PVC Binding Issues

This is the **safest, quickest fix** for your issue #1 without installing new software.

## The Problem

Your PVCs sometimes bind to the wrong PV because:

```bash
jellyfin-cache-nfs PV     → jellyfin-metadata-nfs PVC ❌ WRONG!
jellyfin-metadata-nfs PV  → jellyfin-cache-nfs PVC     ❌ WRONG!
```

This happens because all PVs have:
- Same `storageClassName: nfs`
- No labels to distinguish them
- PVCs have no selectors

Kubernetes picks ANY matching PV!

## The Fix: Labels + Selectors

Add unique labels to PVs and selectors to PVCs.

### Example: Current vs Fixed

**Before (Wrong bindings possible):**
```yaml
# PV - No labels
apiVersion: v1
kind: PersistentVolume
metadata:
  name: jellyfin-cache-nfs
spec:
  storageClassName: nfs
  capacity:
    storage: 1070Gi
  nfs:
    server: 192.168.31.99
    path: "/mnt/ssd120/cache/jellyfin"

---
# PVC - No selector
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jellyfin-cache-nfs
  namespace: jellyfin
spec:
  storageClassName: nfs
  resources:
    requests:
      storage: 100Mi
```

**After (Correct binding guaranteed):**
```yaml
# PV - With labels
apiVersion: v1
kind: PersistentVolume
metadata:
  name: jellyfin-cache-nfs
  labels:
    app: jellyfin
    type: cache
    storage: nfs
spec:
  storageClassName: nfs
  capacity:
    storage: 1070Gi
  nfs:
    server: 192.168.31.99
    path: "/mnt/ssd120/cache/jellyfin"

---
# PVC - With selector
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jellyfin-cache-nfs
  namespace: jellyfin
spec:
  storageClassName: nfs
  selector:
    matchLabels:
      app: jellyfin
      type: cache
  resources:
    requests:
      storage: 100Mi
```

Now jellyfin-cache PVC will ONLY bind to the PV with matching labels!

## Quick Fix Script

```bash
# This adds labels to existing PVs without disrupting running pods
cd /home/jac/homelab/k8s-templates/apps/storage/fix-current-pvcs
./add-labels.sh
```

## Manual Fix Steps

### 1. Add Labels to Existing PVs

```bash
# Example: Label Home Assistant PV
kubectl label pv hass-nfs \
  app=hass \
  type=config \
  storage=nfs

# Example: Label Jellyfin PVs (fix the swap!)
kubectl label pv jellyfin-cache-nfs \
  app=jellyfin \
  type=cache \
  storage=nfs

kubectl label pv jellyfin-metadata-nfs \
  app=jellyfin \
  type=metadata \
  storage=nfs
```

### 2. Update PVC Files

Add selectors to all your PVC files. Example:

```bash
# Edit apps/smart/hass/config-volume.yaml
# Add selector section to PVC:
spec:
  selector:
    matchLabels:
      app: hass
      type: config
  accessModes:
    - ReadWriteMany
  ...
```

### 3. For Already-Bound PVCs

If a PVC is already bound (even to wrong PV), you need to:

**Option A: Non-disruptive (Recommended)**
- Add labels now
- Update PVC files with selectors
- Next time you recreate the PVC, it will bind correctly

**Option B: Fix immediately (Requires downtime)**
```bash
# 1. Scale down the app
kubectl scale deployment jellyfin -n jellyfin --replicas=0

# 2. Delete the PVC (data stays on NFS)
kubectl delete pvc jellyfin-cache-nfs -n jellyfin

# 3. Update PVC file with selector

# 4. Recreate PVC
kubectl apply -f apps/media/jellyfin/cache-volume.yaml

# 5. Verify correct binding
kubectl get pvc jellyfin-cache-nfs -n jellyfin
# Should show correct PV

# 6. Scale back up
kubectl scale deployment jellyfin -n jellyfin --replicas=1
```

## Label Convention

Use this consistent labeling scheme:

```yaml
labels:
  app: <app-name>          # e.g., jellyfin, hass, immich
  type: <purpose>          # e.g., config, data, cache, uploads
  storage: nfs             # All NFS PVs
  managed-by: manual       # vs. csi for future distinction
```

Examples:
- `app=hass, type=config, storage=nfs`
- `app=immich, type=uploads, storage=nfs`
- `app=jellyfin, type=cache, storage=nfs`
- `app=jellyfin, type=metadata, storage=nfs`

## Testing

After adding labels:

```bash
# Check which PVs have labels
kubectl get pv --show-labels

# Verify a PVC would bind correctly (dry-run)
kubectl apply -f apps/smart/hass/config-volume.yaml --dry-run=server

# Check current bindings
kubectl get pv -o custom-columns=\
NAME:.metadata.name,\
CLAIM:.spec.claimRef.name,\
LABELS:.metadata.labels
```

## Updating All Your Files

You have 47 PV files. Use this script to add selectors:

```bash
./update-all-pvcs.sh
```

Or manually update following this pattern.

## Prevention

Going forward, always create PV+PVC pairs with:
1. **Unique labels on PV**
2. **Matching selector on PVC**
3. **Or use `volumeName` field** (explicit binding)

### Template for New Apps

```yaml
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: myapp-data-nfs
  labels:
    app: myapp
    type: data
    storage: nfs
spec:
  capacity:
    storage: 1070Gi
  accessModes:
    - ReadWriteMany
  storageClassName: nfs
  mountOptions:
    - hard
    - nfsvers=4.2
    - rsize=8192
    - wsize=8192
  nfs:
    server: 192.168.31.99
    path: "/mnt/ssd120/apps/myapp"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: myapp-data-nfs
  namespace: myapp
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs
  selector:
    matchLabels:
      app: myapp
      type: data
  resources:
    requests:
      storage: 100Mi
```

## Comparison: Fix Methods

| Method | Pros | Cons |
|--------|------|------|
| Labels + Selectors | Safe, no new software | Manual updates needed |
| volumeName field | Simple, explicit | Still manual PV creation |
| Democratic CSI | Fully automated | Requires API access |
| NFS Subdir Provisioner | Simple automation | No ZFS dataset features |

## Summary

This fix:
- ✅ Solves issue #1 (wrong bindings)
- ✅ No new software needed
- ✅ No risk to existing data
- ✅ Works with your current setup
- ❌ Doesn't solve issue #2 (manual provisioning)

For issue #2, consider Democratic CSI or NFS provisioner.
