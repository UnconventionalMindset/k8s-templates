# Execution Checklist - Democratic CSI + Uptime Kuma

This is your step-by-step execution guide. Follow each step carefully.

## Quick Summary

You will:
1. Run pre-flight checks (5 min)
2. Prepare TrueNAS (10 min)
3. Install Democratic CSI (5 min)
4. Deploy Uptime Kuma (5 min)
5. Verify everything works (5 min)

**Total time: ~30 minutes**

---

## Phase 1: Pre-flight Checks

### Step 1.1: Run Pre-flight Check Script

```bash
cd /home/jac/homelab/k8s-templates/apps/storage/democratic-csi
chmod +x 00-preflight-check.sh
./00-preflight-check.sh
```

**Expected result:** ✅ All checks pass (warnings are OK)

**If errors:** Fix them before continuing.

---

## Phase 2: TrueNAS Preparation

### Step 2.1: Create ZFS Dataset

```bash
# SSH to TrueNAS
ssh -i ~/.ssh/coreos admin@192.168.31.99

# Create dataset
zfs create -o compression=lz4 ssd120/k8s-dynamic

# Set quota (500GB limit)
zfs set quota=500G ssd120/k8s-dynamic

# Verify
zfs list ssd120/k8s-dynamic

# Exit
exit
```

**Expected output:**
```
NAME                 USED  AVAIL     REFER  MOUNTPOINT
ssd120/k8s-dynamic    96K   500G       96K  /mnt/ssd120/k8s-dynamic
```

### Step 2.2: Create API Key

