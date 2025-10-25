# Multus CNI Configuration for K3s

This directory contains the Multus CNI configuration for enabling multiple network interfaces in Kubernetes pods.

## Overview

Multus CNI is a meta-plugin that enables attaching multiple network interfaces to pods. This setup uses the **thick plugin mode** which provides better performance and more features than the traditional thin plugin approach.

## Files

- `multus-values.yaml` - Helm chart values for Multus CNI deployment
- `multus-lan.yaml` - NetworkAttachmentDefinition for LAN network connectivity

## Configuration Details

### Key Settings Explained

The `multus-values.yaml` contains only the **essential configuration overrides** needed for K3s:

```yaml
thickPlugin:
  enabled: true

config:
  daemon_conf:
    cniBinDir: /opt/cni/bin
    cniConfigDir: /hostroot/var/lib/rancher/k3s/agent/etc/cni/net.d
    multusAutoconfigDir: /hostroot/var/lib/rancher/k3s/agent/etc/cni/net.d
```

#### Why These Settings Are Required:

1. **`cniBinDir: /opt/cni/bin`**
   - Default in upstream chart: `/var/lib/rancher/k3s/data/cni`
   - **Why changed**: The helm chart mounts `/opt/cni/bin` from the host to the container
   - Without this, Multus cannot find CNI plugins like `flannel`, `bridge`, `portmap`
   - Error message: `failed to find plugin "flannel" in path [/var/lib/rancher/k3s/data/cni]`

2. **`cniConfigDir: /hostroot/var/lib/rancher/k3s/agent/etc/cni/net.d`**
   - Default in upstream chart: `/host/etc/cni/net.d`
   - **Why changed**: K3s containerd looks for CNI configs in `/var/lib/rancher/k3s/agent/etc/cni/net.d/`
   - Multus must write `00-multus.conf` to this directory for containerd to use it
   - The `/hostroot` mount provides access to the entire host filesystem

3. **`multusAutoconfigDir: /hostroot/var/lib/rancher/k3s/agent/etc/cni/net.d`**
   - Must match `cniConfigDir` for proper autoconfiguration
   - Multus uses this to discover the cluster network config (e.g., `10-flannel.conflist`)

### Volume Mounts (Managed by Helm Chart)

The Multus DaemonSet automatically creates these volume mounts:

| Host Path | Container Mount | Purpose |
|-----------|----------------|---------|
| `/opt/cni/bin` | `/opt/cni/bin` | CNI plugin binaries |
| `/var/lib/rancher/k3s/agent/etc/cni/net.d` | (via `/hostroot`) | CNI configuration files |
| `/` | `/hostroot` | Full host filesystem access (chroot) |

## Installation

### Install Multus

```bash
helm upgrade --install multus rke2-charts/rke2-multus \
  -n kube-system \
  --values multus-values.yaml \
  --version 4.2.208
```

### Create Network Attachment Definition

```bash
kubectl apply -f multus-lan.yaml
```

## Usage Example

To attach additional network interfaces to a pod, add the `k8s.v1.cni.cncf.io/networks` annotation:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  annotations:
    k8s.v1.cni.cncf.io/networks: '[
      {
        "name": "lan-network",
        "namespace": "default",
        "mac": "16:3c:13:e1:c9:02",
        "ips": ["192.168.31.233/24"]
      }
    ]'
spec:
  containers:
  - name: my-container
    image: my-image:latest
```

This will create:
- `eth0`: Default cluster network interface
- `net1`: Additional LAN network interface with the specified IP

## Verification

### Check Multus Pods

```bash
kubectl get pods -n kube-system -l app=rke2-multus
```

### Check Pod Network Interfaces

```bash
kubectl exec -n <namespace> <pod-name> -- ip addr show
```

Expected output:
```
1: lo: <LOOPBACK,UP,LOWER_UP> ...
2: eth0@if123: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
    inet 10.42.0.x/24 ...
3: net1@eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
    inet 192.168.31.233/24 ...
```

### Check Network Status Annotation

```bash
kubectl get pod <pod-name> -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' | jq .
```

## Troubleshooting

### Common Issues

1. **Pod stuck in ContainerCreating**
   - Check Multus logs: `kubectl logs -n kube-system <multus-pod> -c kube-multus`
   - Verify CNI binaries exist: `kubectl exec -n kube-system <multus-pod> -c kube-multus -- ls -la /opt/cni/bin/`

2. **Missing flannel/cni binaries**
   - If binaries are missing after Multus pod restart, copy them manually:
     ```bash
     kubectl exec -n kube-system <multus-pod> -c kube-multus -- \
       sh -c "cp /hostroot/var/lib/rancher/k3s/data/cni/cni /opt/cni/bin/cni && \
              cp /hostroot/var/lib/rancher/k3s/data/cni/flannel /opt/cni/bin/flannel"
     ```

3. **Multus not being invoked for new pods**
   - Verify `00-multus.conf` exists in the correct location:
     ```bash
     kubectl exec -n kube-system <multus-pod> -c kube-multus -- \
       ls -la /hostroot/var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf
     ```

## Architecture Notes

### Thick Plugin vs Thin Plugin

This setup uses **thick plugin mode** (`thickPlugin: enabled: true`), which:
- Runs Multus as a daemon on each node
- Uses a shim CNI binary that communicates with the daemon via Unix socket
- Provides better performance and more features
- Supports dynamic network attachment without pod restarts

### How It Works

1. **Pod Creation**: Kubelet creates a pod and calls CNI
2. **CNI Configuration**: Containerd reads `/var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf` (lexically first)
3. **Multus Shim**: The `multus-shim` binary is called and connects to the Multus daemon via `/host/run/multus/multus.sock`
4. **Network Setup**:
   - Multus daemon reads pod annotations
   - Calls the cluster network CNI (flannel) to create `eth0`
   - Calls additional network CNIs (ipvlan, macvlan, etc.) to create `net1`, `net2`, etc.
5. **Result**: Pod has multiple network interfaces as configured

## References

- [Multus CNI Documentation](https://github.com/k8snetworkplumbingwg/multus-cni)
- [Network Attachment Definitions](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/quickstart.md)
- [K3s Networking](https://docs.k3s.io/networking)
