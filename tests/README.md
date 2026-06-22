# Тесты Milvus и отчёты

## Папка `tests/reports/`

Markdown-артефакты прогонов лежат в **`reports/`**. Назначение файлов, шаблоны имён и работа с `.gitignore` — **`reports/README.md`**.

## Быстрый запуск (только kubectl, без Python SDK)

Из корня `milvus-airgap`:

```bash
chmod +x tests/run_milvus_test_report.sh
./tests/run_milvus_test_report.sh
```

Отчёт: `tests/reports/milvus-test-report-<timestamp>.md` — таблицы, **PASS/FAIL**, фрагменты вывода и **логов** proxy/mixcoord.

Пример зафиксированного прогона (сводка, типичные фрагменты логов T6/T7/T9–T11): **`tests/TEST_RUN_DOCUMENTED_SAMPLE.md`**.

## Расширенный тест PyMilvus (T9)

1. В одном терминале: `kubectl port-forward -n milvus svc/milvus 19530:19530`
2. Установка: `pip install -r tests/requirements-tests.txt`
3. Запуск: `RUN_PYMILVUS=1 ./tests/run_milvus_test_report.sh`

Переменные: `MILVUS_HOST`, `MILVUS_PORT`, `MILVUS_USER`, `MILVUS_PASSWORD` (см. `milvus_pymilvus_version.py`).

## Переменные

| Имя | По умолчанию | Смысл |
|-----|--------------|--------|
| `NAMESPACE` | `milvus` | Namespace кластера |
| `REPORT_DIR` | `tests/reports` | Куда писать Markdown |
| `RUN_PYMILVUS` | `0` | `1` — выполнить T9 |
| `RUN_SLOW_QUERY_DEMO` | `0` | `1` — T10–T11: тяжёлые search **~9 мин** (`SLOW_DEMO_DURATION_SEC`, по умолчанию 540) + логи querynode (нужен **19530** и `pymilvus`). Быстрый отчёт: `SLOW_DEMO_DURATION_SEC=0`. Для панели **Slow Requests** в Web UI: `values-kind-localpath.yaml` → `proxy.slowQuerySpanInSeconds` + `helm upgrade`; при T10 выставляется `SLOW_DEMO_FOR_SLOW_REQUESTS_UI=1` (отключить: `SLOW_DEMO_FOR_SLOW_REQUESTS_UI=0`) |

## Демо slow request → Web UI

Скрипт **`milvus_simulate_slow_queries.py`** и инструкция **`SLOW_QUERY_WEBUI.md`** — как сгенерировать заметную latency и что смотреть на **http://…:9091/webui**.
