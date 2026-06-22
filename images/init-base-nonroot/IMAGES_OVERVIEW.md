# Nonroot Images Overview

Directory scope: `milfus-main/images`  
Export directory: `milfus-main/images/export`  
Policy: runtime user must be `65000:65000` for restricted Kubernetes security context.

## Image catalog

| Image tag | Dockerfile path | Base source (`FROM`) | Runtime user | Notes |
|---|---|---|---|---|
| `milvus-nonroot:latest` | `images/milvus-nonroot/Dockerfile` | `milvusdb/milvus:v2.5.0` | `65000:65000` | Creates/chowns Milvus data/config dirs. |
| `etcd-nonroot:latest` | `images/etcd-nonroot/Dockerfile` | `milvusdb/etcd:3.5.16-r1` | `65000:65000` | Prepares `/bitnami` and etcd data path. |
| `minio-nonroot:latest` | `images/minio-nonroot/Dockerfile` | `minio/minio:RELEASE.2023-03-20T20-16-18Z` | `65000:65000` | Prepares `/data` and `/minio_data`. |
| `pulsar-nonroot:latest` | `images/pulsar-nonroot/Dockerfile` | `apachepulsar/pulsar:3.0.7` | `65000:65000` | Prepares `/pulsar` dirs. |
| `attu-nonroot:latest` | `images/attu-nonroot/Dockerfile` | `zilliz/attu:v2.5.10` | `65000:65000` | Chowns `/app` for nonroot runtime. |
| `milvus-config-tool-nonroot:latest` | `images/milvus-config-tool-nonroot/Dockerfile` | `milvusdb/milvus-config-tool:v0.1.2` | `65000:65000` | Minimal hardening only (`USER`). |
| `init-base-nonroot:latest` | `images/init-base-nonroot/Dockerfile` | `alpine:3.20` | `65000:65000` | Utility image (`bash`, `curl`, `dig`, `nslookup`, `nc`, `ip`, etc). |
| `jaeger-nonroot:latest` | `images/jaeger-nonroot/Dockerfile` | `jaegertracing/all-in-one:1.57` | `65000:65000` | Build step uses root for `chown`, runtime is nonroot. |
| `otel-collector-nonroot:latest` | `images/otel-collector-nonroot/Dockerfile` | `otel/opentelemetry-collector-contrib:0.109.0` | `65000:65000` | Collector config should be mounted by ConfigMap. |
| `envoy-nonroot:latest` | `images/envoy-nonroot/Dockerfile` | `envoyproxy/envoy:v1.31.2` | `65000:65000` | Minimal nonroot wrapper image. |

## Build and export pattern

From repo root (`/Users/one6way/Documents/kub_help`):

```bash
# Build
docker build -t <name>:latest -f "milfus-main/images/<dir>/Dockerfile" "milfus-main/images/<dir>"

# Export (offline)
docker save <name>:latest | gzip > "milfus-main/images/export/<name>-latest.tar.gz"
```

Example:

```bash
docker build -t envoy-nonroot:latest \
  -f "milfus-main/images/envoy-nonroot/Dockerfile" \
  "milfus-main/images/envoy-nonroot"

docker save envoy-nonroot:latest | gzip > \
  "milfus-main/images/export/envoy-nonroot-latest.tar.gz"
```

## Quick validation checklist

```bash
# 1) Runtime user
docker image inspect <name>:latest --format '{{.Config.User}}'

# 2) Archive exists
ls -lh "milfus-main/images/export/<name>-latest.tar.gz"

# 3) Optional smoke run (for shell-capable images)
docker run --rm --entrypoint /bin/sh <name>:latest -c 'id'
```

## Current exported archives (known)

- `envoy-nonroot-latest.tar.gz`
- `jaeger-nonroot-latest.tar.gz`
- `otel-collector-nonroot-latest.tar.gz`
- `init-base-nonroot-latest.tar.gz`
- `milvus-config-tool-nonroot-latest.tar.gz`
- `jaeger-otel-nonroot-latest.tar.gz` (combined archive with two images)

## Tagging recommendation

- Keep `latest` for quick local checks.
- For deployment and rollback in offline environments, publish immutable tags too:
  - `vX.Y.Z`, or
  - `YYYYMMDD-<gitsha>`
- In Helm/Kustomize manifests, pin immutable tags.
