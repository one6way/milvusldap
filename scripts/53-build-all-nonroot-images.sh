#!/usr/bin/env bash
# Один раз на prep-стенде (с интернетом): базовые образы pull только если их нет локально,
# затем сборка всего non-root стека для values-kind-localpath.yaml / offline.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

pull_if_missing() {
  local img="$1"
  if docker image inspect "$img" >/dev/null 2>&1; then
    echo "skip pull (exists): $img"
  else
    echo "pull: $img"
    docker pull "$img"
  fi
}

echo "==> Базовые образы (только отсутствующие локально)"
pull_if_missing milvusdb/milvus:v2.5.0
pull_if_missing milvusdb/etcd:3.5.16-r1
pull_if_missing apachepulsar/pulsar:3.0.7
pull_if_missing minio/minio:RELEASE.2023-03-20T20-16-18Z
pull_if_missing milvusdb/milvus-config-tool:v0.1.2
pull_if_missing zilliz/attu:v2.5.10

echo "==> Инфраструктура K8s (local-path provisioner + helper pod busybox)"
pull_if_missing rancher/local-path-provisioner:v0.0.35
pull_if_missing busybox:1.36

echo "==> Сборка non-root образов зависимостей и Milvus"
docker build -t milvus-etcd-nonroot:3.5.16-r1 -f images/etcd-nonroot/Dockerfile images/etcd-nonroot
docker build -t milvus-pulsar-nonroot:3.0.7 -f images/pulsar-nonroot/Dockerfile images/pulsar-nonroot
docker build -t milvus-minio-nonroot:RELEASE.2023-03-20T20-16-18Z -f images/minio-nonroot/Dockerfile images/minio-nonroot
docker build -t milvus-config-tool-nonroot:v0.1.2 -f images/milvus-config-tool-nonroot/Dockerfile images/milvus-config-tool-nonroot
docker build -t milvus-nonroot:2.5.0 -f images/milvus-nonroot/Dockerfile images/milvus-nonroot

docker run --rm --entrypoint /usr/bin/id milvus-etcd-nonroot:3.5.16-r1
docker run --rm --entrypoint /usr/bin/id milvus-pulsar-nonroot:3.0.7
docker inspect milvus-minio-nonroot:RELEASE.2023-03-20T20-16-18Z --format 'minio user={{.Config.User}}'
docker run --rm milvus-nonroot:2.5.0 id

echo "==> Attu non-root"
./scripts/58-build-attu-nonroot-image.sh

echo "Готово. Дальше: ./scripts/50-collect-images.sh (без сети для Helm) и перенос artifacts/."
