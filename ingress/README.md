# Milvus Ingress: UI / REST / gRPC

Production-ready манифесты для **nginx ingress-controller**. Порты и пути — **Milvus 2.5.0** + [официальная дока Ingress](https://milvus.io/docs/v2.5.x/ingress.md).

## Файлы

| Файл | Host (пример) | Backend port | Пути | Протокол |
|------|---------------|--------------|------|----------|
| `milvus-ui-ingress.yaml` | `milvus-ui.iss.example.ru` | **9091** | `/webui` | HTTP |
| `milvus-rest-ingress.yaml` | `milvus-rest.iss.example.ru` | **19530** | `/v2/vectordb`, `/v1` | HTTP |
| `milvus-grpc-ingress.yaml` | `milvus-grpc.iss.example.ru` | **19530** | `/` | gRPC |
| `MILVUS_REST_API_PATHS.md` | — | — | все REST-пути v2/v1 | справочник |

## Что подставить (find & replace во всех трёх yaml)

| Плейсхолдер | Пример | Описание |
|-------------|--------|----------|
| `{{ NAMESPACE }}` | `milvus` | Namespace Milvus |
| `{{ INGRESS_CLASS }}` | `nginx` | `ingressClassName` контроллера |
| `{{ MILVUS_SERVICE_NAME }}` | `milvus` | Имя Service (= Helm release name) |
| `{{ TLS_SECRET_NAME }}` | `milvus-tls` | Secret с `tls.crt` + `tls.key` в том же namespace |
| `{{ MILVUS_UI_HOST }}` | `milvus-ui.iss.msvavav.ru` | DNS для Web UI |
| `{{ MILVUS_REST_HOST }}` | `milvus-rest.iss.msvavav.ru` | DNS для REST |
| `{{ MILVUS_GRPC_HOST }}` | `milvus-grpc.iss.msvavav.ru` | DNS для gRPC |

Один wildcard-сертификат (`*.iss.msvavav.ru`) — один `{{ TLS_SECRET_NAME }}` во всех трёх Ingress (Secret должен лежать в `{{ NAMESPACE }}`).

Cert-manager вместо готового Secret — раскомментируйте `cert-manager.io/cluster-issuer` и подставьте `{{ CERT_MANAGER_CLUSTER_ISSUER }}`.

## Предусловия (Helm)

```bash
cd ..   # milfus-main
helm upgrade --install milvus ./chart/milvus -n milvus \
  -f values/values-kind-localpath.yaml \
  -f values/values-webui-ingress.yaml
```

Обязательно:
- `proxy.http.enabled: true` — REST на 19530
- `metrics.enabled: true` — порт **9091** на Service (Web UI)

Проверка:

```bash
kubectl -n milvus get svc milvus
# порты 19530 и 9091
kubectl -n milvus get endpoints milvus
# не пусто
```

## DNS

```
milvus-ui.<domain>   → EXTERNAL-IP ingress
milvus-rest.<domain> → EXTERNAL-IP ingress
milvus-grpc.<domain> → EXTERNAL-IP ingress
```

## Apply

```bash
# после замены всех {{ ... }}
kubectl apply -f milvus-ui-ingress.yaml
kubectl apply -f milvus-rest-ingress.yaml
kubectl apply -f milvus-grpc-ingress.yaml
```

## URL после деплоя

| Сервис | URL |
|--------|-----|
| Web UI | `https://<MILVUS_UI_HOST>/webui/` |
| REST v2 | `https://<MILVUS_REST_HOST>/v2/vectordb/collections/list` |
| REST v1 | `https://<MILVUS_REST_HOST>/v1/vector/...` |
| gRPC | `https://<MILVUS_GRPC_HOST>:443` |

## Проверка

```bash
NS=milvus

kubectl -n $NS get ingress
kubectl -n $NS describe ingress milvus-ui milvus-rest milvus-grpc

# UI
curl -skI "https://milvus-ui.iss.msvavav.ru/webui/"

# REST
curl -sk -X POST "https://milvus-rest.iss.msvavav.ru/v2/vectordb/collections/list" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer root:YOUR_PASSWORD" \
  -d '{"dbName":"default"}'

# gRPC (из Python)
# connections.connect("default", uri="https://milvus-grpc.iss.msvavav.ru:443", token="root:...")
```

## Аннотации (что уже в манифестах)

| Аннотация | UI | REST | gRPC |
|-----------|:--:|:----:|:----:|
| `ssl-redirect` / `force-ssl-redirect` | ✅ | ✅ | ✅ |
| `backend-protocol` | HTTP | HTTP | GRPC |
| `proxy-body-size` | 0 (без лимита) | 2048m | 2048m |
| `proxy-*-timeout` 600s | ✅ | ✅ | ✅ |
| `spec.tls` + `secretName` | ✅ | ✅ | ✅ |

## Важно

- **Три разных host'а** — рекомендуется (UI на 9091, gRPC на `/` не конфликтует с REST).
- REST + gRPC на **одном** host возможны: пути `/v2/vectordb` и `/v1` длиннее `/`.
- `/api/v1/*` на порту 9091 **намеренно не** публикуется (ИБ).
- Только **nginx** ingress-controller.

## 503 — чеклист

1. `kubectl -n milvus get endpoints {{ MILVUS_SERVICE_NAME }}` — не пусто
2. В Service есть нужный порт (9091 / 19530)
3. `{{ MILVUS_SERVICE_NAME }}` = имя Helm release
4. Secret `{{ TLS_SECRET_NAME }}` существует в namespace (при TLS)
