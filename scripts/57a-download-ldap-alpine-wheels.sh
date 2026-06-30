#!/usr/bin/env bash
# Скачать/собрать musllinux wheels для Alpine Python 3.11 (offline build в закрытом контуре).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BASE_IMAGE="${BASE_IMAGE:-python:3.11-alpine}"
SYNC_WHEELS="${SYNC_WHEELS:-${ROOT}/docker/milvus-ldap-sync/wheels-alpine}"
AUTH_WHEELS="${AUTH_WHEELS:-${ROOT}/docker/ldap-auth-extauthz/wheels-alpine}"

mkdir -p "$SYNC_WHEELS" "$AUTH_WHEELS"

echo "==> BASE_IMAGE: $BASE_IMAGE"
echo "==> sync wheels -> $SYNC_WHEELS"

docker run --rm -v "${SYNC_WHEELS}:/wheels" "$BASE_IMAGE" sh -ec '
  apk add --no-cache gcc g++ musl-dev libffi-dev openssl-dev python3-dev
  pip install --upgrade pip wheel
  pip wheel --no-cache-dir pymilvus==2.5.0 ldap3==2.9.1 -w /wheels
  echo "sync wheels:"
  ls -lh /wheels
'

echo "==> auth wheels -> $AUTH_WHEELS"
docker run --rm -v "${AUTH_WHEELS}:/wheels" "$BASE_IMAGE" sh -ec '
  pip wheel --no-cache-dir ldap3==2.9.1 -w /wheels
  ls -lh /wheels
'

PACK="${ROOT}/artifacts/ldap-alpine-wheels.tar.gz"
mkdir -p "${ROOT}/artifacts"
tar -czf "$PACK" -C "${ROOT}/docker" milvus-ldap-sync/wheels-alpine ldap-auth-extauthz/wheels-alpine

echo ""
echo "Done."
echo "  sync:  $SYNC_WHEELS ($(find "$SYNC_WHEELS" -name '*.whl' | wc -l | tr -d ' ') whl)"
echo "  auth:  $AUTH_WHEELS"
echo "  pack:  $PACK"
echo ""
echo "На закрытом контуре:"
echo "  tar -xzf ldap-alpine-wheels.tar.gz -C docker/"
echo "  BASE_IMAGE=alpine-python:3.11.9 VARIANT=alpine ./scripts/57-build-ldap-images-nonroot.sh"
