#!/usr/bin/env bash
# Idempotent: create Milvus user "admin" and grant role admin (requires authorizationEnabled + root password).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-milvus}"
ROOT_PASSWORD="${MILVUS_ROOT_PASSWORD:-user}"
ADMIN_USER="${MILVUS_ADMIN_USER:-admin}"
ADMIN_PASSWORD="${MILVUS_ADMIN_PASSWORD:-user}"
JOB_NAME="milvus-native-rbac-bootstrap-$(date +%s)"

kubectl -n "$NAMESPACE" wait --for=condition=ready pod \
  -l 'app.kubernetes.io/name=milvus,component=proxy' --timeout=300s

PY_B64="$(base64 < "${SCRIPT_DIR}/milvus_bootstrap_native_rbac.py" | tr -d '\n')"

kubectl -n "$NAMESPACE" run "$JOB_NAME" --rm -i --restart=Never \
  --image=python:3.11-slim \
  --env "MILVUS_HOST=milvus" \
  --env "MILVUS_PORT=19530" \
  --env "MILVUS_ROOT_USER=root" \
  --env "MILVUS_ROOT_PASSWORD=${ROOT_PASSWORD}" \
  --env "MILVUS_ADMIN_USER=${ADMIN_USER}" \
  --env "MILVUS_ADMIN_PASSWORD=${ADMIN_PASSWORD}" \
  --command -- bash -c "set -euo pipefail
pip install -q 'pymilvus==2.5.0'
echo '${PY_B64}' | base64 -d > /tmp/milvus_bootstrap_native_rbac.py
python /tmp/milvus_bootstrap_native_rbac.py"

echo "Done."
