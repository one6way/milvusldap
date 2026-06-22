#!/usr/bin/env python3
"""Idempotent bootstrap: create Milvus user admin and attach to built-in admin role."""
import os
import sys


def main() -> int:
    host = os.environ.get("MILVUS_HOST", "milvus")
    port = os.environ.get("MILVUS_PORT", "19530")
    root_user = os.environ.get("MILVUS_ROOT_USER", "root")
    root_pw = os.environ.get("MILVUS_ROOT_PASSWORD", "")
    admin_user = os.environ.get("MILVUS_ADMIN_USER", "admin")
    admin_pw = os.environ.get("MILVUS_ADMIN_PASSWORD", "user")
    fallback_pw = os.environ.get("MILVUS_ADMIN_PASSWORD_FALLBACK", "user00")

    if not root_pw:
        print("MILVUS_ROOT_PASSWORD is required", file=sys.stderr)
        return 1

    from pymilvus import Role, connections, utility

    connections.connect(
        alias="default",
        host=host,
        port=port,
        user=root_user,
        password=root_pw,
    )

    _list_fn = getattr(utility, "list_users", None) or getattr(
        utility, "list_usernames", None
    )
    if _list_fn is None:
        print("pymilvus utility has no list_users/list_usernames", file=sys.stderr)
        return 1
    users = set(_list_fn())
    if admin_user in users:
        print(f"User {admin_user!r} already exists, skip create_user")
    else:
        try:
            utility.create_user(admin_user, admin_pw)
            print(f"Created user {admin_user!r}")
        except Exception as e:
            err = str(e).lower()
            if len(admin_pw) < 6 or "password" in err or "length" in err or "invalid" in err:
                print(
                    f"create_user with requested password failed ({e!r}); retry with fallback len>=6",
                    file=sys.stderr,
                )
                utility.create_user(admin_user, fallback_pw)
                print(
                    f"Created user {admin_user!r} with fallback password (see MILVUS_NATIVE_RBAC.md)"
                )
            else:
                raise

    role = Role("admin", using="default")
    in_role = set(role.get_users())
    if admin_user in in_role:
        print(f"User {admin_user!r} already in role admin")
    else:
        role.add_user(admin_user)
        print(f"Added {admin_user!r} to role admin")

    print("Bootstrap OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
