# Uptime Kuma with Democratic CSI - Complete Setup Guide

This guide will help you:
1. Set up Democratic CSI securely
2. Install Uptime Kuma as your first CSI-managed app

## Overview

Democratic CSI will:
- Automatically create `/mnt/ssd120/k8s-dynamic/uptime-kuma/uptime-kuma-data` on TrueNAS
- Manage it as a ZFS dataset with compression
- No manual PV creation needed!

## Prerequisites

- [ ] SSH access to TrueNAS (admin@192.168.31.99)
- [ ] kubectl access to K8s cluster
- [ ] Helm installed
- [ ] 15-30 minutes

---

## Step 1: Pre-flight Checks

Run the pre-flight check script:

```bash
cd /home/jac/homelab/k8s-templates/apps/storage/democratic-csi
chmod +x 00-preflight-check.sh
./00-preflight-check.sh
```

**Expected output:** All checks pass (warnings are OK)

If any errors, fix them before continuing.

---

## Step 2: Prepare TrueNAS

### 2.1 Create Isolated Dataset

SSH to TrueNAS and create the parent dataset:

```bash
# SSH to TrueNAS
ssh -i ~/.ssh/coreos admin@192.168.31.99

# Create dataset with compression
zfs create -o compression=lz4 ssd120/k8s-dynamic

# Set a quota (optional but recommended)
zfs set quota=500G ssd120/k8s-dynamic

# Verify
zfs list ssd120/k8s-dynamic

# Expected output:
# NAME                 USED  AVAIL     REFER  MOUNTPOINT
# ssd120/k8s-dynamic    96K   500G       96K  /mnt/ssd120/k8s-dynamic

# Exit TrueNAS
exit
```

### 2.2 Create API Key

