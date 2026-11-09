# K8s automations

## Nodes

The three K3s nodes (e1, e2, hs) are Kairos VMs on Proxmox, built from `quay.io/unconventionalmindset/kairos-fedora-transcoding`. `e1` is the first (master, `--cluster-init`) server; `e2` and `hs` join it at `https://192.168.31.191:6443`.
- Fresh install of the nodes: [docs/kairos-reinstall-guide.md](docs/kairos-reinstall-guide.md)
- Upgrading existing nodes in steps: [docs/kairos-upgrade-plan.md](docs/kairos-upgrade-plan.md)
- Image build: the `kairos-transcoding` project (`Dockerfile.byoi`)

Once the nodes are up and `kubectl get nodes` shows all three Ready, continue below.

### Kube router
```
k apply -f https://raw.githubusercontent.com/cloudnativelabs/kube-router/v2.12.0/daemonset/kubeadm-kuberouter.yaml
```

### Metal LB
https://metallb.universe.tf/installation/
```
k apply -f https://raw.githubusercontent.com/metallb/metallb/v0.16.1/config/manifests/metallb-native.yaml
k apply -f apps/admin/metallb/ipaddress_pools.yaml
```

## Handling secrets

### GPG key
```
export KEY_NAME="name"
export KEY_COMMENT="comment"

gpg --batch --full-generate-key <<EOF
%no-protection
Key-Type: 1
Key-Length: 4096
Subkey-Type: 1
Subkey-Length: 4096
Expire-Date: 0
Name-Comment: ${KEY_COMMENT}
Name-Real: ${KEY_NAME}
EOF

gpg --list-secret-keys "${KEY_NAME}"
```
Get the pub part of the output

### Helm secrets - SOPS
```
helm plugin install https://github.com/jkroepke/helm-secrets --version v4.6.1
```

### Cert Manager
```
k apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.21.3/cert-manager.crds.yaml
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --values=apps/security/cert-manager/cert-manager-values.yaml --version v1.21.3
```

### Traefik
```
helm repo add traefik https://traefik.github.io/charts
helm repo update
# Apply Custom Resource Definitions (CRDs) before upgrading
helm show crds traefik/traefik --version 41.5.0 | kubectl apply --server-side --force-conflicts -f -
helm upgrade --install traefik traefik/traefik --values=apps/network/traefik/traefik-values.yaml --version 41.5.0
k apply -f apps/network/traefik/ingress.yaml
```

### Further Traefik
Move the first middleware in the previous step in case of issues:
```
k apply -f apps/network/traefik/skip-ssl.yaml
k apply -f apps/network/traefik/reverse-proxy/nas-ingress.yaml
k apply -f apps/network/traefik/reverse-proxy/proxmox-hs-ingress.yaml
k apply -f apps/network/traefik/reverse-proxy/proxmox-e1-ingress.yaml
k apply -f apps/network/traefik/reverse-proxy/proxmox-e2-ingress.yaml
k apply -f apps/network/traefik/reverse-proxy/zigbee-controller-ingress.yaml
```

### Longhorn
```
k apply -k apps/admin/longhorn/
```

### Traefik SSL cert usage

### SSL / Let's Encrypt
 https://www.youtube.com/watch?v=G4CmbYL9UPg
```
k apply -f secrets/cf-token.secret.yaml
```
### Staging
```
k apply -f secrets/certificate-issuers/letsencrypt-staging.insecure.yaml
k apply -f apps/security/cert-manager/certificates/staging/umhomelab-com.yaml
k apply -f apps/security/cert-manager/certificates/staging/traefik-default-tls.yaml

# Check certificate status
kubectl describe certificaterequest umhomelab-com-staging-1 -n default
```

Wait for propagation: find the right pod by checking logs and wait till it says propagated.
The following command should output: `The certificate has been successfully issued` (when propagated).

```
k describe certificate umhomelab-com
```

If the cert does not appear:
  - the issue might be on the name used in traefik-default-tls.yaml
  - try deleting traefik pod or CTRL+F5

### Prod
```
k delete secret umhomelab-com-staging
k apply -f secrets/cf-token.secret.yaml
k apply -f secrets/certificate-issuers/letsencrypt-production.insecure.yaml
k apply -f apps/security/cert-manager/certificates/production/umhomelab-com.yaml
k apply -f apps/security/cert-manager/certificates/production/traefik-default-tls.yaml

# Check certificate status
kubectl describe certificaterequest umhomelab-com-1 -n default
```

### Postgres
```
k apply -f apps/storage/postgres/namespace.yaml

k apply -f secrets/pg.secret.yaml
k apply -f secrets/pgadmin.secret.yaml

k apply -f apps/storage/postgres/configmaps.yaml
k apply -f apps/storage/postgres/postgres.yaml
```

### Redis
```
k apply -f apps/storage/redis/volume.yaml
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm upgrade --install -n db redis bitnami/redis -f secrets/redis-values.insecure.yaml --version 28.3.12
```

