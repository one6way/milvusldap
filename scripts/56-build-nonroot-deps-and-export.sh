#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUT_DIR:-/Users/one6way/Documents/kub_help/milvus-delivery/k8s/images}"

mkdir -p "$OUT_DIR"

docker build -t milvus-etcd-nonroot:3.5.16-r1 -f images/etcd-nonroot/Dockerfile images/etcd-nonroot
docker build -t milvus-pulsar-nonroot:3.0.7 -f images/pulsar-nonroot/Dockerfile images/pulsar-nonroot
docker build -t milvus-minio-nonroot:RELEASE.2023-03-20T20-16-18Z -f images/minio-nonroot/Dockerfile images/minio-nonroot
docker build -t milvus-config-tool-nonroot:v0.1.2 -f images/milvus-config-tool-nonroot/Dockerfile images/milvus-config-tool-nonroot

# Validate runtime user
docker run --rm --entrypoint /usr/bin/id milvus-etcd-nonroot:3.5.16-r1
docker run --rm --entrypoint /usr/bin/id milvus-pulsar-nonroot:3.0.7
docker run --rm --entrypoint /usr/bin/id milvus-minio-nonroot:RELEASE.2023-03-20T20-16-18Z
docker image inspect milvus-config-tool-nonroot:v0.1.2 --format 'config-tool user={{.Config.User}}'

# Export tar.gz archives
docker save milvus-etcd-nonroot:3.5.16-r1 | gzip > "${OUT_DIR}/milvus-etcd-nonroot_3.5.16-r1.tar.gz"
docker save milvus-pulsar-nonroot:3.0.7 | gzip > "${OUT_DIR}/milvus-pulsar-nonroot_3.0.7.tar.gz"
docker save milvus-minio-nonroot:RELEASE.2023-03-20T20-16-18Z | gzip > "${OUT_DIR}/milvus-minio-nonroot_RELEASE.2023-03-20T20-16-18Z.tar.gz"
docker save milvus-config-tool-nonroot:v0.1.2 | gzip > "${OUT_DIR}/milvus-config-tool-nonroot_v0.1.2.tar.gz"

echo "Non-root dependency images built and exported to: ${OUT_DIR}"
