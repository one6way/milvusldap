#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-milvus-local}"
IMG_DIR="${IMG_DIR:-artifacts/images}"

for tar_file in "$IMG_DIR"/*.tar; do
  [ -f "$tar_file" ] || continue
  kind load image-archive "$tar_file" --name "$CLUSTER_NAME"
done

for gz_file in "$IMG_DIR"/*.tar.gz; do
  [ -f "$gz_file" ] || continue
  tmp="$(mktemp)"
  gunzip -c "$gz_file" >"$tmp"
  kind load image-archive "$tmp" --name "$CLUSTER_NAME"
  rm -f "$tmp"
done

echo "All images loaded into kind cluster: $CLUSTER_NAME"
