# Демо: «медленный» search и что смотреть в Milvus Web UI

Документ привязан к тестовому коду: **`tests/milvus_simulate_slow_queries.py`**.

## Идея

Скрипт создаёт коллекцию **`slow_demo_webui`** (или имя из `SLOW_DEMO_COLLECTION`), вставляет десятки тысяч векторов, строит **IVF_FLAT** и выполняет несколько **search** с большим **`nprobe`** и **`limit`** — нагрузка на **query node** растёт, время ответа заметно увеличивается. Это удобно смотреть в встроенном **Web UI** Milvus (`/webui` на порту **9091**).

## Подготовка

1. Доступ к gRPC **19530** с машины, где запускаете Python:
   ```bash
   kubectl port-forward -n milvus svc/milvus 19530:19530
   ```
2. Зависимости:
   ```bash
   pip install -r tests/requirements-tests.txt
   ```

## Запуск демо

```bash
cd milfus-main
python3 tests/milvus_simulate_slow_queries.py
```

В stdout появятся строки вида `heavy_search i=... duration_sec=...` — это **клиентская** длительность; в UI могут быть агрегаты по нодам.

Параметры (опционально):

| Переменная | По умолчанию | Смысл |
|------------|--------------|--------|
| `SLOW_DEMO_VECS` | 12000 | Объём insert |
| `SLOW_DEMO_DURATION_SEC` | 540 | Сколько секунд подряд выполнять тяжёлые search (**9 мин** для Web UI / нагрузочного теста). `0` — только `SLOW_DEMO_ROUNDS` раз (короткий прогон) |
| `SLOW_DEMO_ROUNDS` | 8 | При `SLOW_DEMO_DURATION_SEC=0`: число тяжёлых search |
| `SLOW_DEMO_LOG_INTERVAL_SEC` | 10 | В режиме по длительности: период строк прогресса в stdout |
| `SLOW_DEMO_DROP_FIRST` | 1 | Пересоздать коллекцию |
| `SLOW_DEMO_FOR_SLOW_REQUESTS_UI` | `0` вручную, **`1` из `run_milvus_test_report.sh` при T10** | `nprobe=nlist`, `limit` до 16384 — тяжелее search для панели Slow Requests (вместе с низким `slowQuerySpanInSeconds`) |
| `MILVUS_HOST` / `MILVUS_PORT` | 127.0.0.1 / 19530 | Подключение |

## Web UI: куда смотреть

Откройте **http://&lt;хост&gt;:9091/webui** (на kind с Mac часто нужен `port-forward` или `kind` `extraPortMappings`, см. `ATTU.md` / `values-kind-nodeport.yaml`).

В интерфейсе Milvus 2.x обычно есть (названия вкладок могут слегка отличаться по версии):

1. **Monitoring / Metrics** — загрузка компонентов, задержки, QPS (после серии search графики/цифры должны «ожить»).
2. **Query / QueryNode** (если есть) — активность поиска.
3. При необходимости сравните с логами proxy:
   ```bash
   kubectl logs -n milvus deploy/milvus-querynode --tail=100
   kubectl logs -n milvus deploy/milvus-proxy --tail=80
   ```

Пока идут `heavy_search`, обновляйте страницу Web UI — так проще поймать всплеск latency.

## Slow Requests — почему «No Data»

Таблица **Slow Requests** заполняется только запросами, у которых **время на стороне proxy** больше порога **`proxy.slowQuerySpanInSeconds`** (в документации Milvus по умолчанию порядка **нескольких секунд**). Демо-скрипт на маленькой коллекции даёт search **десятки миллисекунд** — они **не считаются медленными**, поэтому строка *Notice: Slow request in the last 5 minutes* может быть при пустой таблице, а колонки остаются **No Data**.

Что сделать:

1. **Kind-профиль** — в `values/values-kind-localpath.yaml` уже задано **`proxy.slowQuerySpanInSeconds: 0.015`** (15 ms). Выполните **`helm upgrade`** Milvus с этим файлом и обновите Web UI в окне *last 5 minutes* во время прогона. Для прода порог верните по [доке Milvus](https://milvus.io/docs/configure_proxy.md) или уберите блок `proxy`.
2. **Без kind-values** — в `extraConfigFiles.user.yaml` добавьте тот же блок `proxy:` и сделайте upgrade.
3. **Не трогая порог** — добиться реальной задержки **выше дефолтного порога** (секунды): очень большая коллекция, FLAT, тяжёлый запрос.
4. Учитывать окно **last 5 minutes**: откройте раздел и обновляйте страницу **пока** идёт нагрузка из скрипта.

Скрипт с **`SLOW_DEMO_FOR_SLOW_REQUESTS_UI=1`** (по умолчанию при `RUN_SLOW_QUERY_DEMO=1` в `run_milvus_test_report.sh`) усиливает параметры search под эту панель при низком пороге.

См. также: [configure proxy](https://milvus.io/docs/configure_proxy.md) (`slowQuerySpanInSeconds`).

## Включение в отчёт тестов

Автоматически добавить вывод демо в Markdown-отчёт:

```bash
RUN_SLOW_QUERY_DEMO=1 ./tests/run_milvus_test_report.sh
```

По умолчанию фаза тяжёлых search длится **~9 минут** (`SLOW_DEMO_DURATION_SEC=540`). Короткий прогон отчёта: `SLOW_DEMO_DURATION_SEC=0`.

Нужны **port-forward 19530** и установленный **pymilvus** (как для `RUN_PYMILVUS=1`). Если демо не запустилось, в отчёте будет фрагмент stderr.

## Уборка

Удалить демо-коллекцию:

```bash
python3 -c "
from pymilvus import connections, utility
connections.connect('default', host='127.0.0.1', port='19530', user='root', password='user')
utility.drop_collection('slow_demo_webui')
"
```

(Параметры подключения подставьте свои.)
