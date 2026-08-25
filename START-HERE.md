# Democratic CSI + Uptime Kuma Setup

## 🎯 What's Ready

Everything is prepared for you to install Democratic CSI and deploy Uptime Kuma with automatic storage provisioning.

## 📁 Files Created

### Democratic CSI Setup
```
apps/storage/democratic-csi/
├── 00-preflight-check.sh          ← Run this first!
├── EXECUTION-CHECKLIST.md         ← Your step-by-step guide
├── UPTIME-KUMA-SETUP.md           ← Detailed setup instructions
├── democratic-csi-values.yaml     ← Secure CSI configuration
├── install.sh                      ← Installation script
├── verify-security.sh              ← Security verification
├── test-pvc.yaml                   ← Test PVC for validation
├── security-setup.md               ← Security deep dive
└── README.md                       ← Overview and usage
```

### Uptime Kuma Application
```
apps/monitoring/uptime-kuma/
├── namespace.yaml                  ← Namespace definition
├── pvc.yaml                        ← Uses Democratic CSI!
├── deployment.yaml                 ← Uptime Kuma app
├── service.yaml                    ← ClusterIP service
├── ingress.yaml                    ← Optional external access
├── kustomization.yaml              ← Kustomize config
└── README.md                       ← App documentation
```

### Supporting Documentation
```
apps/storage/
├── DECISION-GUIDE.md               ← Comparison of all solutions
└── fix-current-pvcs/               ← Alternative: fix current setup
    ├── README.md
    ├── add-labels.sh
    └── example-pvc-with-selector.yaml
```

## 🚀 Quick Start (30 minutes)

### Option 1: Follow the Checklist (Recommended)
```bash
# Open and follow step-by-step
cat /home/jac/homelab/k8s-templates/apps/storage/democratic-csi/EXECUTION-CHECKLIST.md
```

### Option 2: TL;DR Version
```bash
# 1. Pre-flight checks
cd /home/jac/homelab/k8s-templates/apps/storage/democratic-csi
./00-preflight-check.sh

# 2. Create TrueNAS dataset
ssh -i ~/.ssh/coreos admin@192.168.31.99
zfs create -o compression=lz4 ssd120/k8s-dynamic
zfs set quota=500G ssd120/k8s-dynamic
exit

# 3. Create API key in TrueNAS UI
# Go to: System Settings → API Keys → Add
# Copy the key!

# 4. Install Democratic CSI
export TRUENAS_API_KEY='your-key-here'
./install.sh

# 5. Deploy Uptime Kuma
kubectl apply -k /home/jac/homelab/k8s-templates/apps/monitoring/uptime-kuma/

# 6. Access Uptime Kuma
kubectl port-forward -n uptime-kuma svc/uptime-kuma 3001:3001
# Open: http://localhost:3001
```

## 📋 Execution Order

**Follow this order exactly:**

1. **Read**: `EXECUTION-CHECKLIST.md` (your main guide)
2. **Run**: `00-preflight-check.sh` (verify environment)
3. **Setup**: TrueNAS (dataset + API key)
4. **Install**: Democratic CSI
5. **Deploy**: Uptime Kuma
6. **Verify**: Everything works
7. **Secure**: Run security verification

## ✅ What Will Happen

1. **Democratic CSI** will connect to TrueNAS via API
2. When you create a PVC, it will **automatically**:
   - Create ZFS dataset: `/mnt/ssd120/k8s-dynamic/uptime-kuma/uptime-kuma-data`
   - Configure NFS share
   - Create PersistentVolume
   - Bind PVC
3. **Uptime Kuma** pod will mount and run
4. **No manual PV creation needed!**

## 🔒 Security Features

- ✅ Isolated to `/mnt/ssd120/k8s-dynamic` (won't touch your existing data)
- ✅ Retain policy (never auto-deletes)
- ✅ IP whitelist (only your K8s nodes)
- ✅ Resource limits
- ✅ Audit logging

## 📖 Documentation

| File | Purpose |
|------|---------|
| `EXECUTION-CHECKLIST.md` | **START HERE** - Step-by-step commands |
| `UPTIME-KUMA-SETUP.md` | Detailed setup with troubleshooting |
| `DECISION-GUIDE.md` | Why Democratic CSI vs alternatives |
| `security-setup.md` | Security analysis and hardening |

## 🎯 Success Criteria

After execution, you should have:

- [ ] Democratic CSI running (check: `kubectl get pods -n democratic-csi`)
- [ ] Storage class created (check: `kubectl get sc truenas-nfs-csi`)
- [ ] Uptime Kuma running (check: `kubectl get pods -n uptime-kuma`)
- [ ] PVC bound (check: `kubectl get pvc -n uptime-kuma`)
- [ ] Dataset on TrueNAS (check: `ssh -i ~/.ssh/coreos admin@192.168.31.99 "zfs list | grep uptime"`)
- [ ] Can access UI at http://localhost:3001

## 🆘 Help

**If something goes wrong:**

1. Check logs:
   ```bash
   # CSI controller logs
   kubectl logs -n democratic-csi -l app.kubernetes.io/component=controller

   # Uptime Kuma logs
   kubectl logs -n uptime-kuma -l app=uptime-kuma
   ```

2. See troubleshooting in `UPTIME-KUMA-SETUP.md`

3. Run security check:
   ```bash
   ./verify-security.sh
   ```

## 🔄 Rollback

If you want to undo everything:

```bash
# Delete Uptime Kuma
kubectl delete -k apps/monitoring/uptime-kuma/

# Uninstall Democratic CSI
helm uninstall democratic-csi -n democratic-csi
kubectl delete namespace democratic-csi

# Your data remains on TrueNAS (Retain policy)
```

## 🎉 After Success

Once Uptime Kuma works, you can deploy more apps the same way:

```yaml
# Any future app - just create a PVC!
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-data
  namespace: my-app
spec:
  storageClassName: truenas-nfs-csi  # Automatic!
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
```

Dataset will be created automatically on TrueNAS!

---

## 🚦 Ready to Execute?

**Open the execution checklist:**
```bash
cat apps/storage/democratic-csi/EXECUTION-CHECKLIST.md
```

**Or jump straight in:**
```bash
cd apps/storage/democratic-csi
./00-preflight-check.sh
```

Good luck! 🚀
