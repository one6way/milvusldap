#!/usr/bin/env bash
# Install LDAP domain-login gateway: ldap-auth-extauthz + Envoy milvus-ldap-gateway.
# Prereqs: Milvus RBAC + ldap-sync; LDAPS CA + secrets; images in cluster/registry.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NAMESPACE="${NAMESPACE:-milvus}"
VALUES_FILE="${VALUES_FILE:-values/values-ldap-auth-gateway.example.yaml}"
SECRET_FILE="${SECRET_FILE:-manifests/ldap-auth/ldap-auth-secret.yaml}"
CA_FILE="${CA_FILE:-manifests/ldap-auth/ldap-auth-ca.yaml}"
LDAP_AUTH_IMAGE="${LDAP_AUTH_IMAGE:-milvus-ldap-auth-nonroot:2.5.0}"
ENVOY_IMAGE="${ENVOY_IMAGE:-envoy-nonroot:v1.31.2}"

need() { command -v "$1" >/dev/null || { echo "ERROR: missing: $1" >&2; exit 1; }; }
need kubectl
need python3

[[ -f "$SECRET_FILE" ]] || { echo "ERROR: $SECRET_FILE not found" >&2; exit 1; }
[[ -f "$CA_FILE" ]] || { echo "ERROR: $CA_FILE not found" >&2; exit 1; }

read_values() {
  python3 - "$VALUES_FILE" <<'PY'
import json, re, sys
text = open(sys.argv[1], encoding="utf-8").read()

def scalar(line: str) -> str:
    return line.strip().strip('"').strip("'")

def section(name: str) -> str:
    m = re.search(rf"^\s{{2}}{name}:\n((?:\s{{4}}.+\n)*)", text, re.M)
    return m.group(1) if m else ""

def field(block: str, key: str, default: str = "") -> str:
    m = re.search(rf"^\s{{4}}{re.escape(key)}:\s*(.+)$", block, re.M)
    return scalar(m.group(1)) if m else default

ldap = section("ldap")
out = {
    "ldap_uri": field(ldap, "uri"),
    "ldap_bind_dn": field(ldap, "bindDn"),
    "ldap_user_base": field(ldap, "userBase"),
    "ldap_user_filter": field(ldap, "userFilter", "(&(objectClass=user)(objectCategory=person))"),
    "ldap_username_attr": field(ldap, "usernameAttr", "sAMAccountName"),
    "ldap_username_normalize": field(ldap, "usernameNormalize", "sanitize"),
}
print(json.dumps(out))
PY
}

eval "$(read_values | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(f"export {k}={json.dumps(v)}") for k,v in d.items()]')"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "$CA_FILE"
kubectl apply -f "$SECRET_FILE"

kubectl -n "$NAMESPACE" create configmap ldap-auth-extauthz-config \
  --from-literal=LDAP_URI="$ldap_uri" \
  --from-literal=LDAP_BIND_DN="$ldap_bind_dn" \
  --from-literal=LDAP_USER_BASE="$ldap_user_base" \
  --from-literal=LDAP_USER_FILTER="$ldap_user_filter" \
  --from-literal=LDAP_USERNAME_ATTR="$ldap_username_attr" \
  --from-literal=LDAP_USERNAME_NORMALIZE="$ldap_username_normalize" \
  --from-literal=LDAP_CA_FILE=/etc/ldap/ca.crt \
  --from-literal=HTTP_PORT=8080 \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f manifests/ldap-auth/envoy-milvus-gateway.yaml
kubectl apply -f manifests/ldap-auth/ldap-auth-extauthz.yaml
kubectl apply -f manifests/ldap-auth/milvus-ldap-gateway-deployment.yaml
if [[ "${APPLY_NETWORK_POLICY:-true}" == "true" ]]; then
  kubectl apply -f manifests/ldap-auth/networkpolicy-milvus-ldap.yaml
fi

kubectl -n "$NAMESPACE" set image deployment/ldap-auth-extauthz ldap-auth="$LDAP_AUTH_IMAGE"
kubectl -n "$NAMESPACE" set image deployment/milvus-ldap-gateway envoy="$ENVOY_IMAGE"

kubectl -n "$NAMESPACE" rollout status deployment/ldap-auth-extauthz --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/milvus-ldap-gateway --timeout=300s

echo ""
echo "Installed LDAP domain-login gateway in namespace ${NAMESPACE}"
echo "Attu / SDK Milvus address: milvus-ldap-gateway:19530"
echo "Username: AD login | Password: domain password"
echo "Ensure ldap-sync CronJob has created the same username in Milvus."
