#!/usr/bin/env python3
"""
Симуляция «тяжёлых» vector search для демонстрации задержек в Milvus Web UI (/webui).

Требования: pip install pymilvus; доступ к gRPC (port-forward 19530 или из pod в кластере).

Переменные окружения:
  MILVUS_HOST, MILVUS_PORT, MILVUS_USER, MILVUS_PASSWORD — как в milvus_pymilvus_version.py
  SLOW_DEMO_COLLECTION — имя коллекции (по умолчанию slow_demo_webui)
  SLOW_DEMO_DROP_FIRST — 1: удалить коллекцию если была (по умолчанию 1)
  SLOW_DEMO_VECS — число векторов для insert (по умолчанию 12000)
  SLOW_DEMO_DURATION_SEC — сколько секунд крутить тяжёлые search подряд (по умолчанию 540 = 9 мин).
    Если 0 — используется только SLOW_DEMO_ROUNDS (быстрый прогон).
  SLOW_DEMO_ROUNDS — при SLOW_DEMO_DURATION_SEC=0: число тяжёлых search (по умолчанию 8)
  SLOW_DEMO_LOG_INTERVAL_SEC — как часто печатать прогресс при режиме по длительности (по умолчанию 10)
  SLOW_DEMO_FOR_SLOW_REQUESTS_UI — 1: nprobe=nlist и большой limit (под панель Slow Requests при низком slowQuerySpanInSeconds в values-kind-localpath.yaml)
"""
from __future__ import annotations

import os
import random
import sys
import time

try:
    from pymilvus import (
        Collection,
        CollectionSchema,
        DataType,
        FieldSchema,
        connections,
        utility,
    )
except ImportError:
    print("ERROR: pip install -r tests/requirements-tests.txt", file=sys.stderr)
    sys.exit(2)

host = os.environ.get("MILVUS_HOST", "127.0.0.1")
port = os.environ.get("MILVUS_PORT", "19530")
user = os.environ.get("MILVUS_USER", "root")
password = os.environ.get("MILVUS_PASSWORD", "user")
coll_name = os.environ.get("SLOW_DEMO_COLLECTION", "slow_demo_webui")
drop_first = os.environ.get("SLOW_DEMO_DROP_FIRST", "1") == "1"
num_vecs = int(os.environ.get("SLOW_DEMO_VECS", "12000"))
rounds = int(os.environ.get("SLOW_DEMO_ROUNDS", "8"))
duration_sec = float(os.environ.get("SLOW_DEMO_DURATION_SEC", "540"))  # 9 мин для нагрузочного теста / Web UI
log_interval = float(os.environ.get("SLOW_DEMO_LOG_INTERVAL_SEC", "10"))
for_slow_ui = os.environ.get("SLOW_DEMO_FOR_SLOW_REQUESTS_UI", "0") == "1"
dim = 128
nlist = 1024


def main() -> None:
    connections.connect("default", host=host, port=port, user=user, password=password)
    print(f"connected {host}:{port} user={user} collection={coll_name}")

    if utility.has_collection(coll_name):
        if drop_first:
            utility.drop_collection(coll_name)
            print(f"dropped existing collection {coll_name}")
        else:
            print(f"reuse collection {coll_name} (no drop)")
            coll = Collection(coll_name)
            coll.load()
            entities = coll.num_entities
            _heavy_searches(coll, duration_sec, rounds, log_interval, entities, nlist, for_slow_ui)
            if for_slow_ui:
                print(
                    "Slow Requests: нужен helm upgrade с proxy.slowQuerySpanInSeconds "
                    "(values-kind-localpath.yaml, tests/SLOW_QUERY_WEBUI.md)."
                )
            return

    fields = [
        FieldSchema(name="pk", dtype=DataType.INT64, is_primary=True, auto_id=False),
        FieldSchema(name="embedding", dtype=DataType.FLOAT_VECTOR, dim=dim),
    ]
    schema = CollectionSchema(fields, description="slow query demo for Web UI")
    coll = Collection(coll_name, schema)

    ids = list(range(num_vecs))
    vectors = [[random.random() for _ in range(dim)] for _ in range(num_vecs)]
    print(f"inserting {num_vecs} vectors dim={dim} ...")
    t0 = time.perf_counter()
    coll.insert([ids, vectors])
    coll.flush()
    print(f"flush done in {time.perf_counter() - t0:.2f}s")

    idx = {
        "index_type": "IVF_FLAT",
        "metric_type": "L2",
        "params": {"nlist": nlist},
    }
    print(f"building index IVF_FLAT nlist={nlist} ...")
    t1 = time.perf_counter()
    coll.create_index("embedding", idx)
    print(f"index build submitted/wait in {time.perf_counter() - t1:.2f}s (async on server)")

    coll.load()
    print("collection load() done")

    _heavy_searches(coll, duration_sec, rounds, log_interval, num_vecs, nlist, for_slow_ui)
    print("---")
    print("Откройте Web UI → разделы мониторинга / query (см. tests/SLOW_QUERY_WEBUI.md).")
    if for_slow_ui:
        print(
            "Slow Requests: нужен helm upgrade с proxy.slowQuerySpanInSeconds (см. values-kind-localpath.yaml и tests/SLOW_QUERY_WEBUI.md)."
        )
    print(f"Коллекция `{coll_name}` оставлена для просмотра метаданных; удалить:")
    print(f"  python3 -c \"from pymilvus import utility; utility.drop_collection('{coll_name}')\"")