**In TrueNAS Web UI (https://192.168.31.99):**

1. Login as admin
2. Go to: **System Settings** → **API Keys**
3. Click **Add**
4. Fill in:
   - **Name**: `k8s-democratic-csi`
   - **User**: `admin` (for now; can create dedicated user later)
5. Click **Add**
6. **IMPORTANT**: Copy the API key shown (only shown once!)
   - It looks like: `1-abc123def456...`

**Save the API key somewhere safe - you'll need it in Step 4!**

---

## Step 3: Verify TrueNAS Setup

```bash
# Verify dataset exists
ssh -i ~/.ssh/coreos admin@192.168.31.99 "zfs list ssd120/k8s-dynamic"

# Verify NFS is enabled (should show your existing NFS shares)
ssh -i ~/.ssh/coreos admin@192.168.31.99 "showmount -e localhost"
```

---

## Step 4: Install Democratic CSI

### 4.1 Set API Key Environment Variable

```bash
# Replace YOUR_API_KEY with the key you copied from TrueNAS
export TRUENAS_API_KEY='1-abc123def456...'

# Verify it's set
echo $TRUENAS_API_KEY
```

**SECURITY NOTE:** This key is sensitive! Don't commit it to git.

### 4.2 Run Installation Script

```bash
cd /home/jac/homelab/k8s-templates/apps/storage/democratic-csi

# The install script will:
# - Add helm repo
# - Create namespace
# - Install democratic-csi with secure settings
./install.sh
```

**Expected output:**
```
✅ Installation complete!
```

### 4.3 Verify Installation

```bash
# Check pods are running
kubectl get pods -n democratic-csi

# Expected output:
# NAME                                       READY   STATUS    RESTARTS   AGE
# democratic-csi-controller-xxxxx            4/4     Running   0          1m
# democratic-csi-node-xxxxx                  3/3     Running   0          1m
# democratic-csi-node-yyyyy                  3/3     Running   0          1m

# Check storage class was created
kubectl get storageclass truenas-nfs-csi

# Expected output:
# NAME               PROVISIONER              RECLAIMPOLICY   VOLUMEBINDINGMODE   ...
# truenas-nfs-csi    org.democratic-csi.nfs   Retain          Immediate           ...
```

### 4.4 Check Logs (Optional)

```bash
# View controller logs to ensure no errors
kubectl logs -n democratic-csi -l app.kubernetes.io/component=controller --tail=50
```

---

## Step 5: Test with Simple PVC (Recommended)

Before installing Uptime Kuma, test with a simple PVC:

```bash
# Apply test PVC
kubectl apply -f test-pvc.yaml

# Watch it get created
kubectl get pvc test-democratic-csi -w

# Should show: Bound after a few seconds

# Check if dataset was created on TrueNAS
ssh -i ~/.ssh/coreos admin@192.168.31.99 "zfs list -r ssd120/k8s-dynamic"

# Expected output:
# NAME                                        USED  AVAIL     REFER  MOUNTPOINT
# ssd120/k8s-dynamic                          ...   ...       ...    /mnt/ssd120/k8s-dynamic
# ssd120/k8s-dynamic/default/test-democratic-csi  ...   ...    ...    ...

# ✅ Success! Dataset was created automatically!

# Cleanup test
kubectl delete -f test-pvc.yaml
```

---

## Step 6: Install Uptime Kuma

Now install Uptime Kuma using the CSI storage:

```bash
# Create namespace
kubectl create namespace uptime-kuma

# Apply Uptime Kuma deployment
kubectl apply -f /home/jac/homelab/k8s-templates/apps/monitoring/uptime-kuma/
```

**Watch the deployment:**

```bash
# Watch PVC get created
kubectl get pvc -n uptime-kuma -w

# Watch pod start
kubectl get pods -n uptime-kuma -w

# Check events if issues
kubectl get events -n uptime-kuma --sort-by='.lastTimestamp'
```

---

## Step 7: Verify Everything Works

### 7.1 Check PVC Binding

```bash
kubectl get pvc -n uptime-kuma

# Expected output:
# NAME                STATUS   VOLUME                                     CAPACITY   ...
# uptime-kuma-data    Bound    pvc-xxxxx-xxxxx-xxxxx-xxxxx-xxxxx         5Gi        ...
```

### 7.2 Check Dataset on TrueNAS

```bash
ssh -i ~/.ssh/coreos admin@192.168.31.99 "zfs list -r ssd120/k8s-dynamic"

# Should show:
# ssd120/k8s-dynamic/uptime-kuma/uptime-kuma-data
```

### 7.3 Check Pod is Running

```bash
kubectl get pods -n uptime-kuma

# Expected:
# NAME                            READY   STATUS    RESTARTS   AGE
# uptime-kuma-xxxxxxxxxx-xxxxx    1/1     Running   0          2m
```

### 7.4 Check Uptime Kuma Service

```bash
kubectl get svc -n uptime-kuma

# Get the service IP/port
```

### 7.5 Access Uptime Kuma

**Option 1: Port Forward (Quick Access)**
```bash
kubectl port-forward -n uptime-kuma svc/uptime-kuma 3001:3001

# Open browser: http://localhost:3001
# You should see Uptime Kuma setup page!
```

**Option 2: IngressRoute (External Access)**
```bash
# Edit the IngressRoute to use your domain
nano /home/jac/homelab/k8s-templates/apps/monitoring/uptime-kuma/ingress.yaml
# Change: uptime.umhomelab.com to your actual domain

# Uncomment ingress in kustomization.yaml
nano /home/jac/homelab/k8s-templates/apps/monitoring/uptime-kuma/kustomization.yaml

# Apply
kubectl apply -k /home/jac/homelab/k8s-templates/apps/monitoring/uptime-kuma/

# Access via: https://uptime.yourdomain.com
```

---

## Step 8: Security Verification

Run the security verification script:

```bash
cd /home/jac/homelab/k8s-templates/apps/storage/democratic-csi
./verify-security.sh
```

Check that:
- ✅ ReclaimPolicy is Retain
- ✅ CSI controller is running
- ✅ Dataset is isolated to /mnt/ssd120/k8s-dynamic

---

## What Just Happened?

1. ✅ Democratic CSI installed with security hardening
2. ✅ Uptime Kuma deployed
3. ✅ PVC created automatically
4. ✅ **TrueNAS automatically created the ZFS dataset!**
5. ✅ No manual PV creation needed!

**The Magic:**
```
You created PVC → Democratic CSI called TrueNAS API →
Dataset created → NFS share created → PVC bound → Pod started
```

**All automatic!** No manual dataset creation, no manual PV yaml files!

---

## Troubleshooting

### PVC Stuck in Pending

```bash
# Check CSI controller logs
kubectl logs -n democratic-csi -l app.kubernetes.io/component=controller

# Common issues:
# - API key wrong/expired
# - Dataset parent doesn't exist
# - Network issue with TrueNAS
```

### Pod Can't Mount Volume

```bash
# Check node driver logs
kubectl logs -n democratic-csi -l app.kubernetes.io/component=node-driver

# Check NFS share on TrueNAS
ssh -i ~/.ssh/coreos admin@192.168.31.99 "showmount -e localhost | grep k8s-dynamic"
```

### Dataset Not Created on TrueNAS

```bash
# Check API connectivity
kubectl exec -n democratic-csi -l app.kubernetes.io/component=controller -- \
  curl -k https://192.168.31.99/api/v2.0/pool/dataset

# Should return JSON (not error)
```

---

## Next Steps

After Uptime Kuma works:

1. **Monitor for a few days** - ensure stability
2. **Configure backups** - add `/mnt/ssd120/k8s-dynamic` to Kopia
3. **Deploy more apps** - use same pattern
4. **Optional**: Create dedicated TrueNAS user with limited permissions

---

## Rollback (If Needed)

If something goes wrong:

```bash
# Delete Uptime Kuma
kubectl delete namespace uptime-kuma

# Uninstall Democratic CSI
helm uninstall democratic-csi -n democratic-csi
kubectl delete namespace democratic-csi

# Your data remains on TrueNAS in /mnt/ssd120/k8s-dynamic
# You can manually create PVs to access it
```

---

## Summary Checklist

- [ ] Pre-flight checks passed
- [ ] Created ssd120/k8s-dynamic dataset on TrueNAS
- [ ] Created TrueNAS API key
- [ ] Installed Democratic CSI
- [ ] Tested with test-pvc.yaml
- [ ] Deployed Uptime Kuma
- [ ] Verified dataset created automatically
- [ ] Accessed Uptime Kuma UI
- [ ] Ran security verification

🎉 **Success!** You now have automatic NFS provisioning with ZFS datasets!
