#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-milvus-local}"
CONFIG="${KIND_CONFIG:-$ROOT/kind/kind-config-milvus-local.yaml}"

if kind get clusters 2>/dev/null | rg -x "$CLUSTER_NAME" >/dev/null 2>&1; then
  echo "kind cluster '$CLUSTER_NAME' already exists"
  exit 0
fi

if [[ -f "$CONFIG" ]]; then
  echo "Creating kind cluster with config: $CONFIG (NodePort → localhost для macOS/Docker Desktop)"
  kind create cluster --name "$CLUSTER_NAME" --config "$CONFIG"
else
  kind create cluster --name "$CLUSTER_NAME"
fi
kubectl cluster-info
