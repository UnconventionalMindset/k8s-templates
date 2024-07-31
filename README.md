# K8s automations

### Kube router
```
k apply -f https://raw.githubusercontent.com/cloudnativelabs/kube-router/master/daemonset/kubeadm-kuberouter.yaml
```

### Metal LB
 https://metallb.universe.tf/installation/
```
k apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.3/config/manifests/metallb-native.yaml
k apply -f apps/admin/ipaddress_pools.yaml
```

### Cert Manager
```
k apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.crds.yaml
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --values=apps/security/cert-manager/values.yaml --version v1.14.5
```

### Traefik
```
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm upgrade --install traefik traefik/traefik --values=apps/network/traefik/traefik-values.yaml
k apply -f apps/network/traefik/ingress.yaml
```

### Further Traefik
k apply -f apps/network/traefik/skip-ssl.yaml
k apply -f apps/network/traefik/reverse-proxy/nas-ingress.yaml
k apply -f apps/network/traefik/reverse-proxy/proxmox-hs-ingress.yaml
k apply -f apps/network/traefik/reverse-proxy/proxmox-n1-ingress.yaml
k apply -f apps/network/traefik/reverse-proxy/proxmox-n2-ingress.yaml
k apply -f apps/network/traefik/reverse-proxy/zigbee-controller-ingress.yaml

### Longhorn
```
k apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml
k apply -f apps/admin/ingress.yaml
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
kubectl describe certificaterequest umhomelab-com-1 -n default
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
k apply -f apps/storage/postgres/secret.yaml
k apply -f apps/storage/postgres/postgres.yaml
k apply -f apps/storage/postgres/postgres14.yaml
```

### Authentik
```
k apply -f apps/security/authentik/namespace.yaml
k apply -f apps/security/authentik/authentik-volume+claim.yaml
helm repo add goauthentik https://charts.goauthentik.io
helm repo update
helm upgrade --install authentik goauthentik/authentik -f apps/security/authentik-values.yaml -n auth --version 2024.6.1
k apply -f apps/network/traefik/middlewares/
k apply -f apps/security/authentik/ingress.yaml
```

### K8s dashboard
```
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm repo update
helm upgrade --install dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace dashboard -f apps/interfaces/k8s-dashboard/values.yaml --version 7.3.0

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

### Dev plugin
```
k apply -f apps/smart/generic-device-plugin/
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

cd ~/homelab/k8s-templates/
k apply -f apps/network/multus/multus-lan.yaml
```
Sometimes multus fails due to: https://github.com/k8snetworkplumbingwg/multus-cni/issues/1221
Current temporary fix in:
```
k apply -f apps/network/multus/multus-lan.yaml
k apply -f apps/network/multus/multus-daemonset-thick.yml
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
k apply -f apps/media/rr/namespace.yaml
k apply -f apps/media/rr/rr-media-volume+claim.yaml
```

### Homepage
```
k apply -f apps/interfaces/homepage/
```

### Homarr
```
k apply -f secrets/homarr.secret.yaml
k apply -f apps/media/rr/homarr/
```

### Bazarr
```
k apply -f secrets/bazarr-pg14.secret.yaml
k apply -f apps/media/rr/bazarr/
```

### Jellyseerr
```
k apply -f apps/media/rr/jellyseerr/
```

### Prowlarr
```
k apply -f apps/media/rr/prowlarr/
```

### Radarr
```
k apply -f apps/media/rr/radarr/
```

### Sonarr
```
k apply -f apps/media/rr/sonarr/
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
helm upgrade --install -n monitoring prom-stack prometheus-community/kube-prometheus-stack -f apps/monitoring/prom-stack/prometheus-values.yaml
```

### Redis
```
k apply -f apps/storage/redis/volume.yaml
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm upgrade --install -n db redis bitnami/redis -f secrets/redis-values.insecure.yaml
```

### Immich
```
k create ns immich

k apply -f secrets/immich.insecure.yaml

k apply -f apps/media/immich/photos-volume.yaml
k apply -f apps/media/immich/ingress.yaml
k apply -f apps/media/immich/immich.yaml
```

### Apache Guacamole
```
k create ns guaca
k apply -f secrets/guaca.secret.yaml
k apply -f apps/admin/guaca/guaca.yaml
```

### VaultWarden
```
helm repo add gissilabs https://gissilabs.github.io/charts/
helm repo update
helm upgrade --install -n auth vaultwarden gissilabs/vaultwarden --values secrets/vaultwarden-values.yaml
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