### Authentik
```
k apply -f apps/security/authentik/namespace.yaml
k apply -f secrets/authentik.secret.yaml
k apply -f apps/security/authentik/authentik-volume+claim.yaml
helm repo add goauthentik https://charts.goauthentik.io
helm repo update
k apply -f apps/network/traefik/middlewares/
k apply -f apps/security/authentik/ingress.yaml
# TLS secret (authentik-outpost-tls) referenced by the embedded outpost ingress; needs cert-manager + the letsencrypt-production ClusterIssuer
k apply -f apps/security/authentik/authentik-outpost-tls.yaml
helm upgrade --install authentik goauthentik/authentik -f apps/security/authentik/authentik-values.yaml -n auth --version 2026.8.3

# If the embedded outpost does not upgrade automatically, force it:
kubectl set image deployment/ak-outpost-authentik-embedded-outpost -n auth proxy=ghcr.io/goauthentik/proxy:2026.8.3

# To get a long lived token for authentik: kubectl get secret jac -n dashboard -o jsonpath={".data.token"} | base64 -d
```

### Headlamp
```
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
helm repo update
k apply -f apps/interfaces/headlamp/namespace.yaml
helm upgrade --install headlamp headlamp/headlamp --namespace headlamp -f apps/interfaces/headlamp/values.yaml --version 0.45.0
k apply -f apps/interfaces/headlamp/ingress.yaml
```

### Radar
```
helm repo add skyhook https://skyhook-io.github.io/helm-charts
helm repo update
k apply -f apps/interfaces/radar/namespace.yaml
helm upgrade --install radar skyhook/radar --namespace radar -f apps/interfaces/radar/values.yaml --version 1.19.0
k apply -f apps/interfaces/radar/ingress.yaml
```

### K8s dashboard
```
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm repo update
helm upgrade --install dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace dashboard -f apps/interfaces/k8s-dashboard/values.yaml --version 7.14.0

k apply -f secrets/create-service-account.secret.yaml
k apply -f secrets/create-cluster_role_binding.secret.yaml
k apply -f secrets/get-bearer.secret.yaml

k apply -f apps/interfaces/k8s-dashboard/ingress.yaml
kubectl get secret jac -n dashboard -o jsonpath={".data.token"} | base64 -d
```

### Mosquitto
```
k apply -f apps/smart/mosquitto/
```

### Zigbee
```
k apply -f apps/smart/zigbee/
```

### OpenThread Border Router + Matter server

Radios on the SLZB-MR3 (192.168.31.88): **EFR32MG24 (port 6638, "Thread to remote OTBR" mode) = Thread/Matter**, **CC2674P10 (port 7638) = Zigbee (zigbee2mqtt, do not touch)**. Only one client may use a radio: stop any other OTBR (e.g. the Home Assistant add-on) before starting this one.

Both run with `hostNetwork` (Thread routing, mDNS, Matter multicast) and are pinned to node `e2`, so they share the node's network. State lives on the NAS (`/mnt/ssd120/apps/otbr`, `/mnt/ssd120/apps/matter`, static NFS PVs like the other apps).

```
# 1. On TrueNAS: create the folders AND one NFS share per folder (hosts 192.168.31.191/.192/.193, mapall core:core), otherwise the pods stay in ContainerCreating with "No such file or directory"
#    /mnt/ssd120/apps/otbr   /mnt/ssd120/apps/matter
k apply -f apps/smart/otbr/
k apply -f apps/smart/matter/
```

