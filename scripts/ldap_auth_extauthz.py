#!/usr/bin/env python3
"""Envoy HTTP ext_authz + IB /user/info API for Milvus LDAP domain login."""
from __future__ import annotations

import base64
import json
import logging
import os
import re
import sys
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Dict, Optional, Tuple

logging.basicConfig(level=logging.INFO, format="%(message)s")
LOG = logging.getLogger("ldap-auth-extauthz")

_STATE_PATH = os.environ.get("LDAP_AUTH_STATE_FILE", "/tmp/ldap_auth_state.json")
_STATE_LOCK = threading.Lock()

UAC_ACCOUNTDISABLE = 0x0002
UAC_LOCKOUT = 0x0010
UAC_PASSWORD_EXPIRED = 0x00800000

USER_INFO_PATHS = {"/api/v1/user/info", "/ldap/user/info", "/user/info"}


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def _audit(event: str, **fields: Any) -> None:
    payload = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "component": "milvus-ldap-auth",
        "event": event,
        **fields,
    }
    LOG.info(json.dumps(payload, ensure_ascii=False))


def _normalize_username(value: str) -> str:
    mode = _env("LDAP_USERNAME_NORMALIZE", "sanitize").lower()
    if mode == "lower":
        return value.lower()
    if mode == "sanitize":
        out = re.sub(r"[^A-Za-z0-9_]", "_", value)
        if out and not out[0].isalpha():
            out = f"u_{out}"
        return out[:32] or "user"
    return value[:32]


def _parse_basic_auth(header: str) -> Optional[Tuple[str, str]]:
    if not header:
        return None
    h = header.strip()
    if h.lower().startswith("basic "):
        h = h[6:].strip()
    try:
        raw = base64.b64decode(h).decode("utf-8")
    except Exception:
        return None
    if ":" not in raw:
        return None
    user, password = raw.split(":", 1)
    if not user:
        return None
    return user, password


def _first_attr(attrs: Dict[str, Any], name: str, default: Any = None) -> Any:
    value = attrs.get(name)
    if value is None:
        return default
    if isinstance(value, (list, tuple)):
        return value[0] if value else default
    return value


def _filetime_to_iso(value: Any) -> Optional[str]:
    if value is None:
        return None
    try:
        ft = int(value)
    except (TypeError, ValueError):
        return None
    if ft in (0, 9223372036854775807):
        return None
    seconds = ft / 10_000_000 - 11644473600
    if seconds <= 0:
        return None
    return datetime.fromtimestamp(seconds, tz=timezone.utc).isoformat()


def _now_filetime() -> int:
    epoch = datetime.now(timezone.utc).timestamp()
    return int((epoch + 11644473600) * 10_000_000)


def _load_state() -> Dict[str, Any]:
    with _STATE_LOCK:
        if not os.path.isfile(_STATE_PATH):
            return {"users": {}}
        try:
            with open(_STATE_PATH, encoding="utf-8") as fh:
                return json.load(fh)
        except (OSError, json.JSONDecodeError):
            return {"users": {}}


def _save_state(state: Dict[str, Any]) -> None:
    with _STATE_LOCK:
        tmp = f"{_STATE_PATH}.tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(state, fh)
        os.replace(tmp, _STATE_PATH)


def _record_failed_login(username: str) -> int:
    state = _load_state()
    users = state.setdefault("users", {})
    entry = users.setdefault(username, {})
    entry["failed_login_attempts"] = int(entry.get("failed_login_attempts", 0)) + 1
    entry["last_failed_login"] = datetime.now(timezone.utc).isoformat()
    _save_state(state)
    return int(entry["failed_login_attempts"])


def _record_success_login(username: str) -> None:
    state = _load_state()
    users = state.setdefault("users", {})
    entry = users.setdefault(username, {})
    entry["failed_login_attempts"] = 0
    entry["last_success_login"] = datetime.now(timezone.utc).isoformat()
    _save_state(state)


def _local_failed_attempts(username: str) -> int:
    state = _load_state()
    entry = state.get("users", {}).get(username, {})
    return int(entry.get("failed_login_attempts", 0))


