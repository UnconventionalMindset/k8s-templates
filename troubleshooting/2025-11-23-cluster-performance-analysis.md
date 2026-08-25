# Cluster Performance Analysis Report

**Date**: 2025-11-23
**Issue**: Home Assistant unavailable at 192.168.31.233 and https://hass.umhomelab.com

## Executive Summary

Investigation revealed cascading failures caused by **memory pressure on node e2**, leading to PostgreSQL crashes that broke Authentik authentication and caused cluster-wide instability.

## Root Cause Analysis

### Primary Issue: Node e2 Memory Exhaustion

| Node | Memory Usage | Available |
|------|-------------|-----------|
| e2   | 6694Mi (84%) | ~1.4GB   |
| hs   | 5150Mi (64%) | ~2.9GB   |

Node e2 is running 50 pods including all critical services:
- PostgreSQL (database)
- Authentik (authentication)
- Traefik (reverse proxy)
- CoreDNS
- Home Assistant
- Immich

### Cascade of Failures

1. **Node e2 runs low on memory** → Linux OOM killer terminates pods
2. **PostgreSQL killed abruptly** → Database not properly shut down
3. **PostgreSQL restarts with WAL recovery** → Takes time, rejects connections
4. **Authentik can't connect to database** → Authentication fails
5. **Services behind Traefik inaccessible** → hass.umhomelab.com returns errors
6. **Constant pod restarts** → API server struggles, kubectl commands timeout

### Evidence

| Component | Restarts | Impact |
|-----------|----------|--------|
| PostgreSQL | 31 | Database unavailable during recovery |
| Authentik Worker | 364 | Can't process auth requests |
| Traefik | 18 | Routing disrupted |
| CoreDNS | 5 | DNS resolution failures |

PostgreSQL logs show:
```
database system was interrupted; last known up at 2025-11-23 15:38:06 UTC
database system was not properly shut down; automatic recovery in progress
```

## Performance Bottlenecks

### 1. Slow Authentik API Calls (High Impact)

From Authentik logs:
- `/api/v3/outposts/proxy/` - **1,300-1,400ms**
- `/api/v3/outposts/instances/` - **140-160ms**

These database-heavy queries suffer when PostgreSQL is under memory pressure.

### 2. No Database Connection Pooling (High Impact)

PostgreSQL stats:
- Active connections: 47
- Max connections: 100
- Idle connections: 34

Each request opens a new connection instead of reusing them.

### 3. Traefik in DEBUG Mode (Medium Impact)

```
--log.level=DEBUG
```

DEBUG logging adds overhead to every request.

### 4. Forward Auth on Every Request (Medium Impact)

Every request to protected services triggers:
1. Traefik → Authentik forward auth call
2. Authentik → PostgreSQL query
3. Return auth result

### 5. Critical Services Co-located (High Impact)

All services on node e2 fail together when memory pressure occurs.

## Memory Usage - Top Consumers on Node e2

| Pod | Memory |
|-----|--------|
| authentik-server | 587Mi |
| immich-server | 566Mi |
| postgres-0 | 551Mi |
| hass | 442Mi |
| authentik-worker | 439Mi |
| gitea | 234Mi |
| kopia | 231Mi |
| immich-machine-learning | 216Mi |

**Total (top 8 only)**: ~3,266Mi

## Recommendations

### Immediate Actions (Quick Wins)

1. **Change Traefik log level from DEBUG to INFO**
   - File: `apps/network/traefik/traefik-values.yaml` line 13
   - Change `level: DEBUG` to `level: INFO`
   - DEBUG logging adds overhead to every request

2. **Move PostgreSQL to node hs**
   - Node hs has 2.9GB free vs e2's 1.4GB
   - Add to postgres StatefulSet:
   ```yaml
   nodeSelector:
     kubernetes.io/hostname: hs
   ```

