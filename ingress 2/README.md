# Milvus Ingress: UI / REST / gRPC

Готовые манифесты для nginx ingress-controller. Пути и порты сверены с **Milvus 2.5.0** (`internal/distributed/proxy/service.go`) и [официальной докой Ingress](https://milvus.io/docs/v2.5.x/ingress.md).

## Состав папки

| Файл | Ingress | Порт Service | Протокол | Назначение |
|------|---------|--------------|----------|------------|
| `milvus-ui-ingress.yaml` | `milvus-ui` | **9091** | HTTP | Web UI → `/webui/` |
| `milvus-rest-ingress.yaml` | `milvus-rest` | **19530** | HTTP | REST `/v2/vectordb`, `/v1` |
| `milvus-grpc-ingress.yaml` | `milvus-grpc` | **19530** | gRPC | pymilvus / SDK |

Почему три Ingress: Helm-ingress чарта Milvus смотрит на **19530** без разделения REST/gRPC; Web UI на **9091**.

## Быстрый старт

### 1. Helm (включить HTTP на proxy)

```bash
cd ..   # milfus-main
helm upgrade --install milvus ./chart/milvus -n milvus \
  -f values/values-kind-localpath.yaml \
  -f values/values-webui-ingress.yaml
```

Нужно: `proxy.http.enabled: true`, `metrics.enabled: true` (порт 9091 на Service).

### 2. Заменить плейсхолдеры

Во всех трёх `.yaml`:

| Плейсхолдер | Пример |
|-------------|--------|
| `{{ NAMESPACE }}` | `milvus` |
| `{{ INGRESS_CLASS }}` | `nginx` |
| `{{ MILVUS_UI_HOST }}` | `milvus-ui.corp.local` |
| `{{ MILVUS_REST_HOST }}` | `milvus-rest.corp.local` |
| `{{ MILVUS_GRPC_HOST }}` | `milvus-grpc.corp.local` |

Доступ **по IP без DNS** — раскомментируйте блок `rule` без `host` в нужном файле.

REST и gRPC могут использовать **один host** (разведение по path). UI — отдельный host (другой порт backend).

### 3. DNS

```
<MILVUS_*_HOST>  →  EXTERNAL-IP ingress-контроллера
```

```bash
kubectl get svc -A | grep -i ingress
```

### 4. Apply

```bash
kubectl apply -f milvus-ui-ingress.yaml
kubectl apply -f milvus-rest-ingress.yaml
kubectl apply -f milvus-grpc-ingress.yaml
```

## REST API — официальные пути

**v2 (рекомендуемый):** `POST http://<host>/v2/vectordb/<category>/<action>`

Категории под `/v2/vectordb/`: `databases`, `collections`, `entities`, `partitions`, `users`, `roles`, `privilege_groups`, `indexes`, `aliases`, `jobs/import`, `resource_groups`, `segments`, `quotacenter`, `common`.

Пример:

```bash
curl -X POST "http://{{ MILVUS_REST_HOST }}/v2/vectordb/collections/list" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"dbName": "default"}'
```

**v1 (legacy):** префикс `/v1/vector/` — deprecated, но маршрут включён.

Документация: [RESTful API v2.5.x](https://milvus.io/api-reference/restful/v2.5.x/About.md)

> `/api/v1/*` — на порту **9091** (metrics), в REST Ingress **не** входит.

## gRPC

```python
from pymilvus import connections
connections.connect("default", uri="https://{{ MILVUS_GRPC_HOST }}:443")
```

## Web UI

Браузер: `http://<host>/webui/` (со слэшем).

## Проверка

```bash
kubectl -n milvus get ingress
curl -sI "http://<ui-host>/webui/"
curl -sI -X POST "http://<rest-host>/v2/vectordb/collections/list" \
  -H "Content-Type: application/json" -d '{"dbName":"default"}'
```

## Ограничения

- Рассчитано на **nginx** ingress-controller.
- Имя Service backend: `milvus` (release name = `milvus`).
- TLS — раскомментируйте блоки `tls` и аннотации cert-manager при необходимости.
