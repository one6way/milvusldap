# Сессия: демо нагрузки Milvus Web UI / Slow Requests

| Поле | Значение |
|------|----------|
| Дата | 2026-03-28 |
| Итог | **Успешно** — прогон завершён по плану, проверка в UI возможна в окне ~9 минут |
| Контекст | `kind-milvus-local`, namespace `milvus` |

## Что выполнялось

1. **Helm:** `values/values-kind-localpath.yaml` с `proxy.slowQuerySpanInSeconds: 0.015` — запросы дольше порога попадают в панель **Slow Requests**.
2. **Демо:** `tests/milvus_simulate_slow_queries.py` с `SLOW_DEMO_DURATION_SEC=540` (~9 мин фазы search), `SLOW_DEMO_FOR_SLOW_REQUESTS_UI=1` (nprobe=nlist, высокий limit).
3. **Доступ:** `kubectl port-forward` на **19530** (gRPC) и **9091** (Web UI `/webui`).

Запуск в фоне с логом: `PYTHONUNBUFFERED=1` + `python -u`, вывод в `/tmp/milvus_slow_demo.log` (при повторе сессии).

## Результат

- Нагрузочная фаза отрабатывала штатно (прогресс в логе: `heavy_search progress`, `avg_client_sec` и т.д.).
- Ручная сессия просмотра в панели **Slow Requests** / мониторинге — **без сбоев**; тест по согласованию **остановлен**, фоновые процессы демо сняты.

## Автоматический отчёт kubectl (после сессии)

Файл: **`milvus-test-report-20260328-234248.md`**

| PASS | FAIL |
|------|------|
| 8 | 0 |

Кейсы T1–T8: кластер в состоянии **Available**, сервисы, health, TCP 19530, логи proxy/mixcoord, PVC — **PASS**.

## Ссылки

- `tests/SLOW_QUERY_WEBUI.md` — порог Slow Requests, команды.
- `tests/milvus_simulate_slow_queries.py` — параметры демо.
- `tests/run_milvus_test_report.sh` — регулярные отчёты в `tests/reports/`.
