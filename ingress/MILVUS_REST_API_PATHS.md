# Milvus REST API — все пути (Milvus 2.5.0)

Источник: исходники `milvus-io/milvus` v2.5.0

- `internal/distributed/proxy/service.go` — mount: `Group("/v1")`, `Group("/v2/vectordb")`
- `internal/distributed/proxy/httpserver/handler_v2.go` — `routeToMethod`
- `internal/distributed/proxy/httpserver/handler_v1.go` + `constant.go` — v1 legacy
- `internal/distributed/proxy/httpserver/handler.go` — `/api/v1/*` на metrics-порту

**Порт REST:** `19530` · **Требуется:** `proxy.http.enabled: true` · **Ingress:** `milvus-rest-ingress.yaml`

Документация: [RESTful API v2.5.x](https://milvus.io/api-reference/restful/v2.5.x/About.md)

---

## REST v2 (рекомендуемый)

Префикс: **`/v2/vectordb/`** · **Все endpoint'ы — POST** · JSON body · Auth: `Authorization: Bearer user:password`

### collections — управление коллекциями (таблицами векторных данных)

| Путь | Method | Назначение |
|------|--------|------------|
| `/v2/vectordb/collections/list` | POST | Список коллекций в указанной БД |
| `/v2/vectordb/collections/has` | POST | Проверить, существует ли коллекция |
| `/v2/vectordb/collections/describe` | POST | Схема коллекции: поля, типы, параметры |
| `/v2/vectordb/collections/get_stats` | POST | Статистика коллекции (число строк и т.п.) |
| `/v2/vectordb/collections/get_load_state` | POST | Состояние загрузки коллекции в память (loaded / not loaded) |
| `/v2/vectordb/collections/create` | POST | Создать новую коллекцию с заданной схемой |
| `/v2/vectordb/collections/drop` | POST | Удалить коллекцию и все её данные |
| `/v2/vectordb/collections/truncate` | POST | Очистить все данные коллекции, сохранив схему |
| `/v2/vectordb/collections/rename` | POST | Переименовать коллекцию |
| `/v2/vectordb/collections/load` | POST | Загрузить коллекцию в память query node для поиска |
| `/v2/vectordb/collections/refresh_load` | POST | Перезагрузить коллекцию в память (актуализировать сегменты) |
| `/v2/vectordb/collections/release` | POST | Выгрузить коллекцию из памяти |
| `/v2/vectordb/collections/alter_properties` | POST | Изменить properties коллекции (TTL, consistency и др.) |
| `/v2/vectordb/collections/add_function` | POST | Добавить function (например BM25) к коллекции |
| `/v2/vectordb/collections/alter_function` | POST | Изменить function коллекции |
| `/v2/vectordb/collections/drop_function` | POST | Удалить function из коллекции |
| `/v2/vectordb/collections/drop_properties` | POST | Удалить properties коллекции |
| `/v2/vectordb/collections/compact` | POST | Запустить ручную компакцию сегментов коллекции |
| `/v2/vectordb/collections/get_compaction_state` | POST | Статус компакции коллекции |
| `/v2/vectordb/collections/flush` | POST | Сбросить буферизованные данные коллекции на диск |
| `/v2/vectordb/collections/fields/alter_properties` | POST | Изменить properties отдельного поля коллекции |
| `/v2/vectordb/collections/fields/add` | POST | Добавить новое поле в существующую коллекцию |

### databases — логические базы данных Milvus

| Путь | Method | Назначение |
|------|--------|------------|
| `/v2/vectordb/databases/list` | POST | Список всех баз данных в кластере |
| `/v2/vectordb/databases/create` | POST | Создать новую БД |
| `/v2/vectordb/databases/drop` | POST | Удалить БД и все коллекции в ней |
| `/v2/vectordb/databases/describe` | POST | Описание БД и её properties |
| `/v2/vectordb/databases/alter` | POST | Изменить properties БД |
| `/v2/vectordb/databases/alter_properties` | POST | Изменить properties БД (alias для alter) |
| `/v2/vectordb/databases/drop_properties` | POST | Удалить properties БД |

### entities — операции с данными (векторы и скалярные поля)

| Путь | Method | Назначение |
|------|--------|------------|
| `/v2/vectordb/entities/insert` | POST | Вставить новые записи (векторы + метаданные) |
| `/v2/vectordb/entities/upsert` | POST | Вставить или обновить записи по primary key |
| `/v2/vectordb/entities/search` | POST | Векторный поиск k ближайших соседей (ANN) |
| `/v2/vectordb/entities/query` | POST | Скалярная фильтрация по выражению (без векторного поиска) |
| `/v2/vectordb/entities/get` | POST | Получить записи по primary key (alias query) |
| `/v2/vectordb/entities/delete` | POST | Удалить записи по фильтру или primary key |
| `/v2/vectordb/entities/advanced_search` | POST | Расширенный гибридный поиск (несколько векторных полей / rerank) |
| `/v2/vectordb/entities/hybrid_search` | POST | Гибридный поиск: dense + sparse (BM25) в одном запросе |

### partitions — разделы внутри коллекции

| Путь | Method | Назначение |
|------|--------|------------|
| `/v2/vectordb/partitions/list` | POST | Список партиций коллекции |
| `/v2/vectordb/partitions/has` | POST | Проверить существование партиции |
| `/v2/vectordb/partitions/get_stats` | POST | Статистика партиции (число строк) |
| `/v2/vectordb/partitions/create` | POST | Создать партицию в коллекции |
| `/v2/vectordb/partitions/drop` | POST | Удалить партицию и её данные |
| `/v2/vectordb/partitions/load` | POST | Загрузить партиции в память |
| `/v2/vectordb/partitions/release` | POST | Выгрузить партиции из памяти |

### indexes — векторные и скалярные индексы

| Путь | Method | Назначение |
|------|--------|------------|
| `/v2/vectordb/indexes/list` | POST | Список индексов коллекции |
| `/v2/vectordb/indexes/describe` | POST | Параметры и состояние конкретного индекса |
| `/v2/vectordb/indexes/create` | POST | Создать индекс на поле (IVF, HNSW, и т.д.) |
| `/v2/vectordb/indexes/drop` | POST | Удалить индекс |
| `/v2/vectordb/indexes/alter_properties` | POST | Изменить properties индекса |
| `/v2/vectordb/indexes/drop_properties` | POST | Удалить properties индекса |

### users — пользователи и учётные записи (RBAC)

| Путь | Method | Назначение |
|------|--------|------------|
| `/v2/vectordb/users/list` | POST | Список пользователей |
| `/v2/vectordb/users/describe` | POST | Информация о пользователе и его ролях |
| `/v2/vectordb/users/create` | POST | Создать пользователя с паролем |
| `/v2/vectordb/users/update_password` | POST | Сменить пароль пользователя |
| `/v2/vectordb/users/drop` | POST | Удалить пользователя |
| `/v2/vectordb/users/grant_role` | POST | Назначить роль пользователю |
| `/v2/vectordb/users/revoke_role` | POST | Отозвать роль у пользователя |

### roles — роли и привилегии (RBAC)

| Путь | Method | Назначение |
|------|--------|------------|
| `/v2/vectordb/roles/list` | POST | Список ролей |
| `/v2/vectordb/roles/describe` | POST | Привилегии, назначенные роли |
| `/v2/vectordb/roles/create` | POST | Создать роль |
| `/v2/vectordb/roles/drop` | POST | Удалить роль |
| `/v2/vectordb/roles/grant_privilege` | POST | Выдать привилегию роли (v1 API привилегий) |
| `/v2/vectordb/roles/revoke_privilege` | POST | Отозвать привилегию у роли (v1) |
| `/v2/vectordb/roles/grant_privilege_v2` | POST | Выдать привилегию роли (v2, рекомендуемый) |
| `/v2/vectordb/roles/revoke_privilege_v2` | POST | Отозвать привилегию у роли (v2) |

### privilege_groups — группы привилегий

| Путь | Method | Назначение |
|------|--------|------------|
| `/v2/vectordb/privilege_groups/list` | POST | Список групп привилегий |
| `/v2/vectordb/privilege_groups/create` | POST | Создать группу привилегий |
| `/v2/vectordb/privilege_groups/drop` | POST | Удалить группу привилегий |
| `/v2/vectordb/privilege_groups/add_privileges_to_group` | POST | Добавить привилегии в группу |
| `/v2/vectordb/privilege_groups/remove_privileges_from_group` | POST | Убрать привилегии из группы |

### aliases — псевдонимы коллекций

| Путь | Method | Назначение |
|------|--------|------------|
| `/v2/vectordb/aliases/list` | POST | Список alias'ов |
| `/v2/vectordb/aliases/describe` | POST | На какую коллекцию указывает alias |
| `/v2/vectordb/aliases/create` | POST | Создать alias для коллекции |
| `/v2/vectordb/aliases/drop` | POST | Удалить alias |
| `/v2/vectordb/aliases/alter` | POST | Переназначить alias на другую коллекцию |

### jobs/import — массовый импорт данных

| Путь | Method | Назначение |
|------|--------|------------|
| `/v2/vectordb/jobs/import/list` | POST | Список задач импорта |
| `/v2/vectordb/jobs/import/create` | POST | Создать задачу импорта из файлов (S3/MinIO и т.д.) |
| `/v2/vectordb/jobs/import/get_progress` | POST | Прогресс задачи импорта |
| `/v2/vectordb/jobs/import/describe` | POST | Детали и прогресс задачи импорта (alias get_progress) |

### resource_groups — группы ресурсов query node

| Путь | Method | Назначение |
|------|--------|------------|
| `/v2/vectordb/resource_groups/list` | POST | Список resource group |
| `/v2/vectordb/resource_groups/create` | POST | Создать resource group |
| `/v2/vectordb/resource_groups/drop` | POST | Удалить resource group |
| `/v2/vectordb/resource_groups/describe` | POST | Описание resource group (ноды, capacity) |
| `/v2/vectordb/resource_groups/alter` | POST | Изменить конфигурацию resource group |
| `/v2/vectordb/resource_groups/transfer_replica` | POST | Перенести реплику сегмента между resource group |

### segments / quotacenter / common — диагностика и утилиты

| Путь | Method | Назначение |
|------|--------|------------|
| `/v2/vectordb/segments/describe` | POST | Информация о сегментах коллекции (для отладки) |
| `/v2/vectordb/quotacenter/describe` | POST | Метрики квот и лимитов кластера |
| `/v2/vectordb/common/run_analyzer` | POST | Запустить text analyzer (токенизация для BM25 / full-text) |

### Пример v2

```bash
curl -X POST "https://milvus-rest.example.ru/v2/vectordb/collections/list" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer root:PASSWORD" \
  -d '{"dbName":"default"}'
```

---

## REST v1 (legacy, deprecated)

Префикс: **`/v1/vector/`** · Milvus рекомендует переходить на v2

| Путь | Method | Назначение |
|------|--------|------------|
| `/v1/vector/collections` | GET | Список коллекций |
| `/v1/vector/collections/create` | POST | Создать коллекцию |
| `/v1/vector/collections/describe` | GET | Описание схемы коллекции |
| `/v1/vector/collections/drop` | POST | Удалить коллекцию |
| `/v1/vector/insert` | POST | Вставить векторы |
| `/v1/vector/upsert` | POST | Upsert векторов |
| `/v1/vector/search` | POST | Векторный поиск |
| `/v1/vector/get` | POST | Получить записи по ID |
| `/v1/vector/query` | POST | Скалярный запрос с фильтром |
| `/v1/vector/delete` | POST | Удалить записи |

---

## Порт 9091 — не REST Ingress (`milvus-rest-ingress.yaml`)

### Web UI (`milvus-ui-ingress.yaml`)

| Путь | Method | Назначение |
|------|--------|------------|
| `/webui/` | GET | Встроенный Web UI Milvus: мониторинг, Slow Requests, метаданные |

### `/api/v1/*` — legacy admin HTTP API (metrics-порт)

Старый REST-стиль, **не** публикуется в наших Ingress. Справочно — что есть на 9091:

| Путь | Method | Назначение |
|------|--------|------------|
| `/api/v1/health` | GET | Healthcheck HTTP-сервера |
| `/api/v1/dummy` | POST | Тестовый endpoint (latency check) |
| `/api/v1/collection` | POST | Создать коллекцию (legacy формат) |
| `/api/v1/collection` | DELETE | Удалить коллекцию |
| `/api/v1/collection/existence` | GET | Проверить существование коллекции |
| `/api/v1/collection` | GET | Описать коллекцию |
| `/api/v1/collection/load` | POST | Загрузить коллекцию в память |
| `/api/v1/collection/load` | DELETE | Выгрузить коллекцию из памяти |
| `/api/v1/collection/statistics` | GET | Статистика коллекции |
| `/api/v1/collections` | GET | Список коллекций |
| `/api/v1/partition` | POST | Создать партицию |
| `/api/v1/partition` | DELETE | Удалить партицию |
| `/api/v1/partition/existence` | GET | Проверить существование партиции |
| `/api/v1/partitions/load` | POST | Загрузить партиции |
| `/api/v1/partitions/load` | DELETE | Выгрузить партиции |
| `/api/v1/partition/statistics` | GET | Статистика партиции |
| `/api/v1/partitions` | GET | Список партиций |
| `/api/v1/alias` | POST | Создать alias |
| `/api/v1/alias` | DELETE | Удалить alias |
| `/api/v1/alias` | PATCH | Изменить alias |
| `/api/v1/index` | POST | Создать индекс |
| `/api/v1/index` | GET | Описать индекс |
| `/api/v1/index/state` | GET | Состояние индекса |
| `/api/v1/index/progress` | GET | Прогресс построения индекса |
| `/api/v1/index` | DELETE | Удалить индекс |
| `/api/v1/entities` | POST | Вставить данные |
| `/api/v1/entities` | DELETE | Удалить данные |
| `/api/v1/search` | POST | Векторный поиск |
| `/api/v1/query` | POST | Скалярный запрос |
| `/api/v1/persist` | POST | Flush данных на диск |
| `/api/v1/distance` | GET | Вычислить расстояние между векторами |
| `/api/v1/persist/state` | GET | Состояние flush |
| `/api/v1/persist/segment-info` | GET | Информация о persistent сегментах |
| `/api/v1/query-segment-info` | GET | Информация о query сегментах |
| `/api/v1/replicas` | GET | Информация о репликах коллекции |
| `/api/v1/metrics` | GET | Внутренние метрики Milvus |
| `/api/v1/load-balance` | POST | Балансировка нагрузки между query node |
| `/api/v1/compaction/state` | GET | Состояние компакции |
| `/api/v1/compaction/plans` | GET | Планы компакции |
| `/api/v1/compaction` | POST | Запустить компакцию |
| `/api/v1/import` | POST | Импорт данных |
| `/api/v1/import/state` | GET | Состояние импорта |
| `/api/v1/import/tasks` | GET | Список задач импорта |
| `/api/v1/credential` | POST | Создать пользователя |
| `/api/v1/credential` | PATCH | Обновить пароль |
| `/api/v1/credential` | DELETE | Удалить пользователя |
| `/api/v1/credential/users` | GET | Список пользователей |

---

## gRPC (`milvus-grpc-ingress.yaml`)

Порт `19530`, протокол gRPC — основной API для pymilvus/SDK (insert, search, DDL и всё остальное через gRPC, не HTTP-пути).

```python
connections.connect("default", uri="https://<GRPC_HOST>:443", token="root:PASSWORD")
```

---

## Типовые ошибки

| Запрос | Результат |
|--------|-----------|
| GET на `/v2/vectordb/...` | `404 page not found` (v2 только POST) |
| `/v2/collections/list` без `vectordb` | `404 page not found` |
| `/api/v1/...` через REST Ingress (19530) | `404 page not found` |
| `proxy.http.enabled: false` | REST на 19530 не работает |

---

## Сводка Ingress

| Ingress | Host | Пути | Порт |
|---------|------|------|------|
| `milvus-rest` | `milvus-rest.*` | `/v2/vectordb`, `/v1` | 19530 |
| `milvus-ui` | `milvus-ui.*` | `/webui` | 9091 |
| `milvus-grpc` | `milvus-grpc.*` | `/` (gRPC) | 19530 |

См. также: [README.md](README.md)
