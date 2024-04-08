# node-feature-discovery

kubectl apply -k https://github.com/kubernetes-sigs/node-feature-discovery/deployment/overlays/default?ref=v0.13.2

# cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.yaml

# FACL
setfacl -R -m u:1000:rwx,g:1000:rwx .