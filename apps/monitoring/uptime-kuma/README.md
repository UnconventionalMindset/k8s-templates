# Uptime Kuma - Network Monitoring

Uptime Kuma is a self-hosted monitoring tool similar to Uptime Robot.

## Features
- Monitor uptime for HTTP(s), TCP, Ping, DNS, and more
- Beautiful web UI
- Notifications (Discord, Slack, Email, etc.)
- Multi-language support
- Certificate monitoring

## Storage

This deployment uses **Democratic CSI** for automatic storage provisioning:
- Storage Class: `truenas-nfs-csi`
- Auto-creates ZFS dataset: `/mnt/ssd120/k8s-dynamic/uptime-kuma/uptime-kuma-data`
- Size: 5Gi (SQLite database + config)
- Access Mode: ReadWriteMany (NFS)

## Installation

See: `/home/jac/homelab/k8s-templates/apps/storage/democratic-csi/UPTIME-KUMA-SETUP.md`

Quick install (after Democratic CSI is set up):

```bash
kubectl apply -k /home/jac/homelab/k8s-templates/apps/monitoring/uptime-kuma/
```

## Access

### Port Forward (Quick Access)
```bash
kubectl port-forward -n uptime-kuma svc/uptime-kuma 3001:3001
```

Then open: http://localhost:3001

### IngressRoute (Production)
1. Edit `ingress.yaml`:
   - Change `uptime.umhomelab.com` to your domain
   - Uncomment Authentik middleware if you want authentication
2. Uncomment ingress in `kustomization.yaml`
3. Apply: `kubectl apply -k .`

Access via: https://uptime.umhomelab.com

## First Time Setup

1. Open Uptime Kuma UI
2. Create admin account (first user becomes admin)
3. Add monitors for your services

## Verification

```bash
# Check pod is running
kubectl get pods -n uptime-kuma

# Check PVC is bound
kubectl get pvc -n uptime-kuma

# Check logs
kubectl logs -n uptime-kuma -l app=uptime-kuma

# Verify dataset on TrueNAS
ssh -i ~/.ssh/coreos admin@192.168.31.99 "zfs list | grep uptime-kuma"
```

## Monitoring Examples

Once Uptime Kuma is running, you can monitor:
- Your Jellyfin server
- Home Assistant
- Your router/gateway
- External websites
- Certificate expiry dates

## Backup

The SQLite database is in the PVC at `/app/data/kuma.db`.

Democratic CSI with Retain policy means:
- Data persists even if PVC is deleted
- ZFS dataset remains on TrueNAS
- Include `/mnt/ssd120/k8s-dynamic/uptime-kuma` in your Kopia backups

## Upgrading

```bash
# Pull latest image
kubectl rollout restart deployment/uptime-kuma -n uptime-kuma

# Or update image version in deployment.yaml and apply
```

## Troubleshooting

### PVC Stuck in Pending
```bash
# Check CSI controller logs
kubectl logs -n democratic-csi -l app.kubernetes.io/component=controller

# Verify storage class exists
kubectl get storageclass truenas-nfs-csi
```

### Pod CrashLoopBackOff
```bash
# Check pod logs
kubectl logs -n uptime-kuma -l app=uptime-kuma

# Check volume mount
kubectl describe pod -n uptime-kuma -l app=uptime-kuma
```

### Can't Access UI
```bash
# Check service
kubectl get svc -n uptime-kuma

# Check pod readiness
kubectl get pods -n uptime-kuma

# Port forward directly to pod
kubectl port-forward -n uptime-kuma $(kubectl get pod -n uptime-kuma -l app=uptime-kuma -o name) 3001:3001
```

## Resource Usage

Expected resource usage:
- CPU: ~50-100m (idle), up to 500m (checking monitors)
- Memory: ~128Mi (can grow to 512Mi)
- Storage: ~100Mi (database grows with history)

## Configuration

Uptime Kuma stores all config in SQLite database:
- Location: `/app/data/kuma.db` (in PVC)
- Includes: monitors, notifications, settings, history

No additional ConfigMaps needed.

## Uninstall

```bash
# Delete all resources
kubectl delete -k /home/jac/homelab/k8s-templates/apps/monitoring/uptime-kuma/

# Note: PV will remain on TrueNAS due to Retain policy
# Manual cleanup if needed:
ssh -i ~/.ssh/coreos admin@192.168.31.99
zfs destroy ssd120/k8s-dynamic/uptime-kuma/uptime-kuma-data
```
