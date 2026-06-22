#!/usr/bin/env bash
# Сохранить образы в artifacts/images и упаковать чарты в artifacts/charts.
# Не вызывает helm dependency update — только helm package (subchart'ы уже в chart/milvus/charts/).
set -euo pipefail

CHART_VERSION="${CHART_VERSION:-4.2.33}"
ATTU_CHART_VERSION="${ATTU_CHART_VERSION:-0.1.0}"
OUT_DIR="${OUT_DIR:-artifacts/images}"
CHART_DIR="${CHART_DIR:-artifacts/charts}"

mkdir -p "$OUT_DIR" "$CHART_DIR"

helm package chart/milvus --version "$CHART_VERSION" --destination "$CHART_DIR" >/dev/null
helm package chart/attu --version "$ATTU_CHART_VERSION" --destination "$CHART_DIR" >/dev/null

# Образы как в values-kind-localpath.yaml (non-root), плюс attu-nonroot.
images=(
  "milvus-nonroot:2.5.0"
  "milvus-etcd-nonroot:3.5.16-r1"
  "milvus-minio-nonroot:RELEASE.2023-03-20T20-16-18Z"
  "milvus-pulsar-nonroot:3.0.7"
  "attu-nonroot:2.5.10"
  "rancher/local-path-provisioner:v0.0.35"
  "busybox:1.36"
)

for image in "${images[@]}"; do
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    echo "ERROR: образа нет локально: $image" >&2
    echo "На prep-стенде выполните: ./scripts/53-build-all-nonroot-images.sh" >&2
    exit 1
  fi
  safe_name="$(echo "$image" | tr '/:' '__')"
  docker save "$image" -o "$OUT_DIR/${safe_name}.tar"
  gzip -cf "$OUT_DIR/${safe_name}.tar" >"$OUT_DIR/${safe_name}.tar.gz"
  echo "Saved $image -> ${safe_name}.tar(.gz)"
done

echo "Charts -> $CHART_DIR; images -> $OUT_DIR"
