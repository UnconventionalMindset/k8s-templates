# K3s Cluster Maintenance Guide

This guide covers maintenance procedures for the Kairos K3s cluster, including graceful shutdown and startup procedures.

## Cluster Overview

- **Nodes**: 2 K3s nodes running on Kairos VMs
  - Node `e2` (kairos-fed-k3s-e2): 192.168.31.192
  - Node `hs` (kairos-fed-k3s-hs): 192.168.31.193
- **Storage**: Longhorn distributed storage
- **Network**: kube-router CNI, metallb load balancer

## Graceful Cluster Shutdown

Use this procedure when performing maintenance that requires shutting down the entire cluster.

### Step 1: Delete Pod Disruption Budgets (PDBs)

PDBs can prevent pods from being evicted during drain. For a full cluster shutdown, it's safe to remove them:

```bash
kubectl delete pdb -A --all
```

Note: PDBs will be automatically recreated when applications restart.

### Step 2: Cordon and Drain Nodes

Cordon nodes to prevent new pods from being scheduled:

```bash
kubectl cordon e2 hs
```

Drain both nodes to evict all pods gracefully:

```bash
# Drain node e2
kubectl drain e2 --ignore-daemonsets --delete-emptydir-data --force --grace-period=30

# Drain node hs
kubectl drain hs --ignore-daemonsets --delete-emptydir-data --force --grace-period=30
```

Flags explained:
- `--ignore-daemonsets`: Skip DaemonSet-managed pods (they can't be evicted)
- `--delete-emptydir-data`: Delete pods with emptyDir volumes
- `--force`: Delete pods not managed by ReplicationController, ReplicaSet, Job, DaemonSet, or StatefulSet
- `--grace-period=30`: Allow 30 seconds for graceful pod termination

### Step 3: Verify Drain Status

Check that workload pods have been evicted (DaemonSets will remain):

```bash
kubectl get pods -A -o wide
```

### Step 4: Shutdown VMs

Shutdown the Kairos VMs via SSH:

```bash
# Shutdown e2 node
ssh -i ~/.ssh/coreos kairos@192.168.31.192 "sudo shutdown -h now"

# Shutdown hs node
ssh -i ~/.ssh/coreos kairos@192.168.31.193 "sudo shutdown -h now"
```

Alternatively, shutdown from Proxmox:

```bash
# From Proxmox host
ssh -i ~/.ssh/coreos root@192.168.31.86 "qm shutdown <VM_ID>"  # For e2
ssh -i ~/.ssh/coreos root@192.168.31.84 "qm shutdown <VM_ID>"  # For hs
```

## Cluster Startup

### Step 1: Start VMs

Start VMs from Proxmox web UI or via CLI:

```bash
# From Proxmox hosts
ssh -i ~/.ssh/coreos root@192.168.31.86 "qm start <VM_ID>"  # For e2
ssh -i ~/.ssh/coreos root@192.168.31.84 "qm start <VM_ID>"  # For hs
```

### Step 2: Wait for Nodes to be Ready

Monitor node status:

```bash
kubectl get nodes -w
```

Wait until both nodes show `Ready` status.

### Step 3: Uncordon Nodes

Allow scheduling on the nodes again:

```bash
kubectl uncordon e2 hs
```

### Step 4: Verify Cluster Health

Check that all pods are running:

```bash
kubectl get pods -A
```

Check Longhorn storage health:

```bash
kubectl get volumes -n longhorn-system
```

Check that applications are accessible via their LoadBalancer IPs.

## Troubleshooting

### Drain Stuck on Pod Disruption Budget

If drain gets stuck with errors like "Cannot evict pod as it would violate the pod's disruption budget":

1. Delete the PDBs: `kubectl delete pdb -A --all`
2. Retry the drain command

### Pods Not Starting After Cluster Restart

1. Check node status: `kubectl get nodes`
2. Check pod status and events: `kubectl describe pod <pod-name> -n <namespace>`
3. Check Longhorn volume status: `kubectl get volumes -n longhorn-system`
4. Check storage class: `kubectl get sc`

### Longhorn Volumes Not Attaching

This can happen if Longhorn instance managers didn't start properly:

1. Check Longhorn pods: `kubectl get pods -n longhorn-system`
2. Restart Longhorn components if needed
3. Check Longhorn UI for volume health

### Network Issues After Restart

1. Verify kube-router pods are running: `kubectl get pods -n kube-system -l k8s-app=kube-router`
2. Verify metallb speaker pods are running: `kubectl get pods -n metallb-system`
3. Check service IPs: `kubectl get svc -A`

## Partial Node Maintenance

For maintaining a single node while keeping the cluster operational:

### Take Down One Node

```bash
# Cordon the node
kubectl cordon <node-name>

# Drain the node
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --grace-period=60

# Shutdown the VM
ssh -i ~/.ssh/coreos kairos@<node-ip> "sudo shutdown -h now"
```

### Bring Node Back Online

```bash
# Start the VM (from Proxmox)
# Wait for node to be Ready
kubectl get nodes -w

# Uncordon the node
kubectl uncordon <node-name>
```

Note: With only 2 nodes, some services with replica count > 1 may not achieve full availability during single-node maintenance due to anti-affinity rules or insufficient resources.

## Best Practices

1. **Planned Maintenance**: Schedule maintenance during low-usage periods
2. **Backups**: Always ensure recent backups exist before maintenance
3. **Monitoring**: Monitor cluster health during and after maintenance
4. **Documentation**: Document any issues or deviations from this procedure
5. **PDB Awareness**: Understand which applications have PDBs before draining
6. **Storage Considerations**: Longhorn requires at least 2 healthy nodes for replica synchronization

## Emergency Shutdown

If you need to shutdown immediately without graceful drain:

```bash
# Shutdown VMs directly
ssh -i ~/.ssh/coreos kairos@192.168.31.192 "sudo shutdown -h now"
ssh -i ~/.ssh/coreos kairos@192.168.31.193 "sudo shutdown -h now"
```

Note: Emergency shutdown may result in:
- Unfinished database transactions
- Corrupted application state
- Longer recovery time on startup
- Potential Longhorn volume inconsistencies

Use this only when necessary (e.g., power outage, critical security issue).
