# Redis Failure & Node hs Performance Fix
**Date:** 2026-01-11
**Status:** Fix Identified & Partially Applied
**Related Report:** `docs/2026-01-11-node-hs-performance-investigation.md`

## Executive Summary
Investigation into repeating Redis replica crashes revealed a critical infrastructure issue on node `hs` (homeserver). A broken Intel i3-N305 GPU passthrough configuration was causing a **10.8x virtualization overhead** (40% host CPU usage), leading to `kube-router` networking failures and pod health probe timeouts.

## 1. Issue Description

### Symptoms
- **Redis Replicas:** Continuous `CrashLoopBackOff` in `db` namespace.
- **Error Log:** `Unable to connect to MASTER: Resource temporarily unavailable`.
- **Network:** `kube-router` on node `hs` restarting frequently (60+ times), failing to establish BGP peering or apply `iptables`.
- **Host Performance:** Node `hs` showed massive I/O wait times and CPU load despite low guest utilization.

### Root Cause Analysis
1.  **Invalid PCI ROM Header:** The Proxmox host logs (`dmesg`) showed the VM constantly resetting the passed-through GPU (`0000:00:02.0`) because it couldn't read the device BIOS (ROM).
    *   *Error:* `vfio-pci 0000:00:02.0: Invalid PCI ROM header signature: expecting 0xaa55, got 0x0000`
2.  **Virtualization Overhead:** This reset loop caused a "storm" of interrupts, forcing the host CPU to 40% usage just to manage the empty cycles.
3.  **Cascading Failure:** The CPU starvation caused `kube-router` to timeout on critical network operations, breaking pod-to-pod communication (specifically Redis Replica → Master).

## 2. Implemented Fixes (Redis)

I have updated the Helm values file to make Redis more resilient to temporary latency.

**File:** `secrets/redis-values.insecure.yaml`
**Changes:**
- Increased `livenessProbe` timeout from 5s → **15s**.
- Increased `readinessProbe` timeout from 2s → **10s**.
- Increased `failureThreshold` from 5 → **10**.

**Action Required:**
Apply this change to the cluster:
```bash
helm upgrade redis -n db -f secrets/redis-values.insecure.yaml bitnami/redis
```

## 3. Required Infrastructure Fix (Proxmox GPU)

Since the GPU is required for workloads (transcoding), simply removing it is not an option. We must configure the VM to skip the broken BIOS initialization.

### Step-by-Step Fix

**1. SSH into Proxmox Host (homeserver)**
```bash
ssh -i ~/.ssh/coreos root@192.168.31.84
```

**2. Disable ROM-Bar for VM 203**
This prevents the VM from trying to read the corrupt BIOS header, stopping the reset loop.
```bash
qm set 203 -hostpci0 0000:00:02.0,rombar=0
```

**3. Prevent Host Framebuffer Conflict**
Ensure the host doesn't latch onto the GPU during boot.
```bash
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="initcall_blacklist=sysfb_init /' /etc/default/grub
update-grub
```

**4. Reboot Host**
```bash
reboot
```

## 4. Verification

After the host reboots:

1.  **Check Host CPU:** Run `top` on the Proxmox host. The `kvm` process for VM 203 should drop from ~40% to <10%.
2.  **Check dmesg:** `dmesg | grep vfio` should no longer show "Invalid PCI ROM" or reset messages.
3.  **Check Pods:**
    ```bash
    kubectl get pods -n kube-system -l k8s-app=kube-router
    kubectl get pods -n db -l app.kubernetes.io/name=redis
    ```
    All pods should transition to `Running` and `Ready` within 5 minutes.

## 5. Storage Note
The Redis replicas currently share a single NFS subpath (`replica/`). While not the primary cause of *this* crash, it is a risk for data corruption.
*   **Recommendation:** Future improvement should use `volumeClaimTemplates` to give each replica a unique PVC.
