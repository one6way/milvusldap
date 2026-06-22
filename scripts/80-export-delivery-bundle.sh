#!/usr/bin/env bash
set -euo pipefail

BUNDLE_NAME="${BUNDLE_NAME:-milvus-delivery-bundle-$(date +%Y%m%d-%H%M%S).tar.gz}"
TMP_DIR="$(mktemp -d)"

mkdir -p "$TMP_DIR/milfus-main"
cp -R artifacts "$TMP_DIR/milfus-main/"
cp -R values "$TMP_DIR/milfus-main/"
cp -R scripts "$TMP_DIR/milfus-main/"
cp -R manifests "$TMP_DIR/milfus-main/"
cp -R tests "$TMP_DIR/milfus-main/"
cp -R chart/attu "$TMP_DIR/milfus-main/chart-attu"
if [[ -d images/attu-nonroot ]]; then
  cp -R images/attu-nonroot "$TMP_DIR/milfus-main/images-attu-nonroot"
fi

for doc in README.md ISOLATED_INSTALL.md PREP_NONROOT_ONCE.md ISOLATED_CONTOUR.md ATTU.md \
  MILVUS_POST_RESTART_RECOVERY.md MILVUS_NATIVE_RBAC.md MILVUS_PODS_EXPLAINED.md \
  MILVUS_COMPONENT_FAILURE_RUNBOOK.md MILVUS_KIND_STACK_TEST_CHECKLIST.md \
  MVP_PROFILES.md KEYCLOAK_AUTH_FOR_MILVUS.md EXTERNAL_DEPS_WITH_INTERNAL_PULSAR.md \
  FIRST_TIME_INSTALL_K8S_AND_VM.md; do
  if [[ -f "$doc" ]]; then
    cp "$doc" "$TMP_DIR/milfus-main/"
  fi
done

tar -C "$TMP_DIR" -czf "$BUNDLE_NAME" milfus-main
rm -rf "$TMP_DIR"

echo "Created bundle: $BUNDLE_NAME"
