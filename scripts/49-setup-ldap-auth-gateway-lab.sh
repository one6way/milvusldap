#!/usr/bin/env bash
# Lab: install LDAP domain-login gateway on kind + smoke test with OpenLDAP users.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
NAMESPACE="${NAMESPACE:-milvus}"

echo "==> 1/4 build & load images"
docker build -q -t milvus-ldap-auth:2.5.0-lab -f docker/ldap-auth-extauthz/Dockerfile .
docker build -q -t envoy-nonroot:v1.31.2 -f images/envoy-nonroot/Dockerfile images/envoy-nonroot
kind load docker-image milvus-ldap-auth:2.5.0-lab envoy-nonroot:v1.31.2 --name milvus-k121

echo "==> 2/4 install gateway"
VALUES_FILE=values/values-ldap-auth-gateway-kind-lab.yaml \
SECRET_FILE=manifests/ldap-auth/ldap-auth-secret.lab.yaml \
CA_FILE=manifests/ldap-auth/ldap-auth-ca.lab.yaml \
LDAP_AUTH_IMAGE=milvus-ldap-auth:2.5.0-lab \
ENVOY_IMAGE=envoy-nonroot:v1.31.2 \
./scripts/48-install-ldap-auth-gateway.sh

echo "==> 3/4 ensure ldap-sync users exist"
kubectl -n "$NAMESPACE" delete job milvus-ldap-sync-manual --ignore-not-found
kubectl -n "$NAMESPACE" create job milvus-ldap-sync-manual --from=cronjob/milvus-ldap-sync
kubectl -n "$NAMESPACE" wait --for=condition=complete job/milvus-ldap-sync-manual --timeout=120s

echo "==> 4/4 smoke test (LDAP password via gateway)"
kubectl -n "$NAMESPACE" run ldap-gw-smoke --rm -i --restart=Never \
  --image=milvus-ldap-sync:2.5.0-lab --image-pull-policy=IfNotPresent \
  --command -- python - <<'PY'
from pymilvus import MilvusClient
c = MilvusClient(uri="http://milvus-ldap-gateway:19530", token="testuser:**********")
print("gateway OK:", c.list_databases())
PY

cat <<EOF

==> Attu manual test
  kubectl port-forward -n ${NAMESPACE} svc/attu 3000:3000
  http://127.0.0.1:3000
    Milvus address: milvus-ldap-gateway:19530
    Username:       testuser
    Password:       **********   (LDAP password, NOT **********)

  milvus655 / ********** — same pattern.
EOF