3. **Set memory requests/limits on critical pods**
   - Prevents OOM kills and allows better scheduling
   - Example for PostgreSQL:
   ```yaml
   resources:
     requests:
       memory: "512Mi"
     limits:
       memory: "1Gi"
   ```

### Caching & Performance Optimizations

4. **Add Traefik response compression**
   - Create a compress middleware:
   ```yaml
   apiVersion: traefik.io/v1alpha1
   kind: Middleware
   metadata:
     name: compress
     namespace: default
   spec:
     compress: {}
   ```
   - Add to IngressRoutes for static content services

5. **Deploy PgBouncer for database connection pooling**
   - Current: 47 connections, many idle
   - PgBouncer can reduce to ~10-20 actual connections
   - Reduces PostgreSQL memory usage and connection overhead

6. **Tune PostgreSQL memory settings**
   - Current settings are reasonable but could optimize:
   ```
   shared_buffers = 512MB (OK)
   work_mem = 16MB (OK)
   effective_cache_size = 4GB (high for 8GB node)
   ```
   - Consider reducing `effective_cache_size` to 2GB
   - Reduce `max_connections` from 100 to 50 (with PgBouncer)

7. **Configure Authentik caching**
   - Redis is already configured in `authentik-values.yaml`
   - Add session/cache TTL settings:
   ```yaml
   authentik:
     # ... existing config ...
     session:
       expiry: 86400  # 24 hours instead of default
     cache:
       timeout: 300   # 5 minutes
   ```

8. **Enable HTTP/2 in Traefik** (if not already)
   - Multiplexing reduces connection overhead
   - Already enabled on websecure entrypoint via TLS

9. **Add Traefik caching for static assets**
   - Use headers middleware to set cache-control:
   ```yaml
   apiVersion: traefik.io/v1alpha1
   kind: Middleware
   metadata:
     name: cache-headers
   spec:
     headers:
       customResponseHeaders:
         Cache-Control: "public, max-age=31536000"
   ```

10. **Scale Traefik to 2 replicas**
    - Current: 1 replica
    - Provides redundancy and load distribution
    - Add to traefik-values.yaml:
    ```yaml
    deployment:
      replicas: 2
    ```

### Infrastructure Improvements

11. **Spread workloads with pod anti-affinity**
    - Prevent critical services from co-locating:
    ```yaml
    affinity:
      podAntiAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchLabels:
                app: postgres
            topologyKey: kubernetes.io/hostname
    ```

12. **Add more RAM to nodes**
    - 8GB is tight for this workload
    - Consider 16GB+ for nodes running databases

13. **Implement monitoring alerts**
    - Alert on memory > 80%
    - Alert on pod restart count > 5 in 1 hour
    - Alert on database connection failures
    - Alert on request latency > 500ms

### Network Optimizations

14. **Review rate limiter settings**
    - Current: 100 avg, 200 burst
    - Local IPs (192.168.31.0/24) are excluded - good
    - Consider if rate limiting is needed for all requests

15. **Consider local DNS caching**
    - CoreDNS has restarted 5 times
    - Add node-local-dns for faster resolution

## Verification Steps

After implementing fixes, verify:

```bash
# Check node memory usage
kubectl top nodes

# Verify PostgreSQL stability
kubectl get pods -n db -w

# Test Authentik response times
kubectl logs -n auth -l app.kubernetes.io/name=authentik --tail=100 | grep runtime

# Test end-to-end latency
curl -w "Total: %{time_total}s\n" -k https://hass.umhomelab.com
```

## Current Service Status

As of analysis completion:

- **192.168.31.233** (Multus ipvlan): Working
- **192.168.31.251** (LoadBalancer): Working
- **https://hass.umhomelab.com**: Working (redirects to Authentik)

Note: Services may become unavailable again when memory pressure returns.

## Related Configuration Files

- Home Assistant: `apps/smart/hass/hass.yaml`
- Network Attachment: `default/lan-network` NetworkAttachmentDefinition (ipvlan on ens18)
- Authentik middleware: `auth/authentik` Middleware (forwardAuth)
