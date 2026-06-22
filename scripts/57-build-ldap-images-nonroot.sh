#!/usr/bin/env bash
# Build milvus-ldap-sync + milvus-ldap-auth as non-root (UID/GID 65000) and export tar.gz.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TAG_SYNC="${TAG_SYNC:-2.5.0}"
TAG_AUTH="${TAG_AUTH:-2.5.0}"
OUT_DIR="${OUT_DIR:-${ROOT}/artifacts/images}"
RUNTIME_UID=65000
RUNTIME_GID=65000

mkdir -p "$OUT_DIR"

echo "==> build milvus-ldap-sync-nonroot:${TAG_SYNC}"
docker build \
  --build-arg RUNTIME_UID="${RUNTIME_UID}" \
  --build-arg RUNTIME_GID="${RUNTIME_GID}" \
  -t "milvus-ldap-sync-nonroot:${TAG_SYNC}" \
  -f docker/milvus-ldap-sync/Dockerfile .

echo "==> build milvus-ldap-auth-nonroot:${TAG_AUTH}"
docker build \
  --build-arg RUNTIME_UID="${RUNTIME_UID}" \
  --build-arg RUNTIME_GID="${RUNTIME_GID}" \
  -t "milvus-ldap-auth-nonroot:${TAG_AUTH}" \
  -f docker/ldap-auth-extauthz/Dockerfile .

echo "==> alias tags (manifests / registry naming)"
docker tag "milvus-ldap-sync-nonroot:${TAG_SYNC}" "milvus-ldap-sync:${TAG_SYNC}"
docker tag "milvus-ldap-auth-nonroot:${TAG_AUTH}" "milvus-ldap-auth:${TAG_AUTH}"

echo "==> verify non-root"
docker run --rm --entrypoint id "milvus-ldap-sync-nonroot:${TAG_SYNC}"
docker run --rm --entrypoint id "milvus-ldap-auth-nonroot:${TAG_AUTH}"

echo "==> export tar.gz"
docker save "milvus-ldap-sync-nonroot:${TAG_SYNC}" | gzip > "${OUT_DIR}/milvus-ldap-sync-nonroot_${TAG_SYNC}.tar.gz"
docker save "milvus-ldap-auth-nonroot:${TAG_AUTH}" | gzip > "${OUT_DIR}/milvus-ldap-auth-nonroot_${TAG_AUTH}.tar.gz"

echo ""
echo "Done:"
ls -lh "${OUT_DIR}/milvus-ldap-sync-nonroot_${TAG_SYNC}.tar.gz" "${OUT_DIR}/milvus-ldap-auth-nonroot_${TAG_AUTH}.tar.gz"
echo ""
echo "Air-gap load:"
echo "  gunzip -c ${OUT_DIR}/milvus-ldap-sync-nonroot_${TAG_SYNC}.tar.gz | docker load"
echo "  gunzip -c ${OUT_DIR}/milvus-ldap-auth-nonroot_${TAG_AUTH}.tar.gz | docker load"