def _local_last_login(username: str) -> Optional[str]:
    state = _load_state()
    entry = state.get("users", {}).get(username, {})
    return entry.get("last_success_login")


def _ldap_service_connection():
    import ldap3

    uri = _env("LDAP_URI")
    bind_dn = _env("LDAP_BIND_DN")
    bind_pw = _env("LDAP_BIND_PASSWORD")
    ca_file = _env("LDAP_CA_FILE")

    if not uri or not bind_dn or not bind_pw:
        raise RuntimeError("LDAP_URI, LDAP_BIND_DN, LDAP_BIND_PASSWORD required")

    tls = None
    use_ssl = uri.lower().startswith("ldaps://")
    if use_ssl:
        if ca_file and os.path.isfile(ca_file):
            tls = ldap3.Tls(ca_certs_file=ca_file, validate=ldap3.ssl.CERT_REQUIRED)
        else:
            tls = ldap3.Tls(validate=ldap3.ssl.CERT_NONE)

    server = ldap3.Server(uri, use_ssl=use_ssl, tls=tls, connect_timeout=10)
    return ldap3.Connection(server, user=bind_dn, password=bind_pw, auto_bind=True, receive_timeout=15)


def _domain_policy(conn) -> Dict[str, Any]:
    import ldap3

    policy: Dict[str, Any] = {}
    try:
        conn.search("", "(objectClass=*)", ldap3.BASE, attributes=["*"])
        if not conn.entries:
            return policy
        attrs = conn.entries[0].entry_attributes_as_dict
        base = _first_attr(attrs, "defaultNamingContext") or _first_attr(attrs, "namingContexts")
        if not base:
            return policy
        if isinstance(base, (list, tuple)):
            base = base[0]
        conn.search(
            search_base=str(base),
            search_filter="(objectClass=domain)",
            search_scope=ldap3.BASE,
            attributes=["maxPwdAge", "lockoutThreshold", "lockoutDuration"],
        )
        if conn.entries:
            ad_attrs = conn.entries[0].entry_attributes_as_dict
            for key in ("maxPwdAge", "lockoutThreshold", "lockoutDuration"):
                val = _first_attr(ad_attrs, key)
                if val is not None:
                    policy[key] = int(val)
    except Exception as exc:
        _audit("domain_policy_read_failed", error=str(exc))
    return policy


def _find_user(conn, username: str):
    import ldap3
    from ldap3.core.exceptions import LDAPAttributeError

    user_base = _env("LDAP_USER_BASE")
    user_filter = _env("LDAP_USER_FILTER", "(&(objectClass=user)(objectCategory=person))")
    username_attr = _env("LDAP_USERNAME_ATTR", "sAMAccountName")

    if not user_base:
        raise RuntimeError("LDAP_USER_BASE required")

    safe_user = ldap3.utils.conv.escape_filter_chars(username)
    filt = f"(&{user_filter}({username_attr}={safe_user}))"
    ad_attrs = [
        "userAccountControl",
        "lockoutTime",
        "badPwdCount",
        "lastLogon",
        "lastLogonTimestamp",
        "pwdLastSet",
        "pwdAccountLockedTime",
        "accountExpires",
        "nsAccountLock",
    ]
    try:
        conn.search(search_base=user_base, search_filter=filt, search_scope=ldap3.SUBTREE, attributes=ad_attrs)
    except LDAPAttributeError:
        conn.search(
            search_base=user_base,
            search_filter=filt,
            search_scope=ldap3.SUBTREE,
            attributes=ldap3.ALL_ATTRIBUTES,
        )
    if not conn.entries:
        return None
    entry = conn.entries[0]
    return entry.entry_dn, entry.entry_attributes_as_dict


def _password_expiry_iso(pwd_last_set: Any, max_pwd_age: Optional[int]) -> Optional[str]:
    if pwd_last_set is None:
        return None
    try:
        pwd_ft = int(pwd_last_set)
    except (TypeError, ValueError):
        return None
    if pwd_ft == 0:
        return datetime.now(timezone.utc).isoformat()
    if not max_pwd_age:
        return None
    expiry_ft = pwd_ft + abs(int(max_pwd_age))
    return _filetime_to_iso(expiry_ft)


