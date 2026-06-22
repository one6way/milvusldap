#!/usr/bin/env bash
set -euo pipefail

BUNDLE_NAME="${BUNDLE_NAME:-milvus-airgap-bundle-$(date +%Y%m%d-%H%M%S).tar.gz}"
TMP_DIR="$(mktemp -d)"

mkdir -p "$TMP_DIR/milvus-airgap"
cp -R artifacts "$TMP_DIR/milvus-airgap/"
cp -R values "$TMP_DIR/milvus-airgap/"
cp -R scripts "$TMP_DIR/milvus-airgap/"
cp -R manifests "$TMP_DIR/milvus-airgap/"
cp -R tests "$TMP_DIR/milvus-airgap/"
cp -R chart/attu "$TMP_DIR/milvus-airgap/chart-attu"
if [[ -d images/attu-nonroot ]]; then
  cp -R images/attu-nonroot "$TMP_DIR/milvus-airgap/images-attu-nonroot"
fi

for doc in README.md AIRGAP_INSTALL.md AIRGAP_PREP_NONROOT_ONCE.md ISOLATED_CONTOUR.md ATTU.md \
  MILVUS_POST_RESTART_RECOVERY.md MILVUS_NATIVE_RBAC.md MILVUS_PODS_EXPLAINED.md \
  MILVUS_COMPONENT_FAILURE_RUNBOOK.md MILVUS_KIND_STACK_TEST_CHECKLIST.md \
  MVP_PROFILES.md KEYCLOAK_AUTH_FOR_MILVUS.md EXTERNAL_DEPS_WITH_INTERNAL_PULSAR.md \
  FIRST_TIME_INSTALL_K8S_AND_VM.md; do
  if [[ -f "$doc" ]]; then
    cp "$doc" "$TMP_DIR/milvus-airgap/"
  fi
done

tar -C "$TMP_DIR" -czf "$BUNDLE_NAME" milvus-airgap
rm -rf "$TMP_DIR"

echo "Created bundle: $BUNDLE_NAME"
