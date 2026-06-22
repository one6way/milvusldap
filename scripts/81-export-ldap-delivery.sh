#!/usr/bin/env bash
# Собрать единый каталог для переноса в закрытый контур (исходники + tar.gz образов).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DELIVERY_DIR="${DELIVERY_DIR:-${ROOT}/../milvus-ldap-delivery}"
KUB_HELP="${KUB_HELP:-$(cd "$ROOT/.." && pwd)}"
COPY_MODE="${COPY_MODE:-link}"   # link | copy

need() { command -v "$1" >/dev/null || { echo "ERROR: missing: $1" >&2; exit 1; }; }
need rsync
need shasum

mkdir -p "$DELIVERY_DIR"/{images,source}

copy_or_link() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -f "$dst" ]]; then
    echo "skip (exists): $(basename "$dst")"
    return 0
  fi
  if [[ ! -f "$src" ]]; then
    echo "WARN: missing source: $src" >&2
    return 1
  fi
  if [[ "$COPY_MODE" == "link" ]]; then
    ln "$src" "$dst" 2>/dev/null || cp -p "$src" "$dst"
  else
    cp -p "$src" "$dst"
  fi
  echo "ok: $(basename "$dst")"
}

ISPR="${ROOT}/images/ispravleno"
EXPORT="${ROOT}/images/export"
ART="${ROOT}/artifacts/images"
DELIV_IMAGES="${KUB_HELP}/milvus-delivery/k8s/images"

echo "==> Delivery dir: $DELIVERY_DIR"
echo "==> Images"

copy_image() {
  local name="$1" p1="$2" p2="${3:-}"
  local src=""
  [[ -f "$p1" ]] && src="$p1"
  [[ -z "$src" && -n "$p2" && -f "$p2" ]] && src="$p2"
  if [[ -z "$src" ]]; then
    echo "WARN: missing: $name" >&2
    MISSING=$((MISSING + 1))
    return 1
  fi
  copy_or_link "$src" "$DELIVERY_DIR/images/$name"
}

MISSING=0
copy_image "milvus-nonroot_2.5.0.tar.gz" \
  "${ISPR}/milvus-nonroot-2.5.0.tar.gz" "${DELIV_IMAGES}/milvus-nonroot_2.5.0.tar.gz" || true
copy_image "attu-nonroot_2.5.10.tar.gz" \
  "${ISPR}/attu-nonroot-2.5.10.tar.gz" "" || true
copy_image "milvus-etcd-nonroot_3.5.16-r1.tar.gz" \
  "${ISPR}/milvus-etcd-nonroot-3.5.16-r1.tar.gz" "${DELIV_IMAGES}/milvus-etcd-nonroot_3.5.16-r1.tar.gz" || true
copy_image "milvus-minio-nonroot_RELEASE.2023-03-20T20-16-18Z.tar.gz" \
  "${ISPR}/milvus-minio-nonroot-RELEASE.2023-03-20T20-16-18Z.tar.gz" "${DELIV_IMAGES}/milvus-minio-nonroot_RELEASE.2023-03-20T20-16-18Z.tar.gz" || true
copy_image "milvus-pulsar-nonroot_3.0.7.tar.gz" \
  "${ISPR}/milvus-pulsar-nonroot-3.0.7.tar.gz" "${DELIV_IMAGES}/milvus-pulsar-nonroot_3.0.7.tar.gz" || true
copy_image "envoy-nonroot_v1.31.2.tar.gz" \
  "${EXPORT}/envoy-nonroot-latest.tar.gz" "" || true
copy_image "milvus-config-tool-nonroot_v0.1.2.tar.gz" \
  "${EXPORT}/milvus-config-tool-nonroot-latest.tar.gz" "${DELIV_IMAGES}/milvus-config-tool-nonroot_v0.1.2.tar.gz" || true
copy_image "milvus-ldap-sync-nonroot_2.5.0.tar.gz" \
  "${ART}/milvus-ldap-sync-nonroot_2.5.0.tar.gz" "" || true
copy_image "milvus-ldap-auth-nonroot_2.5.0.tar.gz" \
  "${ART}/milvus-ldap-auth-nonroot_2.5.0.tar.gz" "" || true

# Kafka (опционально): artifacts/images/bitnami-kafka_*.tar.gz после scripts/59-export-kafka-images.sh
# Если Kafka в корпоративном registry — tar не нужен, см. docs/kafka/IMAGES_AND_REGISTRY.md
for f in "${ART}"/bitnami-kafka_*.tar.gz "${ART}"/bitnami-zookeeper_*.tar.gz; do
  [[ -f "$f" ]] || continue
  copy_or_link "$f" "$DELIVERY_DIR/images/$(basename "$f")" || true
