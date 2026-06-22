#!/usr/bin/env python3
"""Idempotent LDAP/AD -> Milvus users and roles sync (RBAC only, no LDAP bind on Milvus login)."""
from __future__ import annotations

import json
import os
import re
import sys
from typing import Dict, Iterable, List, Set

GROUP_ROLE_MAP_DEFAULT = {
    "g-milvus-read": "reader",
    "g-milvus-write": "writer",
    "g-milvus-admin": "admin",
}

ROLE_PRIVILEGES_DEFAULT = {
    "reader": ["CollectionReadOnly", "DatabaseReadOnly"],
    "writer": ["CollectionReadWrite", "DatabaseReadWrite"],
}


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def _load_group_role_map() -> Dict[str, str]:
    raw = _env("LDAP_GROUP_ROLE_MAP_JSON")
    if not raw:
        return dict(GROUP_ROLE_MAP_DEFAULT)
    return {str(k): str(v) for k, v in json.loads(raw).items()}


def _load_role_privileges() -> Dict[str, List[str]]:
    raw = _env("LDAP_ROLE_PRIVILEGES_JSON")
    if not raw:
        return {k: list(v) for k, v in ROLE_PRIVILEGES_DEFAULT.items()}
    return {str(k): list(v) for k, v in json.loads(raw).items()}


def _normalize_username(value: str) -> str:
    mode = _env("LDAP_USERNAME_NORMALIZE", "none").lower()
    if mode == "lower":
        return value.lower()
    if mode == "sanitize":
        # Milvus 2.5.x: letters, digits, underscore; must start with letter.
        out = re.sub(r"[^A-Za-z0-9_]", "_", value)
        if out and not out[0].isalpha():
            out = f"u_{out}"
        return out[:32] or "user"
    return value[:32]


def _name_from_dn(dn: str) -> str:
    match = re.match(r"^(?:CN|cn)=([^,]+)", dn, flags=re.IGNORECASE)
    return match.group(1) if match else dn


def _groups_for_user_dn(conn, user_dn: str) -> Set[str]:
    import ldap3
    from ldap3.utils.conv import escape_filter_chars

    group_base = _env("LDAP_GROUP_BASE")
    if not group_base:
        return set()

    conn.search(
        search_base=group_base,
        search_filter=f"(member={escape_filter_chars(user_dn)})",
        search_scope=ldap3.SUBTREE,
        attributes=["cn"],
    )
    groups: Set[str] = set()
    for entry in conn.entries:
        cn = entry.entry_attributes_as_dict.get("cn") or []
        if cn:
            groups.add(str(cn[0]))
    return groups


def _ldap_connection():
    import ldap3

    uri = _env("LDAP_URI")
    bind_dn = _env("LDAP_BIND_DN")
    bind_pw = _env("LDAP_BIND_PASSWORD")
    ca_file = _env("LDAP_CA_FILE")

    if not uri or not bind_dn or not bind_pw:
        raise RuntimeError("LDAP_URI, LDAP_BIND_DN and LDAP_BIND_PASSWORD are required")

    tls = None
    use_ssl = uri.lower().startswith("ldaps://")
    if use_ssl:
        if ca_file and os.path.isfile(ca_file):
            tls = ldap3.Tls(ca_certs_file=ca_file, validate=ldap3.ssl.CERT_REQUIRED)
        else:
            tls = ldap3.Tls(validate=ldap3.ssl.CERT_NONE)

    server = ldap3.Server(uri, use_ssl=use_ssl, tls=tls, connect_timeout=10)
    conn = ldap3.Connection(server, user=bind_dn, password=bind_pw, auto_bind=True, receive_timeout=30)
    return conn


def _fetch_ad_users(conn) -> Dict[str, Set[str]]:
    import ldap3
    from ldap3.core.exceptions import LDAPAttributeError

    user_base = _env("LDAP_USER_BASE")
    user_filter = _env("LDAP_USER_FILTER", "(objectClass=user)")
    username_attr = _env("LDAP_USERNAME_ATTR", "sAMAccountName")
    group_attr = _env("LDAP_GROUP_ATTR", "memberOf")

    if not user_base:
        raise RuntimeError("LDAP_USER_BASE is required")

    ad_attrs = [username_attr, group_attr, "userAccountControl", "nsAccountLock"]
    try:
        conn.search(
            search_base=user_base,
            search_filter=user_filter,
            search_scope=ldap3.SUBTREE,
            attributes=ad_attrs,
        )
    except LDAPAttributeError:
        conn.search(
            search_base=user_base,
            search_filter=user_filter,
            search_scope=ldap3.SUBTREE,
            attributes=[username_attr, group_attr],
        )

    users: Dict[str, Set[str]] = {}
    for entry in conn.entries:
        attrs = entry.entry_attributes_as_dict
        raw_name = attrs.get(username_attr) or []
        if not raw_name:
            continue
        username = _normalize_username(str(raw_name[0]))
        if not username:
            continue

        uac_raw = attrs.get("userAccountControl") or [0]
        try:
            uac = int(uac_raw[0] if isinstance(uac_raw, (list, tuple)) else uac_raw)
        except (TypeError, ValueError):
            uac = 0
        ns_lock = attrs.get("nsAccountLock") or ["false"]
        if (uac & 0x0002) or str(ns_lock[0]).lower() == "true":
            print(f"skip inactive ldap user {username!r}")
            continue

        groups: Set[str] = set()
        for dn in attrs.get(group_attr) or []:
            groups.add(_name_from_dn(str(dn)))
        if not groups:
            groups = _groups_for_user_dn(conn, entry.entry_dn)
        users[username] = groups
    return users


