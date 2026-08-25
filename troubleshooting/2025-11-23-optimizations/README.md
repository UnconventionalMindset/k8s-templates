# Cluster Performance Optimizations

**Date**: 2025-11-23

This folder contains all the changes recommended in the performance analysis report.

## Structure

```
2025-11-23-optimizations/
├── patches/           # kubectl patch commands as YAML
├── middlewares/       # New Traefik middlewares
├── configs/           # Updated configuration files
└── apply.sh          # Script to apply all changes
```

## How to Apply

Review each change, then run:

```bash
# Dry run first
./apply.sh --dry-run

# Apply all changes
./apply.sh
```

Or apply individually as described in each file.

## Changes Included

### Immediate (High Impact)
1. Traefik log level: DEBUG → INFO
2. PostgreSQL node selector: move to node hs
3. Memory limits for critical pods

### Caching & Performance
4. Compression middleware
5. Cache headers middleware
6. Traefik 2 replicas
7. Authentik session caching

### Infrastructure
8. Pod anti-affinity rules
