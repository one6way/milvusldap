#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-milvus}"
SERVICE="${SERVICE:-milvus}"

kubectl -n "$NAMESPACE" port-forward "svc/${SERVICE}" 19530:19530 9091:9091 >/tmp/milvus-port-forward.log 2>&1 &
PF_PID=$!

cleanup() {
  kill "$PF_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

sleep 5

curl -sf http://127.0.0.1:9091/healthz
echo
echo "Milvus health endpoint is OK"

if nc -z 127.0.0.1 19530; then
  echo "Milvus gRPC port 19530 is reachable"
else
  echo "Milvus gRPC port 19530 is NOT reachable"
  exit 1
fi
