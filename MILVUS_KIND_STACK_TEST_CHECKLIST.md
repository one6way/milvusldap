# Чеклист: kind + Milvus + Attu (после `90-bootstrap-full-stack-kind.sh`)

Используйте для регрессии и фиксации результатов тестов в документации.

## Предусловия

- Запущен **Docker Desktop** (или иной daemon с `kind`).
- Есть доступ в интернет (для `helm dependency update` и pull образов в online-сценарии).
- Из корня `milfus-main`: скрипт **90** при первом запуске вызывает **53** (сборка non-root) и **50** (artifacts), дальше грузит tar в kind **без** повторного `helm dependency update`.

```bash
chmod +x scripts/*.sh
./scripts/90-bootstrap-full-stack-kind.sh
```

См. также **`PREP_NONROOT_ONCE.md`**.

Ожидание: все pod в `milvus` в `Running`/`Ready`, Attu deployment доступен.

---

## Автоматические проверки (уже в скриптах)

| Шаг | Команда | Ожидание |
|-----|---------|----------|
| API / health | `./scripts/40-verify-milvus-api.sh` | `curl` на `9091/healthz` OK, порт `19530` открыт |
| Attu + Milvus | `./scripts/41-verify-attu-prereqs.sh` | Успешный вывод, подсказки host/user/password |
| Полный отчёт с логами | `./tests/run_milvus_test_report.sh` | Markdown в `tests/reports/milvus-test-report-*.md` (см. `tests/README.md`) |
| Slow search + Web UI | `python3 tests/milvus_simulate_slow_queries.py` + `tests/SLOW_QUERY_WEBUI.md` | Нагрузка на query node; смотреть `/webui` на **9091**; в отчёт: `RUN_SLOW_QUERY_DEMO=1 ./tests/run_milvus_test_report.sh` |

---

## Ручные проверки (зафиксировать в отчёте)

| # | Действие | Команда / URL | Ожидание | Результат (pass/fail) |
|---|----------|---------------|----------|------------------------|
| 1 | Состав кластера | `kubectl get pods -n milvus` | proxy, mixcoord, query/datanode/indexnode, etcd, minio, pulsar\* Ready | |
| 2 | Сервисы | `kubectl get svc -n milvus` | `milvus` с портами 19530 и 9091 (при `metrics.enabled: true`) | |
| 3 | Attu UI | `kubectl port-forward -n milvus svc/attu 3000:3000` → `http://127.0.0.1:3000` | Страница логина/подключения открывается | |
| 4 | Подключение Attu к Milvus | В форме: host `milvus`, порт `19530`, учётка из values (см. `ATTU.md`) | Подключение без ошибки | |
| 5 | Milvus Web UI (браузер) | Второй терминал: `kubectl port-forward -n milvus svc/milvus 9091:9091` → `http://127.0.0.1:9091/webui` | UI открывается (не использовать ссылку из Attu на `http://milvus:9091/...` с хоста) | |
| 6 | RBAC (если включён) | После `./scripts/45-bootstrap-milvus-native-rbac.sh` — повтор п.4 с `admin` | По `MILVUS_NATIVE_RBAC.md` | |

---

## Остановка стека

```bash
kind delete cluster --name milvus-local
```

---

## Связанные документы

- `ATTU.md` — Attu, Web UI, port-forward.
- `MILVUS_PODS_EXPLAINED.md` — роли компонентов.
- `MILVUS_COMPONENT_FAILURE_RUNBOOK.md` — порядок восстановления при сбоях.