def _heavy_searches(
    coll: Collection,
    duration_sec: float,
    rounds: int,
    log_interval_sec: float,
    num_entities: int,
    nlist_val: int,
    for_slow_requests_ui: bool,
) -> None:
    q = [[random.random() for _ in range(dim)]]
    if for_slow_requests_ui:
        nprobe = nlist_val
        limit = min(16384, max(2, num_entities))
        warmup_nprobe = min(64, nlist_val)
    else:
        nprobe = min(512, nlist_val)
        limit = 1500
        warmup_nprobe = 32
    # Разогрев
    coll.search(
        q,
        "embedding",
        {"metric_type": "L2", "params": {"nprobe": warmup_nprobe}},
        limit=50,
    )
    if duration_sec > 0:
        deadline = time.monotonic() + duration_sec
        mode = "Slow Requests UI (full nprobe, high limit)" if for_slow_requests_ui else "standard heavy"
        print(
            f"starting heavy searches for {duration_sec:.0f}s (~{duration_sec / 60:.1f} min), "
            f"mode={mode}, nprobe={nprobe} limit={limit} — смотрите Web UI / Slow Requests"
        )
        i = 0
        last_log = time.monotonic()
        searches_since_log = 0
        sum_dt = 0.0
        phase_start = time.monotonic()
        while time.monotonic() < deadline:
            t0 = time.perf_counter()
            coll.search(
                q,
                "embedding",
                {"metric_type": "L2", "params": {"nprobe": nprobe}},
                limit=limit,
            )
            dt = time.perf_counter() - t0
            i += 1
            searches_since_log += 1
            sum_dt += dt
            now = time.monotonic()
            if now - last_log >= log_interval_sec:
                elapsed = now - phase_start
                avg = sum_dt / searches_since_log if searches_since_log else 0.0
                remaining = max(0.0, deadline - now)
                print(
                    f"heavy_search progress: {i} total, last {log_interval_sec:.0f}s: "
                    f"{searches_since_log} searches, avg_client_sec={avg:.4f}, "
                    f"elapsed={elapsed:.0f}s, remaining~{remaining:.0f}s"
                )
                last_log = now
                searches_since_log = 0
                sum_dt = 0.0
        print(
            f"heavy_search phase done: {i} searches in {duration_sec:.0f}s "
            f"(nprobe={nprobe} limit={limit})"
        )
        return

    mode = "Slow Requests UI" if for_slow_requests_ui else "standard"
    print(f"starting {rounds} heavy searches (SLOW_DEMO_DURATION_SEC=0, {mode}, nprobe={nprobe} limit={limit})")
    for i in range(rounds):
        t0 = time.perf_counter()
        coll.search(
            q,
            "embedding",
            {"metric_type": "L2", "params": {"nprobe": nprobe}},
            limit=limit,
        )
        dt = time.perf_counter() - t0
        print(f"heavy_search i={i + 1}/{rounds} duration_sec={dt:.3f} nprobe={nprobe} limit={limit}")


if __name__ == "__main__":
    main()