- OTBR: REST API `http://192.168.31.192:8081` (unauthenticated, LAN only), web UI `:8082`. The image has no socat, so a small python bridge (ConfigMap `otbr-radio-bridge`) connects the radio's TCP port to `otbr-agent`. The Thread dataset is persisted in the NFS folder `thread/`.
- Matter server: [matterjs-server](https://github.com/matter-js/matterjs-server) (the same implementation as the Home Assistant "Matter Server" add-on), WebSocket `ws://192.168.31.192:5580/ws`, dashboard `http://192.168.31.192:5580`. Data in the NFS folder `matterjs/`. `VENDOR_ID`/`FABRIC_ID` (4939 / 2) define the fabric identity and the storage folder `server-2-134b`: never change them once devices are paired.
- Restart with `k -n otbr rollout restart deploy/otbr` (not `delete pod`: the old pod would still hold the radio when the new one starts).
- Add to Home Assistant: Settings, Devices & services, add **Open Thread Border Router** with URL `http://192.168.31.192:8081`, add **Matter** (untick "Use the official Matter Server app") with URL `ws://192.168.31.192:5580/ws`. The Thread integration then offers the border router's dataset as preferred network.

#### Migrating Thread + Matter from the Home Assistant add-ons
Used to move from HA OS add-ons (OpenThread Border Router + Matter Server) to the pods above. Keep the add-ons installed (set to manual boot) for rollback.
1. Back up the add-ons in HA (or use the backup API) and save the Thread dataset (`otbr/info` websocket command, `active_dataset_tlvs`). The dataset is a secret.
2. Stop the **Matter Server add-on**, take a cold backup, and copy the add-on's `/data` folder into the NAS folder `matterjs/` (a helper pod mounting the `matter-nfs` PVC). Check the add-on's storage folder name (`server-<fabric>-<vendor hex>`) and set `FABRIC_ID`/`VENDOR_ID` to match, then start the pod. Verify `compressed_fabric_id` and the node count over the WebSocket (`get_nodes`).
3. Stop the **OpenThread Border Router add-on**, start the `otbr` pod, then import the dataset: `ot-ctl dataset set active <TLV>`, `ot-ctl ifconfig up`, `ot-ctl thread start`. `ot-ctl state` should become `router` and `ot-ctl neighbor table` list the existing Thread devices (no re-pairing needed).
4. Point the target Home Assistant at the new URLs (above). Disable the Matter/OTBR entries of the old Home Assistant, otherwise it keeps restarting its add-ons and two controllers fight over the same fabric/radio.
5. Zigbee is not part of this: ZHA/zigbee2mqtt stay on the CC2674P10.

#### K3s multus
```
helm repo add rke2-charts https://rke2-charts.rancher.io
helm repo update
# 1. CRDs first: a separate chart (the main chart ships none). Installs the NetworkAttachmentDefinition CRD and three whereabouts CRDs
helm upgrade --install multus-crd rke2-charts/rke2-multus-crd -n kube-system --version 4.3.118
# 2. Multus. Run from your workstation (it uses ~/.kube/config). Only when running on a node add: --kubeconfig /etc/rancher/k3s/k3s.yaml
helm upgrade --install multus rke2-charts/rke2-multus -n kube-system --values apps/network/multus/multus-values.yaml --version v4.3.118
# Then do the manual binary copy in apps/network/multus/README.md ("Required on k3s 1.35"), otherwise new pods cannot start
```

### Home Assistant
```
k apply -f apps/smart/hass/
```

### Code
```
k apply -f apps/dev/code/
```

### Jellyfin
```
k apply -f apps/media/jellyfin/
```

### RR
```
k apply -f apps/rr/namespace.yaml
k apply -f apps/rr/rr-media-volume+claim.yaml
```

### Homepage
```
k apply -f apps/interfaces/homepage/
```

### Homarr
```
k apply -f secrets/homarr.secret.yaml
k apply -f apps/rr/homarr/
```

### Bazarr
```
k apply -f secrets/bazarr-pg.secret.yaml
k apply -f apps/rr/bazarr/
```

### Seerr
```
k apply -f apps/rr/seerr/
```

### Prowlarr
```
k apply -f apps/rr/prowlarr/
```

### Radarr
```
k apply -f apps/rr/radarr/
```

### Sonarr
```
k apply -f apps/rr/sonarr/
```

### Qbittorrent
```
k apply -f apps/tools/qbittorrent/
```

### Monitoring
```
k create ns monitoring
```
### Prometheus
```
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

k apply -f secrets/grafana.secret.yaml

k apply -f apps/monitoring/prom-stack/prometheus-volume.yaml
k apply -f apps/monitoring/prom-stack/grafana-volume.yaml
k apply -f apps/monitoring/prom-stack/grafana-ingress.yaml
helm upgrade --install -n monitoring prom-stack prometheus-community/kube-prometheus-stack -f apps/monitoring/prom-stack/prometheus-values.yaml --version 75.12.0
```

### Immich (v3.2.4)
```
k create ns immich

k apply -f secrets/immich.secret.yaml

k apply -f apps/media/immich/ingress.yaml
k apply -f apps/media/immich/immich.yaml
k apply -f apps/media/immich/immich-cm.yaml

k apply -f apps/media/immich/volumes/
```

### Torrentio
```
k apply -f apps/media/torrentio/namespace.yaml
k apply -f apps/media/torrentio/torrentio.yaml
k apply -f apps/media/torrentio/ingress.yaml
```

### Apache Guacamole
```
k create ns guaca
k apply -f secrets/guaca.secret.yaml
k apply -f apps/admin/guaca/traefik-subpath-middleware.yaml
k apply -f apps/admin/guaca/guaca.yaml
```

### VaultWarden
```
helm repo add gabe565 https://charts.gabe565.com
helm repo update
k apply -f secrets/vaultwarden.secret.yaml
helm upgrade --install -n auth vaultwarden gabe565/vaultwarden --values apps/security/vaultwarden/vaultwarden-values.yaml --version 0.16.1
k apply -f apps/security/vaultwarden/ingress.yaml
```

### Kopia
```
k create ns backup
k apply -f apps/backup/kopia/app-volume.yaml

k apply -f apps/backup/kopia/apps-volume.yaml
k apply -f apps/backup/kopia/data-volume.yaml
k apply -f apps/backup/kopia/files-volume.yaml

k apply -f secrets/kopia.secret.yaml
k apply -f apps/backup/kopia/kopia.yaml
```

### Obsidian
```
k create ns office
k apply -f apps/office/obsidian/obsidian-volume.yaml
k apply -f apps/office/obsidian/obsidian.yaml
```

### Scrypted
```
helm repo add bryopsida https://bryopsida.github.io/helm
helm repo update
helm upgrade --install
```

<!--
### Appsmith
```
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm upgrade --install appsmith bitnami/appsmith -n appsmith --create-namespace -f apps/tools/appsmith/appsmith-values.insecure.yaml --version 4.0.0
``` -->
