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

### Install the CRDs first

The CRDs ship as a separate chart, `rke2-multus-crd` (the `rke2-multus` chart contains none, even though its NOTES mention the CRD). It installs `network-attachment-definitions.k8s.cni.cncf.io` and three `whereabouts.cni.cncf.io` CRDs (only used if the whereabouts IPAM is enabled, which it is not here). Note its version has no `v` prefix, unlike `rke2-multus`.

```bash
helm upgrade --install multus-crd rke2-charts/rke2-multus-crd -n kube-system --version 4.3.118
```

Do **not** apply the upstream `multus-daemonset-thick.yml` for this: it also creates a second Multus DaemonSet and a ServiceAccount called `multus` that collides with the one the Helm chart creates.

### Install Multus

```bash
helm upgrade --install multus rke2-charts/rke2-multus \
  -n kube-system \
  --values multus-values.yaml \
  --version v4.3.118
```

On a node, add `--kubeconfig /etc/rancher/k3s/k3s.yaml`. From a workstation leave it out: that file only exists on the nodes.

### Required on k3s 1.35 (Kairos): copy three binaries onto every node

After the install, **new pods cannot start until this is done** (running pods are not affected). Checked on 2026-11-07 on k3s v1.35.10 with chart v4.3.118:

- k3s's containerd searches only `/var/lib/rancher/k3s/data/cni` for CNI plugins, but the chart installs `multus-shim` into `/opt/cni/bin`. Without it: `failed to find plugin "multus-shim" in path [/var/lib/rancher/k3s/data/cni]`.
- The Multus daemon looks for the delegate plugins in `/opt/cni/bin`, which has no `flannel` or `cni`. Without them: `plugin type="flannel" failed (add): failed to find plugin "flannel" in path [/opt/cni/bin]`.
- The chart cannot move either directory (the thick DaemonSet hardcodes `/opt/cni/bin`), so copy the files. Use **copies, not symlinks**: Multus runs in a container, where an absolute symlink to a host path does not resolve.

Run once per node, with the name of that node's Multus pod (`kubectl -n kube-system get pods -o wide | grep multus`):

```bash
kubectl -n kube-system exec <multus-pod-on-that-node> -c kube-multus -- sh -c '
set -e
H=/hostroot/var/lib/rancher/k3s/data/cni
for p in cni flannel; do T=$(readlink "$H/$p"); cp "/hostroot$T" "/opt/cni/bin/$p"; chmod 755 "/opt/cni/bin/$p"; done
cp /opt/cni/bin/multus-shim "$H/multus-shim"; chmod 755 "$H/multus-shim"'
```

(`readlink` plus the `/hostroot` prefix is needed because the k3s plugin files are absolute symlinks that only resolve on the host.) Verify with a throwaway pod pinned to each node, for example `kubectl run cni-probe --image=busybox:1.37 --restart=Never --overrides='{"spec":{"nodeName":"e1"}}' --command -- sleep 60`; it should reach `Running` and get a `10.42.x.x` IP.

Caveats, not verified: the copies live on the persistent partition, but a k3s upgrade replaces the plugin binary behind the symlinks and a chart upgrade replaces `multus-shim` in `/opt/cni/bin`, so repeat the copy after either. I have not checked whether k3s clears extra files in `data/cni` on restart. A reinstall of a node loses all three copies.

### NetworkAttachmentDefinition CRD

Installed by the `rke2-multus-crd` chart above. Without it the Multus daemon logs `could not find the requested resource (get network-attachment-definitions.k8s.cni.cncf.io)` and `multus-lan.yaml` cannot be applied. Removing that chart deletes the CRD and with it every NetworkAttachmentDefinition.

### Create Network Attachment Definition

Needs the CRD from the `rke2-multus-crd` chart (see above); without it `kubectl apply` fails because the kind does not exist.

```bash
kubectl apply -f multus-lan.yaml
```

This creates `lan-network` in the `default` namespace: an `ipvlan` interface on the host's `ens18` with static IPAM and a route to `192.168.31.0/24` via `192.168.31.1`. A NetworkAttachmentDefinition is namespaced, so a pod's annotation must name both `lan-network` and `"namespace": "default"` (Home Assistant's does).

Before applying, check on every node that the `master` interface exists and the plugin is present (done on 2026-11-07, all three nodes passed):

```bash
for p in $(kubectl -n kube-system get pods -o name | grep multus); do
  kubectl -n kube-system exec ${p#pod/} -c kube-multus -- ls /hostroot/sys/class/net | grep -x ens18
done                                                   # one ens18 line per node
kubectl -n kube-system exec <multus-pod> -c kube-multus -- ls /opt/cni/bin | grep -x ipvlan
```

Verify:

```bash
kubectl get network-attachment-definitions -A     # default   lan-network
```

Applying it changes nothing for running pods; it only takes effect for a pod that references it. The Multus daemons log `pod not found ... but continue to delete` when a pod is removed before they handle its cleanup; that is harmless.

Not verified: `apps/smart/hass/hass.yaml` also requests a `mac` for this network. `ipvlan` interfaces share the parent's MAC address, so I expect that field to have no effect, but I have not started Home Assistant to check.

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

2. **Missing flannel/cni/multus-shim binaries**
   - Symptoms and the fix are in "Required on k3s 1.35 (Kairos)" above. The older one-liner that copied from `/hostroot/var/lib/rancher/k3s/data/cni/<name>` does not work on k3s 1.35: those entries are absolute symlinks that do not resolve inside the container, and it never covered `multus-shim`.

3. **Multus not being invoked for new pods**
   - Verify `00-multus.conf` exists in the correct location:
     ```bash
     kubectl exec -n kube-system <multus-pod> -c kube-multus -- \
       ls -la /hostroot/var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf
     ```

4. **Multus daemon logs `could not find the requested resource (get network-attachment-definitions.k8s.cni.cncf.io)`**
   - Cause: the NetworkAttachmentDefinition CRD is not installed. The `rke2-multus` chart ships no CRDs; they come from the separate `rke2-multus-crd` chart.
   - Fix:
     ```bash
     helm upgrade --install multus-crd rke2-charts/rke2-multus-crd -n kube-system --version 4.3.118
     kubectl get crd network-attachment-definitions.k8s.cni.cncf.io   # should exist
     ```
   - No restart of the Multus pods is needed. On 2026-11-07 each node had logged 60 to 64 of these errors before the CRD chart was installed and none after.
   - Do not use the upstream `multus-daemonset-thick.yml` to get the CRD: it also creates a second DaemonSet and a ServiceAccount named `multus` that collides with the Helm chart's.
   - Until the CRD exists, `kubectl apply -f multus-lan.yaml` fails and pods that request an additional network (Home Assistant) cannot be created.

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
