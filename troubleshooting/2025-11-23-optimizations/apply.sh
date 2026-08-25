#!/bin/bash

# Cluster Performance Optimizations Apply Script
# Date: 2025-11-23
#
# Usage:
#   ./apply.sh [--dry-run] [--step]
#
# Options:
#   --dry-run   Show what would be applied without making changes
#   --step      Pause after each change for confirmation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
STEP_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --step)
            STEP_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $1"
    else
        log_info "Running: $1"
        eval "$1"
    fi
}

pause_if_step() {
    if [ "$STEP_MODE" = true ] && [ "$DRY_RUN" = false ]; then
        read -p "Press Enter to continue or Ctrl+C to abort..."
    fi
}

echo "============================================"
echo "  Cluster Performance Optimizations"
echo "  Date: 2025-11-23"
echo "============================================"
echo ""

if [ "$DRY_RUN" = true ]; then
    log_warn "Running in DRY-RUN mode - no changes will be made"
    echo ""
fi

# Step 1: Apply middlewares
echo "Step 1: Applying Traefik middlewares..."
echo "----------------------------------------"
run_cmd "kubectl apply -f ${SCRIPT_DIR}/middlewares/compress.yaml"
run_cmd "kubectl apply -f ${SCRIPT_DIR}/middlewares/cache-headers.yaml"
run_cmd "kubectl apply -f ${SCRIPT_DIR}/middlewares/security-headers.yaml"
pause_if_step
echo ""

# Step 2: Apply resource limits
echo "Step 2: Applying resource limits to critical pods..."
echo "-----------------------------------------------------"
log_warn "This will cause pods to restart!"
run_cmd "kubectl patch statefulset postgres -n db --patch-file ${SCRIPT_DIR}/patches/02-postgres-resources.yaml"
run_cmd "kubectl patch deployment authentik-server -n auth --patch-file ${SCRIPT_DIR}/patches/03-authentik-server-resources.yaml"
run_cmd "kubectl patch deployment authentik-worker -n auth --patch-file ${SCRIPT_DIR}/patches/04-authentik-worker-resources.yaml"
run_cmd "kubectl patch deployment hass -n hass --patch-file ${SCRIPT_DIR}/patches/05-hass-resources.yaml"
pause_if_step
echo ""

# Step 3: Move PostgreSQL to node hs
echo "Step 3: Moving PostgreSQL to node hs..."
echo "---------------------------------------"
log_warn "This will cause PostgreSQL to restart and move to a different node!"
run_cmd "kubectl patch statefulset postgres -n db --patch-file ${SCRIPT_DIR}/patches/01-postgres-node-selector.yaml"
pause_if_step
echo ""

# Step 4: Upgrade Traefik with optimized values
echo "Step 4: Upgrading Traefik with optimized configuration..."
echo "---------------------------------------------------------"
log_info "This upgrades Traefik to use INFO logging and 2 replicas"
if [ "$DRY_RUN" = true ]; then
    run_cmd "helm upgrade traefik traefik/traefik -n default --values ${SCRIPT_DIR}/configs/traefik-values-optimized.yaml --dry-run"
else
    run_cmd "helm upgrade traefik traefik/traefik -n default --values ${SCRIPT_DIR}/configs/traefik-values-optimized.yaml"
fi
pause_if_step
echo ""

# Step 5: Apply PostgreSQL config
echo "Step 5: Applying PostgreSQL configuration..."
echo "--------------------------------------------"
run_cmd "kubectl apply -f ${SCRIPT_DIR}/patches/06-postgres-config.yaml"
echo ""

echo "============================================"
echo "  Optimizations Applied!"
echo "============================================"
echo ""
log_info "Next steps:"
echo "  1. Monitor pod restarts: kubectl get pods -A -w"
echo "  2. Check node memory: kubectl top nodes"
echo "  3. Test service latency: curl -w '%{time_total}s' -k https://hass.umhomelab.com"
echo ""
log_warn "Note: Authentik helm upgrade not included - run manually if needed:"
echo "  helm upgrade authentik authentik/authentik -n auth --values ${SCRIPT_DIR}/configs/authentik-values-optimized.yaml"
echo ""
