# Пример прогона тестов и фрагменты логов

Зафиксированный прогон на **kind** (`kubectl context`: `kind-milvus-local`, namespace `milvus`), **2026-03-28**. Полный артефакт: `tests/reports/milvus-test-report-20260328-231101.md`.

## Команды

Базовый прогон (T1–T8, без Python):

```bash
cd milvus-airgap
./tests/run_milvus_test_report.sh
```

Полный прогон с PyMilvus и демо нагрузки (нужен **port-forward 19530**; ниже длительность демо **45 с** только для короткой фиксации лога; штатно по умолчанию **540 с = 9 мин**):

```bash
kubectl port-forward -n milvus svc/milvus 19530:19530   # отдельный терминал
cd milvus-airgap
python3 -m venv tests/.venv
tests/.venv/bin/pip install -r tests/requirements-tests.txt
PATH="tests/.venv/bin:$PATH" \
  RUN_PYMILVUS=1 RUN_SLOW_QUERY_DEMO=1 SLOW_DEMO_DURATION_SEC=45 \
  ./tests/run_milvus_test_report.sh
```

На macOS с PEP 668 у системного Python удобнее ставить зависимости только в `tests/.venv`, как выше.

## Сводка результатов

| Кейс | Описание | Статус | Время (с) |
|------|----------|--------|-----------|
| T1 | Критичные Deployment в Available | PASS | 1 |
| T2 | Сводка pod | PASS | 0 |
| T3 | Сервисы milvus и attu | PASS | 0 |
| T4 | Health proxy 9091/healthz | PASS | 0 |
| T5 | TCP milvus:19530 (busybox) | PASS | 2 |
| T6 | Логи milvus-proxy (tail) | PASS | 0 |
| T7 | Логи milvus-mixcoord (tail) | PASS | 0 |
| T8 | PVC Bound | PASS | 0 |
| T9 | PyMilvus: версия сервера | PASS | 1 |
| T10 | Демо тяжёлых vector search | PASS | 53 |
| T11 | Логи milvus-querynode после нагрузки | PASS | 0 |

**Итог:** 11 PASS, 0 FAIL.

## T9 — PyMilvus (фрагмент stdout)

```text
server_version=v2.5.0
collections_count=1
collections_sample=['slow_demo_webui']
```

## T10 — Демо нагрузки (фрагмент stdout)

Режим по длительности: строки прогресса каждые `SLOW_DEMO_LOG_INTERVAL_SEC` (10 с), затем итог фазы.

```text
connected 127.0.0.1:19530 user=root collection=slow_demo_webui
dropped existing collection slow_demo_webui
inserting 12000 vectors dim=128 ...
flush done in 3.19s
building index IVF_FLAT nlist=1024 ...
index build submitted/wait in 1.60s (async on server)
collection load() done
starting heavy searches for 45s (~0.8 min), nprobe=512 limit=1500 — смотрите latency в Web UI
heavy_search progress: 636 total, last 10s: 636 searches, avg_client_sec=0.0157, elapsed=10s, remaining~35s
heavy_search progress: 1334 total, last 10s: 698 searches, avg_client_sec=0.0143, elapsed=20s, remaining~25s
heavy_search progress: 1935 total, last 10s: 601 searches, avg_client_sec=0.0167, elapsed=30s, remaining~15s
heavy_search progress: 2536 total, last 10s: 601 searches, avg_client_sec=0.0167, elapsed=40s, remaining~5s
heavy_search phase done: 2828 searches in 45s (nprobe=512 limit=1500)
```

При `SLOW_DEMO_DURATION_SEC=540` (по умолчанию) формат тот же, фаза длится **9 минут**; для CI/чернового отчёта используйте `SLOW_DEMO_DURATION_SEC=0` (только 8 поисков).

## T6 — milvus-proxy (типичный фрагмент логов)

Повторяющиеся **WARN** `get disk usage failed` на kind часто связаны с метриками диска в контейнере; на **health** и работу API это не указывает.

```text
[2026/03/28 20:10:01.985 +00:00] [WARN] [proxy/metrics_info.go:112] ["get disk usage failed"] [traceID=...] [error="no such file or directory"]
[2026/03/28 20:10:08.803 +00:00] [DEBUG] [metrics/thread.go:53] ["thread watcher observe thread num"] [threadNum=32]
```

## T7 — mixcoord после нагрузки (фрагмент)

Видна балансировка сегментов по query node и фоновые **WARN** disk metrics.

```text
[2026/03/28 20:10:49.493 +00:00] [INFO] [balance/score_based_balancer.go:514] ["node segment workload status"] [collectionID=465233986989595896] [replicaID=465234023328514049] [nodes="[\"{NodeID: 3, AssignedScore: 13200.000000, CurrentScore: 14520.000000, Priority: 1320}\"]"]
[2026/03/28 20:10:56.688 +00:00] [INFO] [datacoord/handler.go:436] ["channel seek position set from channel checkpoint meta"] [channel=by-dev-rootcoord-dml_0_465233986989595896v0] ...
```

## T11 — milvus-querynode (фрагмент после insert/load/search)

Загрузка индекса и сегмента, затем периодические **sync action** / обновление версии сегмента при активности коллекции.

```text
[2026/03/28 20:11:13.242 +00:00] [INFO] [segments/segment_loader.go:1023] ["load field binlogs done for sealed segment with index"] [collectionID=465233986990997598] ... [rowCount=12000] [fieldID=101] ... [load_duration=53.565573ms]
[2026/03/28 20:11:16.686 +00:00] [INFO] [delegator/distribution.go:313] ["Update readable segment version"] [partitions="[465233986990997599]"] [oldVersion=1774728672224897488] [newVersion=1774728673381733141] [growingSegmentNum=0] [sealedSegmentNum=1]
[2026/03/28 20:11:38.803 +00:00] [DEBUG] [metrics/thread.go:53] ["thread watcher observe thread num"] [threadNum=68]
```

## T4 — healthz (заметка)

Иногда перед `OK` в логе exec появляется сообщение **LD_PRELOAD** от динамического загрузчика — на результат проверки **OK** не влияет.

```text
ERROR: ld.so: object '/milvus/lib/' from LD_PRELOAD cannot be preloaded (cannot read file data): ignored.
OK
```
