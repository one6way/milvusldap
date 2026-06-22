#!/usr/bin/env bash
# Install LDAP -> Milvus RBAC sync CronJob for milvus-k121 (or any cluster).
# Prereqs: Milvus up with authorizationEnabled; LDAPS CA + bind secret prepared.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NAMESPACE="${NAMESPACE:-milvus}"
VALUES_FILE="${VALUES_FILE:-values/values-ldap-sync-milvus-k121.yaml}"
SECRET_FILE="${SECRET_FILE:-manifests/ldap-sync/ldap-sync-secret.yaml}"
CA_FILE="${CA_FILE:-manifests/ldap-sync/ldap-sync-ca.yaml}"
SCHEDULE="${LDAP_SYNC_SCHEDULE:-*/15 * * * *}"

need() { command -v "$1" >/dev/null || { echo "ERROR: missing: $1" >&2; exit 1; }; }
need kubectl
need python3

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "ERROR: values file not found: $VALUES_FILE" >&2
  exit 1
fi
if [[ ! -f "$SECRET_FILE" ]]; then
  echo "ERROR: secret file not found: $SECRET_FILE" >&2
  echo "Copy manifests/ldap-sync/ldap-sync-secret.example.yaml and fill LDAP_BIND_PASSWORD." >&2
  exit 1
fi
if [[ ! -f "$CA_FILE" ]]; then
  echo "ERROR: CA configmap not found: $CA_FILE" >&2
  echo "Copy manifests/ldap-sync/ldap-sync-ca.example.yaml with your LDAPS CA." >&2
  exit 1
fi

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
milvus = section("milvus")

group_map = {}
for line in section("groupRoleMap").splitlines():
    m = re.match(r"\s{4}([^:]+):\s*(\S+)", line)
    if m:
        group_map[m.group(1).strip()] = m.group(2).strip()

role_priv = {}
current = None
for line in section("rolePrivileges").splitlines():
    m_role = re.match(r"\s{4}(\w+):\s*$", line)
    if m_role:
        current = m_role.group(1)
        role_priv[current] = []
        continue
    m_priv = re.match(r"\s{6}-\s+(\S+)", line)
    if m_priv and current:
        role_priv[current].append(m_priv.group(1))

out = {
    "ldap_uri": field(ldap, "uri"),
    "ldap_bind_dn": field(ldap, "bindDn"),
    "ldap_user_base": field(ldap, "userBase"),
    "ldap_group_base": field(ldap, "groupBase"),
    "ldap_user_filter": field(ldap, "userFilter", "(objectClass=user)"),
    "ldap_username_attr": field(ldap, "usernameAttr", "sAMAccountName"),
    "ldap_group_attr": field(ldap, "groupAttr", "memberOf"),
    "ldap_username_normalize": field(ldap, "usernameNormalize", "none"),
    "ldap_revoke_orphan": field(ldap, "revokeOrphanRoles", "true"),
    "ldap_dry_run": field(ldap, "dryRun", "false"),
    "milvus_host": field(milvus, "host", "milvus"),
    "milvus_port": field(milvus, "port", "19530"),
    "milvus_root_user": field(milvus, "rootUser", "root"),
    "milvus_super_users": field(milvus, "superUsers", "root,admin"),
    "map_json": json.dumps(group_map),
    "priv_json": json.dumps(role_priv),
}
print(json.dumps(out))
PY
}

eval "$(read_values | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(f"export {k}={json.dumps(v)}") for k,v in d.items()]')"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NAMESPACE" create configmap milvus-ldap-sync-script \
  --from-file=milvus_ldap_sync.py=scripts/milvus_ldap_sync.py \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "$CA_FILE"
kubectl apply -f "$SECRET_FILE"

kubectl -n "$NAMESPACE" create configmap milvus-ldap-sync-config \
  --from-literal=LDAP_URI="$ldap_uri" \
  --from-literal=LDAP_BIND_DN="$ldap_bind_dn" \
  --from-literal=LDAP_USER_BASE="$ldap_user_base" \
  --from-literal=LDAP_GROUP_BASE="$ldap_group_base" \
  --from-literal=LDAP_USER_FILTER="$ldap_user_filter" \
  --from-literal=LDAP_USERNAME_ATTR="$ldap_username_attr" \
  --from-literal=LDAP_GROUP_ATTR="$ldap_group_attr" \
  --from-literal=LDAP_USERNAME_NORMALIZE="$ldap_username_normalize" \
  --from-literal=LDAP_MILVUS_REVOKE_ORPHAN="$ldap_revoke_orphan" \
  --from-literal=LDAP_SYNC_DRY_RUN="$ldap_dry_run" \
  --from-literal=LDAP_CA_FILE=/etc/ldap/ca.crt \
  --from-literal=LDAP_GROUP_ROLE_MAP_JSON="$map_json" \
  --from-literal=LDAP_ROLE_PRIVILEGES_JSON="$priv_json" \
  --from-literal=MILVUS_HOST="$milvus_host" \
  --from-literal=MILVUS_PORT="$milvus_port" \
  --from-literal=MILVUS_ROOT_USER="$milvus_root_user" \
  --from-literal=MILVUS_SUPER_USERS="$milvus_super_users" \
  --dry-run=client -o yaml | kubectl apply -f -

sed "s|schedule: \"\\*/15 \\* \\* \\* \\*\"|schedule: \"${SCHEDULE}\"|" manifests/ldap-sync/cronjob.yaml \
  | kubectl apply -f -

echo "Installed milvus-ldap-sync in namespace ${NAMESPACE}"
echo "Dry-run once:"
echo "  kubectl -n ${NAMESPACE} create job milvus-ldap-sync-manual --from=cronjob/milvus-ldap-sync"
echo "  kubectl -n ${NAMESPACE} logs -f job/milvus-ldap-sync-manual"