def _is_password_expired(pwd_last_set: Any, max_pwd_age: Optional[int]) -> bool:
    if pwd_last_set is None:
        return False
    try:
        pwd_ft = int(pwd_last_set)
    except (TypeError, ValueError):
        return False
    if pwd_ft == 0:
        return True
    if not max_pwd_age:
        return False
    return _now_filetime() >= pwd_ft + abs(int(max_pwd_age))


def _build_user_info(username: str, attrs: Dict[str, Any], policy: Dict[str, Any]) -> Dict[str, Any]:
    uac_raw = _first_attr(attrs, "userAccountControl", 0)
    try:
        uac = int(uac_raw or 0)
    except (TypeError, ValueError):
        uac = 0

    lockout_time = _first_attr(attrs, "lockoutTime", 0)
    bad_pwd_count = _first_attr(attrs, "badPwdCount", 0)
    pwd_last_set = _first_attr(attrs, "pwdLastSet")
    max_pwd_age = policy.get("maxPwdAge")
    lockout_threshold = policy.get("lockoutThreshold")

    try:
        bad_pwd_count = int(bad_pwd_count or 0)
    except (TypeError, ValueError):
        bad_pwd_count = 0

    is_disabled = bool(uac & UAC_ACCOUNTDISABLE)
    is_ad_locked = False
    try:
        is_ad_locked = int(lockout_time or 0) > 0
    except (TypeError, ValueError):
        is_ad_locked = bool(uac & UAC_LOCKOUT)

    openldap_locked = bool(_first_attr(attrs, "pwdAccountLockedTime"))
    openldap_inactive = str(_first_attr(attrs, "nsAccountLock", "false")).lower() == "true"
    password_expired = bool(uac & UAC_PASSWORD_EXPIRED) or _is_password_expired(pwd_last_set, max_pwd_age)

    account_locked = is_disabled or is_ad_locked or openldap_locked or password_expired
    lock_reason = ""
    if is_disabled or openldap_inactive:
        lock_reason = "account disabled"
    elif is_ad_locked or openldap_locked:
        lock_reason = "exceeded login attempts"
    elif password_expired:
        lock_reason = "password expired"
    elif int(pwd_last_set or -1) == 0:
        lock_reason = "password change required"

    last_login = _filetime_to_iso(_first_attr(attrs, "lastLogonTimestamp"))
    if not last_login:
        last_login = _filetime_to_iso(_first_attr(attrs, "lastLogon"))
    if not last_login:
        last_login = _local_last_login(username)

    failed_attempts = bad_pwd_count if bad_pwd_count else _local_failed_attempts(username)
    if lockout_threshold and failed_attempts >= int(lockout_threshold):
        account_locked = True
        if not lock_reason:
            lock_reason = "exceeded login attempts"

    is_active = not is_disabled and not openldap_inactive

    return {
        "username": username,
        "milvus_username": _normalize_username(username),
        "last_login": last_login,
        "password_expiry_date": _password_expiry_iso(pwd_last_set, max_pwd_age),
        "account_locked": account_locked,
        "lock_reason": lock_reason,
        "failed_login_attempts": failed_attempts,
        "is_active": is_active,
    }


