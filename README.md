# K8s automations

### Kube router
```
k apply -f https://raw.githubusercontent.com/cloudnativelabs/kube-router/master/daemonset/kubeadm-kuberouter.yaml
```

### Metal LB
https://metallb.universe.tf/installation/
```
k apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml
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
k apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.18.2/cert-manager.crds.yaml
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --values=apps/security/cert-manager/cert-manager-values.yaml --version v1.18.2
```

### Traefik
```
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm upgrade --install traefik traefik/traefik --values=apps/network/traefik/traefik-values.yaml --version 37.0.0
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
helm upgrade --install -n db redis bitnami/redis -f secrets/redis-values.insecure.yaml --version 22.0.1
```

### Authentik
```
k apply -f secrets/authentik.secret.yaml
k apply -f apps/security/authentik/namespace.yaml
k apply -f apps/security/authentik/authentik-volume+claim.yaml
helm repo add goauthentik https://charts.goauthentik.io
helm repo update
k apply -f apps/network/traefik/middlewares/
k apply -f apps/security/authentik/ingress.yaml
helm upgrade --install authentik goauthentik/authentik -f apps/security/authentik/authentik-values.yaml -n auth --version 2025.6.4
```

### K8s dashboard
```
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm repo update
helm upgrade --install dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace dashboard -f apps/interfaces/k8s-dashboard/values.yaml --version 7.13.0

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

### Multus
Usual install (do not use now due to issue)
```
git clone https://github.com/k8snetworkplumbingwg/multus-cni.git
cd multus-cni/
cat ./deployments/multus-daemonset-thick.yml | k apply -f -
k apply -f apps/network/multus/multus-lan.yaml
```
Sometimes multus fails due to: https://github.com/k8snetworkplumbingwg/multus-cni/issues/1221
Current temporary fix in:
```
cd ~/homelab/k8s-templates/
k apply -f apps/network/multus/multus-daemonset-thick.yml
k apply -f apps/network/multus/multus-lan.yaml
```

#### K3s multus
```
helm repo add rke2-charts https://rke2-charts.rancher.io
helm repo update
helm upgrade --install multus rke2-charts/rke2-multus -n kube-system --kubeconfig /etc/rancher/k3s/k3s.yaml --values apps/network/multus/multus-values.yaml --version 4.2.202
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

### Jellyseerr
```
k apply -f apps/rr/jellyseerr/
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

### Immich
```
k create ns immich

k apply -f secrets/immich.secret.yaml

k apply -f apps/media/immich/ingress.yaml
k apply -f apps/media/immich/immich.yaml
k apply -f apps/media/immich/immich-cm.yaml

k apply -f apps/media/immich/volumes/
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
helm repo add gissilabs https://gissilabs.github.io/charts/
helm repo update
helm upgrade --install -n auth vaultwarden gissilabs/vaultwarden --values secrets/vaultwarden-values.insecure.yaml --version 1.2.5
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
