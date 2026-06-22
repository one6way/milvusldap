#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-milvus}"
RELEASE="${RELEASE:-milvus}"
CHART_PATH="${CHART_PATH:-chart/milvus}"

# Subchart'ы лежат в chart/milvus/charts/ (vendored) — сеть не нужна.
# Обновить зависимости с репозиториев: HELM_DEPS_UPDATE=1 или ./scripts/51-refresh-helm-chart-dependencies.sh
if [[ "${HELM_DEPS_UPDATE:-0}" == "1" ]]; then
  helm dependency update "$CHART_PATH"
else
  echo "Helm: без helm dependency update (offline / vendored charts)."
fi

kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install "$RELEASE" "$CHART_PATH" \
  --namespace "$NAMESPACE" \
  -f values/values-kind-localpath.yaml

kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance="$RELEASE" -n "$NAMESPACE" --timeout=900s
kubectl get pods -n "$NAMESPACE"