def _ldap_bind(username: str, password: str) -> Tuple[bool, str, Optional[Dict[str, Any]]]:
    import ldap3

    conn = _ldap_service_connection()
    policy = _domain_policy(conn)
    found = _find_user(conn, username)
    if not found:
        _record_failed_login(username)
        _audit("login_denied", username=username, reason="user_not_found", client_result="deny")
        return False, "user_not_found", None

    user_dn, attrs = found
    info = _build_user_info(username, attrs, policy)
    if info["account_locked"]:
        _record_failed_login(username)
        _audit(
            "login_denied",
            username=username,
            reason=info["lock_reason"] or "account_locked",
            failed_login_attempts=info["failed_login_attempts"],
            client_result="deny",
        )
        return False, info["lock_reason"] or "account_locked", info

    server = conn.server
    user_conn = ldap3.Connection(server, user=user_dn, password=password, receive_timeout=15)
    if not user_conn.bind():
        failed = _record_failed_login(username)
        reason = "invalid_credentials"
        if info.get("password_expiry_date") and _is_password_expired(
            _first_attr(attrs, "pwdLastSet"), policy.get("maxPwdAge")
        ):
            reason = "password_expired"
        _audit(
            "login_denied",
            username=username,
            reason=reason,
            failed_login_attempts=failed,
            client_result="deny",
        )
        return False, reason, info

    _record_success_login(username)
    _audit("login_granted", username=username, milvus_username=info["milvus_username"], client_result="allow")
    return True, "ok", info


def _milvus_authorization_header(username: str) -> str:
    milvus_user = _normalize_username(username)
    milvus_pass = _env("MILVUS_SYNC_DEFAULT_PASSWORD")
    if len(milvus_pass) < 6:
        raise RuntimeError("MILVUS_SYNC_DEFAULT_PASSWORD must be at least 6 characters")
    return base64.b64encode(f"{milvus_user}:{milvus_pass}".encode()).decode()


def _json_response(handler: BaseHTTPRequestHandler, status: int, payload: Dict[str, Any]) -> None:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        return

    def _handle_user_info(self) -> None:
        auth = self.headers.get("Authorization") or self.headers.get("authorization")
        parsed = _parse_basic_auth(auth or "")
        if not parsed:
            _audit("user_info_denied", reason="missing_authorization", client_ip=self.address_string())
            _json_response(self, 401, {"error": "authorization required"})
            return

        username, password = parsed
        try:
            ok, reason, cached_info = _ldap_bind(username, password)
            if not ok:
                payload = cached_info or {
                    "username": username,
                    "last_login": _local_last_login(username),
                    "password_expiry_date": None,
                    "account_locked": True,
                    "lock_reason": reason,
                    "failed_login_attempts": _local_failed_attempts(username),
                    "is_active": False,
                }
                _json_response(self, 403, payload)
                return

            conn = _ldap_service_connection()
            policy = _domain_policy(conn)
            found = _find_user(conn, username)
            if not found:
                _json_response(self, 404, {"error": "user not found"})
                return
            _, attrs = found
            payload = _build_user_info(username, attrs, policy)
            payload["last_login"] = payload.get("last_login") or _local_last_login(username)
            _audit("user_info_ok", username=username, account_locked=payload["account_locked"])
            _json_response(self, 200, payload)
        except Exception as exc:
            LOG.exception("user_info error")
            _audit("user_info_error", username=username, error=str(exc))
            _json_response(self, 500, {"error": "internal error"})

    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0]
        if path in ("/healthz", "/readyz", "/"):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")
            return
        if path in USER_INFO_PATHS:
            self._handle_user_info()
            return
        self.send_response(404)
        self.end_headers()

    def do_POST(self) -> None:
        auth = self.headers.get("Authorization") or self.headers.get("authorization")
        parsed = _parse_basic_auth(auth or "")
        if not parsed:
            _audit("ext_authz_denied", reason="missing_authorization", client_ip=self.address_string())
            self.send_response(403)
            self.end_headers()
            return

        username, password = parsed
        try:
            ok, reason, _info = _ldap_bind(username, password)
            if not ok:
                self.send_response(403)
                self.end_headers()
                return
            new_auth = _milvus_authorization_header(username)
        except Exception as exc:
            _audit("ext_authz_error", username=username, error=str(exc))
            self.send_response(500)
            self.end_headers()
            return

        self.send_response(200)
        self.send_header("Authorization", new_auth)
        self.send_header("Content-Length", "0")
        self.end_headers()


def main() -> int:
    port = int(_env("HTTP_PORT", "8080"))
    host = _env("HTTP_HOST", "0.0.0.0")
    _audit("service_start", listen=f"{host}:{port}")
    httpd = ThreadingHTTPServer((host, port), Handler)
    httpd.serve_forever()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        sys.exit(0)
