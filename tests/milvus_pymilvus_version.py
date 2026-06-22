#!/usr/bin/env python3
"""Опционально: версия Milvus через PyMilvus (localhost:19530, root/user)."""
import os
import sys

try:
    from pymilvus import connections, utility
except ImportError:
    print("ERROR: pip install pymilvus", file=sys.stderr)
    sys.exit(2)

host = os.environ.get("MILVUS_HOST", "127.0.0.1")
port = os.environ.get("MILVUS_PORT", "19530")
user = os.environ.get("MILVUS_USER", "root")
password = os.environ.get("MILVUS_PASSWORD", "user")

connections.connect("default", host=host, port=port, user=user, password=password)
ver = utility.get_server_version()
print(f"server_version={ver}")
cols = utility.list_collections()
print(f"collections_count={len(cols)}")
if cols:
    print(f"collections_sample={cols[:5]}")
