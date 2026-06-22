#!/usr/bin/env bash
# Только когда нужно обновить subchart'ы Milvus с репозиториев (интернет).
# В offline и для повседневной работы НЕ вызывать — в chart/milvus/charts/ уже vendored-копии.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
helm repo add bitnami "https://charts.bitnami.com/bitnami" 2>/dev/null || true
helm repo add milvus "https://zilliztech.github.io/milvus-helm" 2>/dev/null || true
helm repo add apache-pulsar "https://pulsar.apache.org/charts" 2>/dev/null || true
helm repo update
helm dependency update chart/milvus
echo "Обновлены зависимости в chart/milvus. Зафиксируйте изменения в Git при необходимости."
