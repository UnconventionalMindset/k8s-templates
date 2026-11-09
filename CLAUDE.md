# Infrastructure Documentation

## Server Architecture

This homelab environment consists of a Proxmox cluster running Kairos VMs with K3s Kubernetes.

### Proxmox Hosts

| Hostname | IP Address | SSH Key | User | Notes |
|----------|------------|---------|------|-------|
| homeserver | 192.168.31.84 | ~/.ssh/coreos | root | Proxmox host 1 |
| elitedesk-2 | 192.168.31.86 | ~/.ssh/coreos | root | Proxmox host 2 |
| elitedesk-1 | 192.168.31.85 | ~/.ssh/coreos | root | Proxmox host 3 (runs the e1 node VM and the haos VM) |

### Kairos VMs (K3s Nodes)

| Hostname | IP Address | SSH Key | User | Sudo Password | Notes |
|----------|------------|---------|------|---------------|-------|
| kairos-fed-k3s-e2 | 192.168.31.192 | ~/.ssh/kairos | kairos | None (passwordless) | K3s node running on elitedesk-2 |
| kairos-fed-k3s-hs | 192.168.31.193 | ~/.ssh/kairos | kairos | None (passwordless) | K3s node running on homeserver |
| kairos-fed-k3s-e1 | 192.168.31.191 | ~/.ssh/kairos | kairos | None (passwordless) | K3s node running on elitedesk-1 |

All three VMs run K3s as control-plane/etcd servers and form one Kubernetes cluster. In the reinstalled cluster `e1` (192.168.31.191) is the first (master, `--cluster-init`) server and the API endpoint (`https://192.168.31.191:6443`); `e2` and `hs` join it. For reinstalling them see `docs/kairos-reinstall-guide.md`.

### Storage

| Hostname | IP Address | SSH Key | User | Notes |
|----------|------------|---------|------|-------|
| truenas | 192.168.31.99 | ~/.ssh/coreos | admin | NAS storage |

## SSH Access

Proxmox hosts and TrueNAS use `~/.ssh/coreos`; the Kairos K3s VMs use `~/.ssh/kairos`.

**Example SSH commands:**
```bash
# Proxmox hosts
ssh -i ~/.ssh/coreos root@192.168.31.84  # homeserver
ssh -i ~/.ssh/coreos root@192.168.31.86  # elitedesk-2

# Kairos VMs (K3s nodes)
ssh -i ~/.ssh/kairos kairos@192.168.31.192  # kairos-fed-k3s-e2
ssh -i ~/.ssh/kairos kairos@192.168.31.193  # kairos-fed-k3s-hs

# NAS
ssh -i ~/.ssh/coreos admin@192.168.31.99  # truenas
```

## Network Topology

```
├── Proxmox Cluster
│   ├── homeserver (192.168.31.84)
│   │   └── kairos-fed-k3s-hs VM (192.168.31.193)
│   │       └── K3s node
│   └── elitedesk-2 (192.168.31.86)
│       └── kairos-fed-k3s-e2 VM (192.168.31.192)
│           └── K3s node
└── truenas NAS (192.168.31.99)
```

## Kubernetes Cluster

The K3s cluster consists of both Kairos VMs:
- Node: kairos-fed-k3s-e2 (192.168.31.192)
- Node: kairos-fed-k3s-hs (192.168.31.193)

Network CNI: kube-router
Load balancer: metallb
