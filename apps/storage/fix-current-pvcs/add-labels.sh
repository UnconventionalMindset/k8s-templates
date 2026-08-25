#!/bin/bash
set -e

echo "=== Adding Labels to Existing PVs ==="
echo ""
echo "This will add labels to prevent wrong PVC bindings."
echo "This is SAFE - it doesn't affect running pods."
echo ""

# Function to add labels
label_pv() {
  local pv_name=$1
  local app=$2
  local type=$3

  echo "Labeling $pv_name (app=$app, type=$type)..."
  kubectl label pv "$pv_name" \
    app="$app" \
    type="$type" \
    storage=nfs \
    managed-by=manual \
    --overwrite
}

# Jellyfin (fix the swap!)
echo "--- Jellyfin ---"
label_pv "jellyfin-cache-nfs" "jellyfin" "cache"
label_pv "jellyfin-metadata-nfs" "jellyfin" "metadata"
label_pv "jellyfin-config-nfs" "jellyfin" "config"
label_pv "jellyfin-media-nfs" "jellyfin" "media"

# Home Assistant
echo "--- Home Assistant ---"
label_pv "hass-nfs" "hass" "config"

# Immich
echo "--- Immich ---"
label_pv "uploads-immich-nfs" "immich" "uploads"
label_pv "backups-immich-nfs" "immich" "backups"
label_pv "encoded-videos-immich-nfs" "immich" "encoded-videos"

# Homarr
echo "--- Homarr ---"
label_pv "homarr-config-nfs" "homarr" "config"

# Bazarr
echo "--- Bazarr ---"
label_pv "bazarr-config-nfs" "bazarr" "config"

# Jellyseerr
echo "--- Jellyseerr ---"
label_pv "jellyseerr-config-nfs" "jellyseerr" "config"

# Code Server
echo "--- Code Server ---"
label_pv "code-config-nfs" "code-server" "config"
label_pv "code-j-config-nfs" "code-jupyter" "config"

# Grafana
echo "--- Grafana ---"
label_pv "grafana-app-nfs" "grafana" "data"

# Kopia
echo "--- Kopia ---"
label_pv "kopia-app-nfs" "kopia" "config"
label_pv "kopia-apps-nfs" "kopia" "apps-backup"
label_pv "kopia-data-nfs" "kopia" "data-backup"
label_pv "kopia-files-nfs" "kopia" "files-backup"

# Authentik
echo "--- Authentik ---"
label_pv "authentik-media-nfs" "authentik" "media"

# Gitea
echo "--- Gitea ---"
label_pv "gitea-app-nfs" "gitea" "data"

echo ""
echo "✅ Labels added!"
echo ""
echo "Verify with:"
echo "  kubectl get pv --show-labels"
echo ""
echo "Next steps:"
echo "  1. Update PVC files to add selectors (see example-pvc-with-selector.yaml)"
echo "  2. For wrongly-bound PVCs, recreate them (see README.md)"
echo ""
echo "Current PV-PVC bindings:"
kubectl get pv -o custom-columns=\
NAME:.metadata.name,\
CLAIM:.spec.claimRef.name,\
APP:.metadata.labels.app,\
TYPE:.metadata.labels.type
