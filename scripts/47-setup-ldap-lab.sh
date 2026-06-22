#!/usr/bin/env bash
# Lab: OpenLDAP + ldap-sync + manual test user for Attu on kind.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NAMESPACE="${NAMESPACE:-milvus}"

echo "==> 1/5 OpenLDAP lab"
kubectl apply -f manifests/ldap-lab/openldap.yaml
kubectl -n "$NAMESPACE" rollout status deployment/openldap-lab --timeout=300s

echo "==> 2/5 ldap-sync manifests"
VALUES_FILE=values/values-ldap-sync-kind-lab.yaml \
SECRET_FILE=manifests/ldap-sync/ldap-sync-secret.lab.yaml \
CA_FILE=manifests/ldap-sync/ldap-sync-ca.lab.yaml \
./scripts/46-install-ldap-sync.sh

echo "==> 3/5 run sync once"
kubectl -n "$NAMESPACE" delete job milvus-ldap-sync-manual --ignore-not-found
kubectl -n "$NAMESPACE" create job milvus-ldap-sync-manual --from=cronjob/milvus-ldap-sync
kubectl -n "$NAMESPACE" wait --for=condition=complete job/milvus-ldap-sync-manual --timeout=300s
kubectl -n "$NAMESPACE" logs job/milvus-ldap-sync-manual

echo "==> 4/5 verify Milvus user testuser"
kubectl -n "$NAMESPACE" delete job milvus-verify-testuser --ignore-not-found
kubectl -n "$NAMESPACE" run milvus-verify-testuser --rm -i --restart=Never \
  --image=python:3.11-slim \
  --env MILVUS_HOST=milvus \
  --env MILVUS_PORT=19530 \
  --command -- bash -c "pip install -q pymilvus==2.5.0 && python - <<'PY'
from pymilvus import MilvusClient
c = MilvusClient(uri='http://milvus:19530', token='root:user')
print('users:', c.list_users())
print('testuser:', c.describe_user(user_name='testuser'))
c2 = MilvusClient(uri='http://milvus:19530', token='testuser:AttuTest1')
print('testuser login: OK')
PY"

echo ""
echo "==> 5/5 Attu (manual check)"
echo "Terminal 1: kubectl port-forward -n ${NAMESPACE} svc/attu 3000:3000"
echo "Terminal 2: kubectl port-forward -n ${NAMESPACE} svc/milvus 19530:19530   # optional for local clients"
echo "Open http://127.0.0.1:3000"
echo "  Milvus address: milvus:19530"
echo "  Username:       testuser"
echo "  Password:       AttuTest1"
echo ""
echo "LDAP lab user (bind only, not Attu password): uid=testuser / Testldap1"
echo "LDAP admin: cn=admin,dc=lab,dc=local / admin"