**In TrueNAS Web UI (https://192.168.31.99):**

1. Login
2. Go to: **System Settings** → **API Keys**
3. Click **Add**
4. Name: `k8s-democratic-csi`
5. User: `admin`
6. Click **Add**
7. **COPY THE API KEY** (shown only once!)

**Paste it here for next step:**
```
API_KEY: _____________________________________
```

---

## Phase 3: Install Democratic CSI

### Step 3.1: Set Environment Variable

```bash
# Replace with your actual API key from Step 2.2
export TRUENAS_API_KEY='paste-your-key-here'

# Verify
echo $TRUENAS_API_KEY
# Should show your key
```

### Step 3.2: Make Scripts Executable

```bash
cd /home/jac/homelab/k8s-templates/apps/storage/democratic-csi
chmod +x *.sh
```

### Step 3.3: Run Installation

```bash
./install.sh
```

**Expected output:**
```
✅ Installation complete!
```

### Step 3.4: Verify Democratic CSI

```bash
# Check pods (wait for all Running)
kubectl get pods -n democratic-csi

# Should show:
# democratic-csi-controller-xxxxx   4/4   Running
# democratic-csi-node-xxxxx         3/3   Running (one per K8s node)

# Check storage class
kubectl get storageclass truenas-nfs-csi

# Should show:
# NAME               PROVISIONER              RECLAIMPOLICY
# truenas-nfs-csi    org.democratic-csi.nfs   Retain
```

### Step 3.5: Test with Simple PVC (Optional but Recommended)

```bash
# Create test PVC
kubectl apply -f test-pvc.yaml

# Watch it bind
kubectl get pvc test-democratic-csi -w
# Wait for STATUS: Bound (Ctrl+C when bound)

# Verify dataset created on TrueNAS
ssh -i ~/.ssh/coreos admin@192.168.31.99 "zfs list -r ssd120/k8s-dynamic"

# Should show:
# ssd120/k8s-dynamic/default/test-democratic-csi

# ✅ Success! Automatic dataset creation works!

# Cleanup test
kubectl delete -f test-pvc.yaml
```

---

## Phase 4: Deploy Uptime Kuma

### Step 4.1: Review Uptime Kuma Files

```bash
# See what will be created
ls /home/jac/homelab/k8s-templates/apps/monitoring/uptime-kuma/

# Files:
# - namespace.yaml      (namespace)
# - pvc.yaml           (PVC using democratic CSI)
# - deployment.yaml    (Uptime Kuma app)
# - service.yaml       (ClusterIP service)
# - kustomization.yaml (kustomize config)
```

### Step 4.2: Deploy Uptime Kuma

```bash
# Apply all resources
kubectl apply -k /home/jac/homelab/k8s-templates/apps/monitoring/uptime-kuma/
```

**Expected output:**
```
namespace/uptime-kuma created
persistentvolumeclaim/uptime-kuma-data created
deployment.apps/uptime-kuma created
service/uptime-kuma created
```

### Step 4.3: Watch Deployment

```bash
# Watch PVC binding
kubectl get pvc -n uptime-kuma -w
# Wait for STATUS: Bound (Ctrl+C when bound)

# Watch pod starting
kubectl get pods -n uptime-kuma -w
# Wait for STATUS: Running (Ctrl+C when running)
```

**This may take 1-2 minutes for:**
- CSI to create dataset on TrueNAS
- PVC to bind
- Pod to pull image and start

---

## Phase 5: Verification

### Step 5.1: Check All Resources

```bash
# Check PVC
kubectl get pvc -n uptime-kuma

# Expected:
# NAME                STATUS   VOLUME        CAPACITY   STORAGECLASS
# uptime-kuma-data    Bound    pvc-xxxxx...  5Gi        truenas-nfs-csi

# Check Pod
kubectl get pods -n uptime-kuma

# Expected:
# NAME                          READY   STATUS    RESTARTS   AGE
# uptime-kuma-xxxxxxxxxx-xxxxx  1/1     Running   0          2m

# Check Service
kubectl get svc -n uptime-kuma

# Expected:
# NAME          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)
# uptime-kuma   ClusterIP   10.43.xxx.xxx   <none>        3001/TCP
```

### Step 5.2: Verify Dataset on TrueNAS

```bash
ssh -i ~/.ssh/coreos admin@192.168.31.99 "zfs list | grep uptime-kuma"

# Expected:
# ssd120/k8s-dynamic/uptime-kuma/uptime-kuma-data  ...
```

**✅ TrueNAS automatically created the ZFS dataset!**

### Step 5.3: Check Pod Logs

```bash
kubectl logs -n uptime-kuma -l app=uptime-kuma --tail=20

# Should show Uptime Kuma starting up
```

### Step 5.4: Access Uptime Kuma UI

```bash
# Port forward to access locally
kubectl port-forward -n uptime-kuma svc/uptime-kuma 3001:3001
```

**In your browser, open:** http://localhost:3001

**Expected:** Uptime Kuma setup page (create admin account)

**✅ Success!** Uptime Kuma is running with automatic storage!

### Step 5.5: Run Security Verification

```bash
cd /home/jac/homelab/k8s-templates/apps/storage/democratic-csi
./verify-security.sh
```

**Check that:**
- ✅ ReclaimPolicy is Retain
- ✅ Dataset is under /mnt/ssd120/k8s-dynamic
- ✅ CSI pods are running

---

## Phase 6: Final Steps

### Step 6.1: Create Admin Account

In Uptime Kuma UI (http://localhost:3001):
1. Create admin username and password
2. Login
3. Add your first monitor (optional)

### Step 6.2: Configure IngressRoute (Optional)

If you want external access via Traefik:

```bash
# Edit ingress.yaml
nano /home/jac/homelab/k8s-templates/apps/monitoring/uptime-kuma/ingress.yaml

# Change:
# - Host(`uptime.umhomelab.com`)  → your actual domain
# - Uncomment authentik middleware if you want SSO

# Uncomment ingress in kustomization.yaml
nano /home/jac/homelab/k8s-templates/apps/monitoring/uptime-kuma/kustomization.yaml

# Apply
kubectl apply -k /home/jac/homelab/k8s-templates/apps/monitoring/uptime-kuma/

# Access via: https://uptime.yourdomain.com
```

### Step 6.3: Add to Backup

```bash
# Ensure /mnt/ssd120/k8s-dynamic is included in your Kopia backups
# This directory now contains all CSI-managed volumes
```

---

## Success Criteria

Check all these:

- [ ] Democratic CSI pods running (2-3 pods)
- [ ] Storage class `truenas-nfs-csi` exists
- [ ] Uptime Kuma PVC is Bound
- [ ] Uptime Kuma pod is Running
- [ ] Dataset `/mnt/ssd120/k8s-dynamic/uptime-kuma/uptime-kuma-data` exists on TrueNAS
- [ ] Can access Uptime Kuma UI on http://localhost:3001
- [ ] Security verification passed

If all checked: **🎉 Complete success!**

---

## What You Accomplished

1. ✅ Installed Democratic CSI with secure configuration
2. ✅ Deployed Uptime Kuma
3. ✅ **Automatic ZFS dataset creation** - no manual PV needed!
4. ✅ Automatic NFS share configuration
5. ✅ Automatic PVC binding

**The Magic:**
```
kubectl apply -f pvc.yaml
          ↓
Democratic CSI sees PVC
          ↓
Calls TrueNAS API
          ↓
Creates ZFS dataset with compression
          ↓
Creates NFS share
          ↓
Creates PersistentVolume in K8s
          ↓
Binds PVC to PV
          ↓
Pod mounts and runs!
```

**All automatic! No manual work needed!**

---

## Next Apps

For your next app, you can now just:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-data
  namespace: my-app
spec:
  storageClassName: truenas-nfs-csi  # That's it!
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
```

Dataset will be created automatically!

---

## Troubleshooting

If something failed, see:
- `UPTIME-KUMA-SETUP.md` - Detailed troubleshooting
- CSI logs: `kubectl logs -n democratic-csi -l app.kubernetes.io/component=controller`
- Pod logs: `kubectl logs -n uptime-kuma -l app=uptime-kuma`

---

## Rollback (If Needed)

```bash
# Delete Uptime Kuma
kubectl delete -k /home/jac/homelab/k8s-templates/apps/monitoring/uptime-kuma/

# Uninstall Democratic CSI
helm uninstall democratic-csi -n democratic-csi
kubectl delete namespace democratic-csi

# Data remains on TrueNAS
# You can manually create PVs if needed
```

---

**Good luck! 🚀**
