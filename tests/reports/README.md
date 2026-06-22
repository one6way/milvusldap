# Артефакты отчётов тестов Milvus

Сюда пишет скрипт **`../run_milvus_test_report.sh`** и сюда же можно класть **ручные** отчёты по сессиям (Web UI, нагрузка).

## Имена файлов

| Шаблон | Кто создаёт | Содержание |
|--------|-------------|------------|
| `milvus-test-report-<YYYYMMDD-HHMMSS>.md` | `run_milvus_test_report.sh` | T1–T8 всегда; T9–T11 при `RUN_PYMILVUS=1` / `RUN_SLOW_QUERY_DEMO=1`. Таблицы PASS/FAIL, время, до 80 строк вывода на кейс. |
| `milvus-webui-demo-session-<дата>.md` | вручную (по итогу демо) | Краткий итог сессии: helm, демо ~9 мин, Slow Requests, ссылка на последний автотест. |

## Документация прогонов (не в этой папке)

- **`../README.md`** — как запускать отчёт, переменные окружения, PyMilvus, T10–T11.
- **`../TEST_RUN_DOCUMENTED_SAMPLE.md`** — пример разобранного прогона с фрагментами логов.
- **`../SLOW_QUERY_WEBUI.md`** — Web UI **9091**, панель **Slow Requests**, `proxy.slowQuerySpanInSeconds`.

## `.gitignore` в этой папке

Файл **`.gitignore`** игнорирует `milvus-test-report-*.md`, чтобы не засорять VCS сотнями прогонов. Ручные отчёты вроде `milvus-webui-demo-session-*.md` шаблоном **не** игнорируются — коммитьте или переносите в архив по политике проекта.

При переносе каталога `milvus-airgap` в другой репозиторий: скопируйте вместе с `tests/reports/.gitignore` или поправьте правила под свой Git.
