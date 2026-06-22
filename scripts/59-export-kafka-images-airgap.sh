#!/usr/bin/env bash
# Экспорт образов Bitnami Kafka + Zookeeper для air-gap (встроенный subchart Milvus).
# Если Kafka уже в корпоративном registry — см. docs/kafka/IMAGES_AND_REGISTRY.md (сценарий A/B).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${OUT_DIR:-${ROOT}/artifacts/images}"

KAFKA_IMAGE="${KAFKA_IMAGE:-bitnami/kafka:3.1.0-debian-10-r52}"
ZK_IMAGE="${ZK_IMAGE:-bitnami/zookeeper:3.8.0-debian-10-r63}"

kafka_tag="${KAFKA_IMAGE##*:}"
zk_tag="${ZK_IMAGE##*:}"
KAFKA_TAR="${OUT_DIR}/bitnami-kafka_${kafka_tag}.tar.gz"
ZK_TAR="${OUT_DIR}/bitnami-zookeeper_${zk_tag}.tar.gz"

mkdir -p "$OUT_DIR"

echo "==> pull $KAFKA_IMAGE"
docker pull "$KAFKA_IMAGE"

echo "==> pull $ZK_IMAGE"
docker pull "$ZK_IMAGE"

echo "==> export"
docker save "$KAFKA_IMAGE" | gzip > "$KAFKA_TAR"
docker save "$ZK_IMAGE" | gzip > "$ZK_TAR"

ls -lh "$KAFKA_TAR" "$ZK_TAR"
echo ""
echo "Положите в air-gap пакет или пересоберите:"
echo "  ./scripts/81-export-ldap-airgap-delivery.sh"
