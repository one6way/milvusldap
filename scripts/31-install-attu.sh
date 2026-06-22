#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-milvus}"
RELEASE="${RELEASE:-attu}"
CHART_PATH="${CHART_PATH:-chart/attu}"

kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install "$RELEASE" "$CHART_PATH" \
  --namespace "$NAMESPACE" \
  -f values/values-attu-kind.yaml

kubectl rollout status "deployment/${RELEASE}" -n "$NAMESPACE" --timeout=180s
kubectl get svc,pods -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE"

echo ""
echo "Port-forward UI: kubectl port-forward -n ${NAMESPACE} svc/${RELEASE} 3000:3000"
echo "Then open http://127.0.0.1:3000 — connect to Milvus (RBAC: use root/admin from MILVUS_NATIVE_RBAC.md if enabled)."
