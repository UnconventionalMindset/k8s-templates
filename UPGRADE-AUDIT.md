# Homelab Kubernetes Cluster & Repository Upgrade Audit

**Audit Date:** September 12, 2026  
**Cluster:** K3s `v1.33.4+k3s1` (Dual-node: `hs` [192.168.31.193] & `e2` [192.168.31.192])  
**Target Repository:** `UnconventionalMindset/k8s-templates`

---

## 1. Upgrades Executed & Verified (Current Session)

The following components were updated in the repository configuration and successfully rolled out and verified in the live Kubernetes cluster:

| Component | Target Manifest / Config | Previous Version | Upgraded Version | Status in Cluster | Verification Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **qBittorrent** | [`apps/tools/qbittorrent/qbit.yaml`](apps/tools/qbittorrent/qbit.yaml) | `5.2.2` | `5.2.3` | **Running** (`1/1`) | Clean rolling update, web UI and downloads operational |
| **Traefik Ingress** | [`README.md`](README.md), [`apps/network/traefik/traefik-values.yaml`](apps/network/traefik/traefik-values.yaml) | Chart `41.0.1` (`v3.7.5`) | Chart `41.5.0` (`v3.7.13`) | **Running** (`1/1`) | Server-side CRDs applied before Helm upgrade; ingress routes healthy |
| **Cert-Manager** | [`README.md`](README.md), [`apps/security/cert-manager/cert-manager-values.yaml`](apps/security/cert-manager/cert-manager-values.yaml) | `v1.20.3` | `v1.21.2` | **Running** (`1/1` x4 pods) | CRDs updated to v1.21.2; controller, webhook, and cainjector healthy |
| **Longhorn** | [`apps/admin/longhorn/kustomization.yaml`](apps/admin/longhorn/kustomization.yaml) | `v1.12.0` | `v1.12.1` | **Running** (`2/2` managers) | Patch upgrade; new engine images active on both nodes |
| **Kube-Router** | [`README.md`](README.md) | `v2.10.0` | `v2.11.1` | **Running** (DaemonSet `2/2`) | CNI daemonset rolling restart completed with zero node disruption |
| **Multus CNI** | [`README.md`](README.md), [`apps/network/multus/multus-values.yaml`](apps/network/multus/multus-values.yaml) | Chart `v4.2.418` (`4.2.4`) | Chart `v4.3.101` (`4.3.1`) | **Running** (DaemonSet `2/2`) | Upgraded via `rke2-charts`; host network CNI configuration maintained |
| **Immich** | [`apps/media/immich/immich.yaml`](apps/media/immich/immich.yaml) | `v3.1.0` | `v3.2.0` | **Running** (Server & ML `1/1`) | Automatic database migrations completed; ML & server containers healthy |
| **Code-Server** | [`apps/dev/code/code.yaml`](apps/dev/code/code.yaml) | `4.107.1` | `4.137.0` | **Running** (`2/2` replicas) | Rolled out across both cluster nodes |
| **Bazarr** | [`apps/rr/bazarr/bazarr.yaml`](apps/rr/bazarr/bazarr.yaml) | `1.5.4` | `1.6.0` | **Running** (`1/1`) | Verified safe; patches RCE vulnerability; database schema updated |
| **Radarr** | [`apps/rr/radarr/radarr.yaml`](apps/rr/radarr/radarr.yaml) | `6.0.4` | `6.2.1` | **Running** (`1/1`) | Non-breaking release within v6; internal DB migrations applied |
| **Sonarr** | [`apps/rr/sonarr/sonarr.yaml`](apps/rr/sonarr/sonarr.yaml) | `4.0.16` | `4.0.19` | **Running** (`1/1`) | Minor patch within v4; database schema and download integration verified |

---

## 2. Actively Running Services Remaining to Upgrade

These services are actively serving traffic/pods in the cluster and have newer versions available:

