#!/usr/bin/env bash
# Проверяет, что Milvus proxy и Attu доступны; печатает параметры входа в UI.
set -euo pipefail

NAMESPACE="${NAMESPACE:-milvus}"

kubectl wait --for=condition=available "deploy/milvus-proxy" -n "$NAMESPACE" --timeout=180s
kubectl wait --for=condition=available "deploy/attu" -n "$NAMESPACE" --timeout=120s

out="$(kubectl exec -n "$NAMESPACE" deploy/milvus-proxy -- curl -sf http://127.0.0.1:9091/healthz)"
test "$out" = "OK"

echo "OK: milvus-proxy healthz=OK, attu Deployment available."
echo ""
echo "Port-forward только к Attu:"
echo "  kubectl port-forward -n ${NAMESPACE} svc/attu 3000:3000"
echo "  Браузер: http://127.0.0.1:3000"
echo ""
echo "В форме подключения к Milvus (важно — не localhost):"
echo "  Host / address:  milvus"
echo "  Port:            19530"
echo "  Authentication:  включить"
echo "  Username:        root"
echo "  Password:       user"
echo ""
echo "Если создавали пользователя admin скриптом bootstrap — см. MILVUS_NATIVE_RBAC.md (пароль admin может быть user00)."