done

echo "==> Source tree"
rsync -a --delete \
  --exclude '.git/' \
  --exclude '.DS_Store' \
  --exclude 'artifacts/images/' \
  --exclude 'images/export/' \
  --exclude 'images/ispravleno/' \
  --exclude 'images/init-base-nonroot/wheels/' \
  --exclude 'milvus-delivery-bundle*.tar.gz' \
  "$ROOT/" "$DELIVERY_DIR/source/"

echo "==> Docs"
for f in START_HERE.md CORP_LDAP_DEPLOYMENT_CHECKLIST.md LDAP_MILVUS_TEST_PROTOCOL.md \
  IB_TZ_COMPLIANCE_ARGUMENTATION.md ISOLATED_INSTALL.md \
  MILVUS_PULSAR_TO_KAFKA_MIGRATION.md KAFKA_IMAGES_AND_REGISTRY.md; do
  [[ -f "$ROOT/$f" ]] && cp -p "$ROOT/$f" "$DELIVERY_DIR/"
done
rsync -a "$ROOT/docs/kafka/" "$DELIVERY_DIR/docs/kafka/"
rsync -a "$ROOT/docs/architecture/" "$DELIVERY_DIR/docs/architecture/"

mkdir -p "$DELIVERY_DIR/images/kafka"
cat > "$DELIVERY_DIR/images/kafka/README.md" << 'KAFKAEOF'
# Kafka образы (опционально)

Документация: `docs/kafka/` (без образов в Git).

- **Корпоративный Kafka** → tar.gz не нужны (`docs/kafka/IMAGES_AND_REGISTRY.md`, сценарий A).
- **Образ в internal registry** → сценарий B.
- **tar.gz** → prep: `source/scripts/59-export-kafka-images.sh`, положить сюда, пересобрать пакет.
KAFKAEOF

cat > "$DELIVERY_DIR/load-images.sh" << 'LOADEOF'
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
for f in "$DIR"/images/*.tar.gz "$DIR"/images/kafka/*.tar.gz; do
  [[ -f "$f" ]] || continue
  echo "==> load $(basename "$f")"
  gunzip -c "$f" | docker load
done
echo "Done. Verify: docker images | grep -E 'milvus|attu|envoy|ldap|kafka|zookeeper'"
LOADEOF
chmod +x "$DELIVERY_DIR/load-images.sh"

{
  echo "# Milvus + LDAP offline delivery manifest"
  echo ""
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  echo "## Images"
  echo ""
  echo "| File | Size | SHA256 |"
  echo "|------|------|--------|"
  for f in "$DELIVERY_DIR"/images/*.tar.gz; do
    [[ -f "$f" ]] || continue
    sz=$(ls -lh "$f" | awk '{print $5}')
    sha=$(shasum -a 256 "$f" | awk '{print $1}')
    echo "| $(basename "$f") | $sz | \`${sha}\` |"
  done
} > "$DELIVERY_DIR/MANIFEST.md"

cat > "$DELIVERY_DIR/README.md" << EOF
# Milvus + LDAP — пакет для закрытого контура

| Каталог | Содержание |
|---------|------------|
| \`images/\` | Docker-образы (*.tar.gz) |
| \`source/\` | Helm, manifests, values, scripts, Dockerfile |
| \`load-images.sh\` | \`docker load\` всех образов |
| \`MANIFEST.md\` | Checksums |
| \`START_HERE.md\` | Навигация |
| \`docs/kafka/\` | Миграция Pulsar → Kafka (без образов) |
| \`docs/architecture/\` | Схемы взаимодействия и авторизации |

\`\`\`bash
./load-images.sh
cd source && ./scripts/70-install-milvus-isolated.sh
./scripts/46-install-ldap-sync.sh
./scripts/48-install-ldap-auth-gateway.sh
# Kafka (после maintenance window): см. docs/kafka/MIGRATION.md
\`\`\`
EOF

TOTAL=$(du -sh "$DELIVERY_DIR" | awk '{print $1}')
IMG_COUNT=$(find "$DELIVERY_DIR/images" -name '*.tar.gz' 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "==> Done: $DELIVERY_DIR"
echo "    images: $IMG_COUNT tar.gz, total size: $TOTAL"
echo "    missing: $MISSING"
echo ""
echo "Упаковать:"
echo "  tar -czf milvus-ldap-delivery.tar.gz -C $(dirname "$DELIVERY_DIR") $(basename "$DELIVERY_DIR")"
