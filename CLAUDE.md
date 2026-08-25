# Infrastructure Documentation

## Server Architecture

This homelab environment consists of a Proxmox cluster running Kairos VMs with K3s Kubernetes.

### Proxmox Hosts

| Hostname | IP Address | SSH Key | User | Notes |
|----------|------------|---------|------|-------|
| homeserver | 192.168.31.84 | ~/.ssh/coreos | root | Proxmox host 1 |
| elitedesk-2 | 192.168.31.86 | ~/.ssh/coreos | root | Proxmox host 2 |

### Kairos VMs (K3s Nodes)

| Hostname | IP Address | SSH Key | User | Sudo Password | Notes |
|----------|------------|---------|------|---------------|-------|
| kairos-fed-k3s-e2 | 192.168.31.192 | ~/.ssh/coreos | kairos | None (passwordless) | K3s node running on elitedesk-2 |
| kairos-fed-k3s-hs | 192.168.31.193 | ~/.ssh/coreos | kairos | None (passwordless) | K3s node running on homeserver |

Both VMs run K3s and form a Kubernetes cluster.

### Storage

| Hostname | IP Address | SSH Key | User | Notes |
|----------|------------|---------|------|-------|
| truenas | 192.168.31.99 | ~/.ssh/coreos | admin | NAS storage |

## SSH Access

All servers use the same SSH key: `~/.ssh/coreos`

**Example SSH commands:**
```bash
# Proxmox hosts
ssh -i ~/.ssh/coreos root@192.168.31.84  # homeserver
ssh -i ~/.ssh/coreos root@192.168.31.86  # elitedesk-2

# Kairos VMs (K3s nodes)
ssh -i ~/.ssh/coreos kairos@192.168.31.192  # kairos-fed-k3s-e2
ssh -i ~/.ssh/coreos kairos@192.168.31.193  # kairos-fed-k3s-hs

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
