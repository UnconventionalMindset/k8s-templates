# Storage Solution Decision Guide

You asked about fixing two problems:
1. PVCs sometimes attach to wrong PVs
2. Manual provisioning of PV + TrueNAS datasets every time

Here's a comparison of all solutions to help you decide.

## Solutions Comparison

| Solution | Issue #1 (Wrong Bindings) | Issue #2 (Manual Work) | Risk Level | Setup Time |
|----------|---------------------------|------------------------|------------|------------|
| **Fix Current (Labels)** | ✅ Fixed | ❌ Still manual | Very Low | 30 min |
| **NFS Subdir Provisioner** | ✅ Fixed | ✅ Automatic dirs | Low | 15 min |
| **Democratic CSI** | ✅ Fixed | ✅ Full automation | Low-Medium | 30 min |

## Detailed Breakdown

### Option 1: Fix Current Setup (Safest)
📂 Location: `apps/storage/fix-current-pvcs/`

**What it does:**
- Adds labels to existing PVs
- Adds selectors to PVCs
- Guarantees correct binding

**Pros:**
- ✅ Extremely safe (no new software)
- ✅ No API access needed
- ✅ Works with current workflow
- ✅ Zero risk to existing data

**Cons:**
- ❌ Still manual PV creation
- ❌ Still manual dataset creation
- ❌ Doesn't reduce your workload

**Best for:**
- You want the safest fix
- You're comfortable with manual provisioning
- You don't trust automation with storage

**Quick start:**
```bash
cd /home/jac/homelab/k8s-templates/apps/storage/fix-current-pvcs
./add-labels.sh
```

---

### Option 2: NFS Subdir Provisioner (Simple Automation)
📂 Location: `apps/storage/nfs-provisioner/` (not created yet, can create if interested)

**What it does:**
- Automatically creates subdirectories on NFS share
- No manual PV creation needed
- Just create a PVC, directory is made automatically

**Pros:**
- ✅ No manual PV/directory creation
- ✅ No TrueNAS API access needed
- ✅ Simple and reliable
- ✅ Low risk

**Cons:**
- ❌ Creates directories, not ZFS datasets
- ❌ No ZFS features (snapshots, quotas, compression)
- ❌ No backup strategy automation

**Best for:**
- You want automation without API access
- You don't need ZFS dataset features
- You want something simple and proven

---

### Option 3: Democratic CSI (Full Automation)
📂 Location: `apps/storage/democratic-csi/`

**What it does:**
- Automatically creates ZFS datasets via TrueNAS API
- Full ZFS features: compression, snapshots, quotas
- Complete automation

**Pros:**
- ✅ Full automation (no manual work)
- ✅ Real ZFS datasets (not just directories)
- ✅ Built-in snapshot support
- ✅ Per-dataset compression/quotas
- ✅ Can be made secure (see security-setup.md)

**Cons:**
- ❌ Requires TrueNAS API access
- ❌ More complex than other options
- ❌ API credentials in cluster
- ❌ Higher learning curve

**Security mitigations:**
- Isolated dataset: Only manages `/mnt/ssd120/k8s-dynamic`
- Retain policy: Never auto-deletes
- IP whitelist: Only your K8s nodes
- Dedicated API user with minimal permissions

**Best for:**
- You want full automation
- You trust the security setup
- You want ZFS dataset features
- You're willing to monitor it

**Quick start:**
```bash
# 1. Create dataset on TrueNAS
ssh -i ~/.ssh/coreos admin@192.168.31.99
zfs create -o compression=lz4 ssd120/k8s-dynamic

# 2. Create API key in TrueNAS UI
# System > API Keys > Add

# 3. Install
cd /home/jac/homelab/k8s-templates/apps/storage/democratic-csi
export TRUENAS_API_KEY='your-key'
./install.sh
```

---

## My Recommendation

**Start with Option 1 (Fix Current), then optionally add Option 3 (Democratic CSI) for new apps.**

### Phase 1: Immediate Fix (Option 1)
```bash
# Fix wrong bindings right now (15 minutes)
cd apps/storage/fix-current-pvcs
./add-labels.sh
```

This solves your immediate problem with zero risk.

### Phase 2: Test Automation (Option 3) - Optional
```bash
# Set up Democratic CSI for new apps only (30 minutes)
cd apps/storage/democratic-csi
# Follow README.md
```

Benefits:
- Existing apps stay on manual (safe)
- New apps get automation (convenient)
- You can test CSI with non-critical apps first
- Gradually migrate critical apps if comfortable

### Hybrid Approach Example

```yaml
# Critical apps (Immich, Jellyfin, etc.)
# Keep using manual PVs + datasets
storageClassName: nfs  # Your existing setup
# You create dataset manually
# You have full control

# New/test apps
# Use Democratic CSI
storageClassName: truenas-nfs-csi  # Automatic
# Dataset created automatically
# Less work for you
```

---

## Decision Tree

```
Do you trust automation with storage?
│
├─ NO
│  └─ Use Option 1 (Fix Current)
│     ✅ Safest, you stay in control
│
└─ YES
   │
   Do you need ZFS dataset features (snapshots, compression, quotas)?
   │
   ├─ NO
   │  └─ Use Option 2 (NFS Subdir Provisioner)
   │     ✅ Simple, no API access needed
   │
   └─ YES
      └─ Use Option 3 (Democratic CSI)
         ✅ Full automation with ZFS features
         ⚠️  Set up security properly (see security-setup.md)
```

---

## Test Before Committing

Whichever you choose, test first:

### For Option 1:
```bash
# Label a few PVs
kubectl label pv hass-nfs app=hass type=config storage=nfs

# Verify it doesn't break anything
kubectl get pvc -A
```

### For Option 3:
```bash
# Create test PVC
kubectl apply -f apps/storage/democratic-csi/test-pvc.yaml

# Verify dataset created
ssh -i ~/.ssh/coreos admin@192.168.31.99 "zfs list ssd120/k8s-dynamic"

# Delete test
kubectl delete -f apps/storage/democratic-csi/test-pvc.yaml
```

---

## Questions to Ask Yourself

1. **How much do I value automation vs. control?**
   - High control → Option 1
   - High automation → Option 3

2. **How comfortable am I with giving K8s API access to TrueNAS?**
   - Not comfortable → Option 1 or 2
   - Comfortable with security setup → Option 3

3. **Do I need ZFS dataset features?**
   - No → Option 2
   - Yes → Option 3

4. **How much time do I spend provisioning storage?**
   - Not much → Option 1 (keep current)
   - A lot → Option 3 (automate)

5. **What's my risk tolerance?**
   - Low → Option 1
   - Medium → Option 2
   - Medium-High (with security) → Option 3

---

## What I Set Up for You

I created both solutions so you can choose:

1. ✅ `fix-current-pvcs/` - Safe fix for wrong bindings
2. ✅ `democratic-csi/` - Full automation with security

You can:
- Use Option 1 only (safest)
- Use Option 1 now, Option 3 later (gradual)
- Skip straight to Option 3 (if you trust the security)

---

## Summary

**Safest**: Fix current PVCs with labels (Option 1)
**Simplest automation**: NFS Subdir Provisioner (Option 2 - can create if you want)
**Most powerful**: Democratic CSI with security (Option 3)
**Best compromise**: Option 1 now + Option 3 for new apps

What matters most to you?
