# Secure Democratic CSI Setup Guide

## Security Layers

### 1. TrueNAS Side Security

#### Create Isolated Dataset
```bash
# On TrueNAS (via SSH or UI)
# Create a dedicated parent dataset that CSI can manage
zfs create -o compression=lz4 ssd120/k8s-dynamic
zfs set quota=500G ssd120/k8s-dynamic  # Limit total space

# Set permissions
chmod 770 /mnt/ssd120/k8s-dynamic
```

#### Create Limited API User (TrueNAS UI)
1. **Accounts > Users > Add**
   - Username: `k8s-csi`
   - Disable password
   - No sudo access
   - Shell: `nologin`

2. **Storage > Pools > Permissions**
   - `/mnt/ssd120/k8s-dynamic`: Owner `k8s-csi`
   - All other datasets: NO access for `k8s-csi`

3. **API Keys > Add**
   - Create API key for user `k8s-csi`
   - **Copy the key - shown only once!**

### 2. Kubernetes Side Security

#### Install Sealed Secrets (Encrypt API Keys)
```bash
# Install sealed secrets controller
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system

# Create secret (replace YOUR_API_KEY)
kubectl create secret generic truenas-api \
  --from-literal=api-key='YOUR_API_KEY' \
  --namespace democratic-csi \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > truenas-api-sealed.yaml

# Now you can safely commit truenas-api-sealed.yaml to git
kubectl apply -f truenas-api-sealed.yaml
```

#### Democratic CSI Values (Restricted)
```yaml
# democratic-csi-values.yaml
csiDriver:
  name: "org.democratic-csi.nfs"

driver:
  config:
    driver: freenas-api-nfs

    # TrueNAS connection
    httpConnection:
      protocol: https
      host: 192.168.31.99
      port: 443
      # Use sealed secret
      apiKey: ${TRUENAS_API_KEY}
      allowInsecure: false  # Require valid SSL

    # CRITICAL: Restrict to isolated dataset
    zfs:
      datasetParentName: ssd120/k8s-dynamic
      detachedSnapshotsDatasetParentName: ssd120/k8s-dynamic/.snapshots

      # Security settings
      datasetProperties:
        "org.freenas:description": "Managed by K8s CSI - Do Not Modify"

    nfs:
      shareHost: 192.168.31.99
      shareAlldirs: false  # Only share specific directories
      shareAllowedHosts:
        - 192.168.31.192  # Only your K8s nodes
        - 192.168.31.193
      shareAllowedNetworks: []
      shareMaprootUser: root
      shareMaprootGroup: root

storageClasses:
  - name: truenas-nfs-csi
    defaultClass: false
    reclaimPolicy: Retain  # NEVER auto-delete data
    volumeBindingMode: Immediate
    allowVolumeExpansion: true

    parameters:
      fsType: nfs

    mountOptions:
      - nfsvers=4.2
      - hard
      - noatime

# Resource limits for CSI controller
controller:
  resources:
    limits:
      cpu: 200m
      memory: 256Mi

# Enable audit logging
controller:
  extraEnv:
    - name: LOG_LEVEL
      value: "info"
```

### 3. RBAC Restrictions

```yaml
# Only allow specific namespaces to use CSI
apiVersion: v1
kind: ResourceQuota
metadata:
  name: democratic-csi-quota
  namespace: democratic-csi
spec:
  hard:
    persistentvolumeclaims: "50"  # Max 50 PVCs
    requests.storage: "2Ti"        # Max 2TB total
```

### 4. Network Policies

```yaml
# Restrict CSI controller network access
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: democratic-csi-netpol
  namespace: democratic-csi
spec:
  podSelector:
    matchLabels:
      app: democratic-csi-controller
  policyTypes:
    - Egress
  egress:
    # Only allow TrueNAS API access
    - to:
      - ipBlock:
          cidr: 192.168.31.99/32
      ports:
      - protocol: TCP
        port: 443
    # Allow DNS
    - to:
      - namespaceSelector:
          matchLabels:
            name: kube-system
      ports:
      - protocol: UDP
        port: 53
```

### 5. Monitoring & Alerts

```bash
# Watch for suspicious activity
kubectl logs -n democratic-csi -l app=democratic-csi-controller --tail=100 -f

# Set up alerts for:
# - Dataset deletions
# - Quota exceeded
# - API authentication failures
# - Unusual dataset creation patterns
```

## Security Checklist

- [ ] Dedicated TrueNAS user `k8s-csi` with minimal permissions
- [ ] Isolated parent dataset `/mnt/ssd120/k8s-dynamic`
- [ ] API key stored in Sealed Secret (encrypted)
- [ ] `reclaimPolicy: Retain` (never auto-delete)
- [ ] Network policy restricting CSI controller
- [ ] Resource quotas limiting PVC creation
- [ ] SSL certificate validation enabled
- [ ] NFS shares restricted to K8s node IPs only
- [ ] Audit logging enabled
- [ ] Regular backup of all datasets (your existing Kopia setup)

## Emergency Procedures

### Revoke Access Immediately
```bash
# On TrueNAS - delete API key
# System > API Keys > Delete k8s-csi key

# The CSI controller will stop working but existing mounts remain
```

### Disaster Recovery
```bash
# Your manual datasets are unaffected
# CSI-managed datasets are in /mnt/ssd120/k8s-dynamic

# Restore from backup using your existing Kopia setup
```

## Risk Assessment

| Risk | Mitigation | Severity |
|------|------------|----------|
| API key leaked | Sealed Secrets + revoke immediately | Medium |
| Dataset deleted | Retain policy + backups | Low |
| Quota exceeded | Resource quotas | Low |
| Wrong dataset modified | Isolated parent dataset | Very Low |
| Network attack | Network policies + IP whitelist | Low |

## Alternative: Hybrid Approach

**Most Secure Option:**
- Use Democratic CSI ONLY for non-critical, easily replaceable data
- Continue manual datasets for critical apps (Immich, Jellyfin, etc.)
- Best of both worlds: convenience + control

Example:
- `storageClassName: truenas-nfs-csi` → Testing, temp data
- Manual PV/PVC → Production apps with critical data