| Component | Manifest / Release | Currently Running | Available Version | Risk Level | Notes & Recommendations |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Vaultwarden** | [`apps/security/vaultwarden/vaultwarden-values.yaml`](apps/security/vaultwarden/vaultwarden-values.yaml) | `1.33.2-alpine` | `1.37.2-alpine` | **Low** | Git config specifies `1.37.2-alpine`, but the running Helm release still uses chart default `1.33.2-alpine`. Run `helm upgrade` with values to sync. |
| **Homarr** | [`apps/rr/homarr/homarr.yaml`](apps/rr/homarr/homarr.yaml) | `v1.50.0` (Git: `v1.53.1`) | `v1.77.1` | **Low / Medium** | Upstream branch `origin/renovate/ghcr.io-homarr-labs-homarr-1.x` is available. |
| **Authentik** | [`apps/security/authentik/authentik-values.yaml`](apps/security/authentik/authentik-values.yaml) | Chart `2026.5.3` | Chart `2026.8.2` | **Medium** | Minor jump across three monthly releases. Test auth middleware and forward-auth flows after upgrading. |
| **ClusterSecret Operator** | Release `clustersecret` in namespace `clustersecret` | Chart `0.5.2` (`0.0.14`) | Chart `0.7.0` | **Low** | Routine operator update from `charts.clustersecret.com`. |
| **Jellyseerr** | [`apps/rr/jellyseerr/jellyseerr.yaml`](apps/rr/jellyseerr/jellyseerr.yaml) | `2.7.3` | `3.4.1` | **Medium / High** | Major version update (v2 &rarr; v3). Take a snapshot/backup of `jellyseerr-config-nfs` before upgrading. |
| **Gitea** | Release `gitea` in namespace `bazar` | Chart `11.0.1` (`1.23.6`) | Chart `12.7.0` (`1.27.0`) | **High** | Multi-minor version upgrade across Gitea 1.23 &rarr; 1.27. Read intermediate Gitea migration notes. |
| **Redis** | Release `redis` in namespace `db` | Chart `24.1.0` (`8.4.0`) | Chart `28.1.0` (`8.10.1`) | **High** | Bitnami chart major version bump. Parameter schemas in `values.yaml` frequently change; verify before applying. |
| **PostgreSQL** | [`apps/storage/postgres/postgres.yaml`](apps/storage/postgres/postgres.yaml) | `postgres:16-...` | Postgres `17` | **High** | Major database version bump. Direct image tag update will corrupt or reject the PGDATA directory. Requires `pg_upgrade` or dump/restore. |
| **Helm Secrets (SOPS)** | [`README.md`](README.md#L39) | `v4.6.1` | `v4.7.7` | **Low** | Local CLI plugin: `helm plugin update secrets` or re-install `v4.7.7`. |

---

## 3. Repo Workloads Not Currently Running in Cluster

These manifests exist in git, but no active workloads are currently deployed:

| Component | Manifest Path | Configured Version | Latest Available | Renovate Branch / Source |
| :--- | :--- | :--- | :--- | :--- |
| **Home Assistant** | [`apps/smart/hass/hass.yaml`](apps/smart/hass/hass.yaml) | `2026.4.2` | `2026.9.2` | `origin/renovate/docker.io-homeassistant-home-assistant-2026.x` |
| **Zigbee2MQTT** | [`apps/smart/zigbee/zigbee.yaml`](apps/smart/zigbee/zigbee.yaml) | `2.7.2` | `2.14.1` | `origin/renovate/docker.io-koenkk-zigbee2mqtt-2.x` |
| **Homepage** | [`apps/interfaces/homepage/homepage.yaml`](apps/interfaces/homepage/homepage.yaml) | `v1.8.0` | `v1.13.2` | `origin/renovate/ghcr.io-gethomepage-homepage-1.x` |
| **Prowlarr** | [`apps/rr/prowlarr/prowlarr.yaml`](apps/rr/prowlarr/prowlarr.yaml) | `2.3.0` | `2.4.0` | `origin/renovate/lscr.io-linuxserver-prowlarr-2.x` |
| **Obsidian** | [`apps/office/obsidian/obsidian.yaml`](apps/office/obsidian/obsidian.yaml) | `1.10.6` | `1.11.7` | `origin/renovate/lscr.io-linuxserver-obsidian-1.x` |
| **Metrics Server** | [`apps/monitoring/metrics/metrics.yaml`](apps/monitoring/metrics/metrics.yaml) | `v0.7.2` | `v0.9.0` | `origin/renovate/registry.k8s.io-metrics-server-metrics-server-0.x` |
| **kube-prometheus-stack** | [`apps/monitoring/prom-stack/`](apps/monitoring/prom-stack/) | Chart `75.12.0` | Chart `90.1.1` | `prometheus-community/kube-prometheus-stack` |
| **Democratic CSI** | [`apps/storage/democratic-csi/`](apps/storage/democratic-csi/) | Not deployed | Latest chart | Ready for execution via [`START-HERE.md`](START-HERE.md) |
| **Appsmith** | [`apps/tools/appsmith/`](apps/tools/appsmith/) | Chart `4.0.0` | — | Commented out in [`README.md`](README.md) |

---

## 4. Components Already Up to Date

- **Jellyfin**: `10.11.11` (Merged in PR #524)
- **Kopia**: `0.23.1` (Merged in PR #523)
- **Mosquitto**: `2.0.22`
- **Kubernetes Dashboard**: `7.14.0`
- **MetalLB**: `v0.16.1`
- **K3s Cluster Core**: `v1.33.4+k3s1`

---

## 5. Recommended Next Steps

1. **Vaultwarden Sync (Immediate / Zero risk):**
   ```bash
   helm upgrade --install -n auth vaultwarden gabe565/vaultwarden \
     --values apps/security/vaultwarden/vaultwarden-values.yaml \
     --version 0.16.1
   ```
2. **Homarr Update:**
   Update [`apps/rr/homarr/homarr.yaml`](apps/rr/homarr/homarr.yaml) image to `ghcr.io/homarr-labs/homarr:v1.77.1` and apply.
3. **Authentik Upgrade:**
   Review changelogs between `2026.5.3` and `2026.8.2`, then upgrade the Helm release.
4. **Hold on Major Database Migrations:**
   Do not blindly bump Bitnami Redis or PostgreSQL 16 &rarr; 17 without dedicated maintenance windows and database backup/restore procedures.
