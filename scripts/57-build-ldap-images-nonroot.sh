#!/usr/bin/env bash
# Build milvus-ldap-sync + milvus-ldap-auth as non-root (UID/GID 65000) and export tar.gz.
# VARIANT=alpine  — musl / Alpine (закрытый контур, wheels-alpine/)
# VARIANT=debian  — python:3.11-slim (prep, default)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TAG_SYNC="${TAG_SYNC:-2.5.0}"
TAG_AUTH="${TAG_AUTH:-2.5.0}"
OUT_DIR="${OUT_DIR:-${ROOT}/artifacts/images}"
RUNTIME_UID=65000
RUNTIME_GID=65000
VARIANT="${VARIANT:-debian}"
BASE_IMAGE="${BASE_IMAGE:-}"

case "$VARIANT" in
  alpine)
    SYNC_DF="docker/milvus-ldap-sync/Dockerfile.alpine"
    AUTH_DF="docker/ldap-auth-extauthz/Dockerfile.alpine"
    BASE_IMAGE="${BASE_IMAGE:-python:3.11-alpine}"
    if [[ ! -d docker/milvus-ldap-sync/wheels-alpine ]] || [[ -z "$(ls -A docker/milvus-ldap-sync/wheels-alpine/*.whl 2>/dev/null)" ]]; then
      echo "ERROR: missing docker/milvus-ldap-sync/wheels-alpine/*.whl" >&2
      echo "Run: ./scripts/57a-download-ldap-alpine-wheels.sh" >&2
      exit 1
    fi
    ;;
  debian)
    SYNC_DF="docker/milvus-ldap-sync/Dockerfile"
    AUTH_DF="docker/ldap-auth-extauthz/Dockerfile"
  ;;
  *)
    echo "ERROR: VARIANT must be alpine or debian (got: $VARIANT)" >&2
    exit 1
    ;;
esac

mkdir -p "$OUT_DIR"

build_args=(--build-arg "RUNTIME_UID=${RUNTIME_UID}" --build-arg "RUNTIME_GID=${RUNTIME_GID}")
if [[ -n "$BASE_IMAGE" ]]; then
  build_args+=(--build-arg "BASE_IMAGE=${BASE_IMAGE}")
fi

echo "==> VARIANT=${VARIANT} BASE_IMAGE=${BASE_IMAGE:-<dockerfile default>}"
echo "==> build milvus-ldap-sync-nonroot:${TAG_SYNC}"
docker build "${build_args[@]}" \
  -t "milvus-ldap-sync-nonroot:${TAG_SYNC}" \
  -f "$SYNC_DF" .

echo "==> build milvus-ldap-auth-nonroot:${TAG_AUTH}"
docker build "${build_args[@]}" \
  -t "milvus-ldap-auth-nonroot:${TAG_AUTH}" \
  -f "$AUTH_DF" .

echo "==> alias tags (manifests / registry naming)"
docker tag "milvus-ldap-sync-nonroot:${TAG_SYNC}" "milvus-ldap-sync:${TAG_SYNC}"
docker tag "milvus-ldap-auth-nonroot:${TAG_AUTH}" "milvus-ldap-auth:${TAG_AUTH}"

echo "==> verify non-root + imports"
docker run --rm --entrypoint id "milvus-ldap-sync-nonroot:${TAG_SYNC}"
docker run --rm --entrypoint id "milvus-ldap-auth-nonroot:${TAG_AUTH}"
docker run --rm --entrypoint python "milvus-ldap-sync-nonroot:${TAG_SYNC}" -c \
  "import ldap3, pymilvus; from pymilvus import MilvusClient; print('sync imports OK', pymilvus.__version__)"
docker run --rm --entrypoint python "milvus-ldap-auth-nonroot:${TAG_AUTH}" -c \
  "import ldap3; print('auth imports OK', ldap3.__version__)"

echo "==> export tar.gz"
docker save "milvus-ldap-sync-nonroot:${TAG_SYNC}" | gzip > "${OUT_DIR}/milvus-ldap-sync-nonroot_${TAG_SYNC}.tar.gz"
docker save "milvus-ldap-auth-nonroot:${TAG_AUTH}" | gzip > "${OUT_DIR}/milvus-ldap-auth-nonroot_${TAG_AUTH}.tar.gz"

echo ""
echo "Done:"
ls -lh "${OUT_DIR}/milvus-ldap-sync-nonroot_${TAG_SYNC}.tar.gz" "${OUT_DIR}/milvus-ldap-auth-nonroot_${TAG_AUTH}.tar.gz"
echo ""
echo "Offline load:"
echo "  gunzip -c ${OUT_DIR}/milvus-ldap-sync-nonroot_${TAG_SYNC}.tar.gz | docker load"
echo "  gunzip -c ${OUT_DIR}/milvus-ldap-auth-nonroot_${TAG_AUTH}.tar.gz | docker load"
