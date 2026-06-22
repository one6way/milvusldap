# init-base-nonroot cheat sheet

Image: `init-base-nonroot:latest`  
Runtime user: `65000:65000`

## Run locally

```bash
docker run --rm -it --entrypoint /bin/sh init-base-nonroot:latest
```

## Basic checks

```bash
# Who am I
id

# Tool paths
command -v nc dig nslookup curl ip ping traceroute
```

## DNS checks

```bash
# Resolve via cluster DNS/search domain
nslookup kubernetes.default.svc

# Query specific DNS server
dig @10.96.0.10 milvus.default.svc.cluster.local +short
```

## TCP port checks

```bash
# Check connectivity to host:port (3s timeout)
nc -zvw3 milvus.default.svc 19530

# Check MinIO API
nc -zvw3 minio.default.svc 9000
```

## HTTP checks

```bash
# Health endpoint
curl -fsS http://otel-collector.default.svc:13133/ || echo "unhealthy"

# Jaeger UI (headers only)
curl -I http://jaeger-query.default.svc:16686/
```

## Network/route checks

```bash
# Interfaces and routes
ip addr
ip route

# Quick reachability
ping -c 3 minio.default.svc
traceroute -m 5 minio.default.svc
```

## Kubernetes Job one-liner example

```bash
kubectl -n default run init-netcheck \
  --image=init-base-nonroot:latest \
  --restart=Never \
  --rm -it \
  -- /bin/sh -c 'nslookup kubernetes.default.svc && nc -zvw3 milvus.default.svc 19530'
```

## Notes

- `nc` is OpenBSD netcat (`/usr/bin/nc`).
- For offline clusters, preload the image on every node or mirror it to `{{ INTERNAL_REGISTRY }}`.
- Prefer fixed version tags in production manifests; keep `latest` for quick local smoke checks.