def _milvus_client():
    from pymilvus import MilvusClient

    host = _env("MILVUS_HOST", "milvus")
    port = _env("MILVUS_PORT", "19530")
    root_user = _env("MILVUS_ROOT_USER", "root")
    root_pw = _env("MILVUS_ROOT_PASSWORD")
    if not root_pw:
        raise RuntimeError("MILVUS_ROOT_PASSWORD is required")

    uri = f"http://{host}:{port}"
    return MilvusClient(uri=uri, token=f"{root_user}:{root_pw}")


def _privilege_scope(privilege: str) -> tuple[str, str]:
    # pymilvus 2.5.x grant_privilege_v2 requires db_name + collection_name.
    default_db = _env("MILVUS_DEFAULT_DB", "default")
    priv = privilege.upper()
    if priv.startswith("CLUSTER"):
        return "*", "*"
    if priv.startswith("DATABASE") or priv.startswith("DB_"):
        return default_db, "*"
    return default_db, "*"


def _ensure_roles(client, role_privileges: Dict[str, List[str]], group_role_map: Dict[str, str]) -> None:
    needed_roles = set(group_role_map.values()) | set(role_privileges.keys())
    existing = set(client.list_roles() or [])
    for role in sorted(needed_roles):
        if role not in existing:
            client.create_role(role_name=role)
            print(f"created role {role!r}")
        for privilege in role_privileges.get(role, []):
            db_name, collection_name = _privilege_scope(privilege)
            try:
                client.grant_privilege_v2(
                    role_name=role,
                    privilege=privilege,
                    collection_name=collection_name,
                    db_name=db_name,
                )
            except (AttributeError, TypeError):
                client.grant_privilege(
                    role_name=role,
                    object_type="Global",
                    object_name="*",
                    privilege=privilege,
                )
            except Exception as exc:
                msg = str(exc).lower()
                if "already" in msg or "exist" in msg:
                    continue
                raise


def _user_roles(client, username: str) -> Set[str]:
    info = client.describe_user(user_name=username)
    if isinstance(info, dict):
        roles = info.get("roles", [])
    else:
        roles = getattr(info, "roles", []) or []
    if isinstance(roles, str):
        return {roles} if roles else set()
    return set(roles or [])


def _sync_users(
    client,
    ldap_users: Dict[str, Set[str]],
    group_role_map: Dict[str, str],
) -> None:
    default_password = _env("MILVUS_SYNC_DEFAULT_PASSWORD")
    if len(default_password) < 6:
        raise RuntimeError("MILVUS_SYNC_DEFAULT_PASSWORD must be at least 6 characters")

    revoke_orphan = _env("LDAP_MILVUS_REVOKE_ORPHAN", "true").lower() in {"1", "true", "yes"}
    dry_run = _env("LDAP_SYNC_DRY_RUN", "false").lower() in {"1", "true", "yes"}

    milvus_users = set(client.list_users() or [])
    super_users = {u.strip() for u in _env("MILVUS_SUPER_USERS", "root,admin").split(",") if u.strip()}

    for username, groups in sorted(ldap_users.items()):
        if username in super_users:
            print(f"skip super user {username!r}")
            continue

        target_roles = sorted({group_role_map[g] for g in groups if g in group_role_map})
        if not target_roles:
            continue

        if username not in milvus_users:
            print(f"create user {username!r} roles={target_roles}")
            if not dry_run:
                client.create_user(user_name=username, password=default_password)
        else:
            print(f"update user {username!r} roles={target_roles}")

        current_roles = _user_roles(client, username)
        desired_roles = set(target_roles)

        for role in sorted(desired_roles - current_roles):
            print(f"grant {username!r} -> {role!r}")
            if not dry_run:
                client.grant_role(user_name=username, role_name=role)

        if revoke_orphan:
            for role in sorted(current_roles - desired_roles):
                if role == "admin" and username in super_users:
                    continue
                print(f"revoke {username!r} <- {role!r}")
                if not dry_run:
                    client.revoke_role(user_name=username, role_name=role)


def main() -> int:
    group_role_map = _load_group_role_map()
    role_privileges = _load_role_privileges()

    print("LDAP -> Milvus sync start")
    conn = _ldap_connection()
    ldap_users = _fetch_ad_users(conn)
    print(f"ldap users fetched: {len(ldap_users)}")

    client = _milvus_client()
    _ensure_roles(client, role_privileges, group_role_map)
    _sync_users(client, ldap_users, group_role_map)
    print("LDAP -> Milvus sync OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"LDAP sync failed: {exc}", file=sys.stderr)
        raise
