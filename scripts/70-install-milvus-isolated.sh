#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-milvus}"
RELEASE="${RELEASE:-milvus}"
CHART_PACKAGE="${CHART_PACKAGE:-artifacts/charts/milvus-4.2.33.tgz}"

kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install "$RELEASE" "$CHART_PACKAGE" \
  --namespace "$NAMESPACE" \
  -f values/values-isolated-template.yaml

kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance="$RELEASE" -n "$NAMESPACE" --timeout=900s
kubectl get pods -n "$NAMESPACE"
