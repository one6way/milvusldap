#!/usr/bin/env bash
# Изолированный контур: только локальный манифест (без https:// к GitHub).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="${MANIFEST:-$ROOT/manifests/local-path-storage.yaml}"

if [[ ! -f "$MANIFEST" ]]; then
  echo "ERROR: нет файла $MANIFEST" >&2
  exit 1
fi

kubectl apply -f "$MANIFEST"

kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || true

kubectl get sc
