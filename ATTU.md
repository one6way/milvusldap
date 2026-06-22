# Attu (веб-UI для Milvus) в `milvus-airgap`

[Attu](https://github.com/zilliztech/attu) — отдельное приложение для управления Milvus 2.x. В этом репозитории:

- **Helm-чарт:** `chart/attu/` (vendored, без внешнего `helm repo`).
- **Образ `attu-nonroot`:** `images/attu-nonroot/Dockerfile` — обёртка над `zilliz/attu`, runtime **UID/GID 1000** (как у остальных образов набора).
- **Values для kind:** `values/values-attu-kind.yaml`.

## Совместимость с Milvus

Для **Milvus 2.5.x** используется тег Attu **v2.5.10** (см. таблицу в README Attu). Образ собирается как `attu-nonroot:2.5.10`.

## Сборка образа (prep-стенд, есть интернет)

Из каталога `milvus-airgap`:

```bash
chmod +x scripts/58-build-attu-nonroot-image.sh
./scripts/58-build-attu-nonroot-image.sh
```

Загрузка в kind:

```bash
kind load docker-image attu-nonroot:2.5.10 --name milvus-local
```

## Установка в кластер

Тот же namespace, что и Milvus (по умолчанию `milvus`):

```bash
./scripts/31-install-attu.sh
```

Или вручную:

```bash
helm upgrade --install attu chart/attu -n milvus -f values/values-attu-kind.yaml
```

## Доступ к UI

```bash
kubectl port-forward -n milvus svc/attu 3000:3000
```

Браузер: `http://127.0.0.1:3000`.

### NodePort (без port-forward и без Ingress)

Дополнительный values: **`values/values-attu-nodeport.yaml`** (вместе с `values-attu-kind.yaml`). Пример порта UI на ноде: **30300** → `http://<IP-ноды>:30300`. Для Milvus gRPC/Web UI см. **`values/values-kind-nodeport.yaml`** (по умолчанию **30530** / **30531**). В облаке следующий шаг — заменить `service.type` на **LoadBalancer** с теми же `port` / `targetPort`.

**macOS + Docker Desktop + kind:** NodePort **не** слушает на `127.0.0.1`, пока нет проброса — Safari пишет «не может подключиться». Варианты: (1) пересоздать кластер с **`kind/kind-config-milvus-local.yaml`** (`scripts/10-create-kind-cluster.sh`); (2) без пересоздания — **`kubectl port-forward`**:  
`kubectl port-forward -n milvus svc/attu 30300:3000` → `http://127.0.0.1:30300` (или классика `3000:3000`).

### Кнопка «Milvus Web UI» (иконка внешней ссылки) → `http://milvus:9091/webui` пустая / не открывается

Это **ожидаемое поведение** при подключении к Milvus с хостом `milvus` (или другим внутренним DNS кластера).

- В форме Connect вы указываете адрес, **доступный из pod Attu** — например `milvus:19530`.
- Ссылка на встроенный Web UI Milvus строится из **того же хоста** и порта **9091**: `http://milvus:9091/webui`.
- Браузер на вашей машине **не входит** в pod и **не знает** имя `milvus` → страница не грузится.

**Что сделать:** открыть Web UI Milvus **на localhost**, пробросив порт сервиса proxy (порт **9091** на Service `milvus` совпадает с target на pod proxy в типовом чарте):

```bash
# отдельный терминал, пока смотрите Attu
kubectl port-forward -n milvus svc/milvus 9091:9091
```

В браузере вручную: **`http://127.0.0.1:9091/webui`** (кнопку в Attu для этого сценария не используйте).

Параллельно Attu оставьте на `kubectl port-forward -n milvus svc/attu 3000:3000`.

Долгосрочно (общая сеть / прод): вынести Milvus за Ingress или DNS-имя, которое **резолвится с рабочей станции** (и при необходимости TLS), тогда можно подставлять этот хост в Attu **только если** он одновременно доступен и из pod’ов, и из браузера — на практике для kind/dev чаще используют два port-forward, как выше.

## Milvus Web UI в Kubernetes: «есть ли оно в кластере»

**Да.** Встроенный Web UI — это HTTP на том же процессе, что и gRPC proxy Milvus: в pod **proxy** слушается порт **9091** (в чарте он назван `metrics`; там же отдаются `/metrics`, health и путь **`/webui`**).

Helm создаёт Service с именем релиза (часто **`milvus`**) с портом **19530** (gRPC). Второй порт **9091** (имя в манифесте часто `metrics`, target на контейнер proxy) добавляется **только если** в values **`metrics.enabled: true`** — так сделано в `chart/milvus/templates/service.yaml`.

В `chart/milvus/values.yaml` по умолчанию **`metrics.enabled: true`**. Проверка:

```bash
kubectl get svc -n milvus milvus -o wide
# должны быть порты 19530 и 9091 (имя порта часто metrics)
```

Из **любого pod** в том же namespace Web UI доступен как  
`http://milvus.<namespace>.svc:9091/webui` (или коротко `http://milvus:9091/webui` при namespace `milvus`).

Если в ваших values **`metrics.enabled: false`**, второй порт в Service может **не создаться** — тогда `kubectl port-forward svc/milvus 9091:9091` не сработает; либо включите `metrics.enabled: true`, либо пробрасывайте порт на pod proxy напрямую:

```bash
kubectl port-forward -n milvus deploy/milvus-proxy 9091:9091
```

**Снаружи кластера** по умолчанию ничего «не торчит»: Service обычно **ClusterIP**. Чтобы оператор открыл Web UI с рабочей машины (как Attu), нужно явно:

| Способ | Комментарий |
|--------|-------------|
| `kubectl port-forward` | Как в dev/kind |
| **Ingress** | Маршрут на `svc/milvus`, порт backend **9091**, путь можно ограничить префиксом; TLS на Ingress |
| **LoadBalancer / NodePort** | На сервисе Milvus или отдельный Service только на 9091 |
| Доступ только из ВПН | Клиент в той же сети, что и Pod network / internal LB |

Итого: в Kube Web UI **не пропадает** — он на proxy. «Не открывается из браузера» бывает из‑за **DNS `milvus` только внутри кластера** или из‑за того, что **9091 не опубликован наружу** (и это нормально с точки зрения ИБ, пока вы сами не настроите публикацию).

### Подключение к Milvus из Attu (обязательно прочитать)

Запросы к Milvus идут **из pod Attu в кластере**, а не с вашего Mac. Поэтому в форме «Connect» **нельзя** указывать `127.0.0.1` / `localhost` как адрес Milvus — для Attu это сам контейнер Attu, а не proxy Milvus.

| Поле | Значение |
|------|----------|
| Host / Milvus address | `milvus` (имя Service в namespace `milvus`; при необходимости FQDN: `milvus.milvus.svc.cluster.local`) |
| Port | `19530` |
| Authentication | включить (если в `values-kind-localpath.yaml` задан `authorizationEnabled: true`) |
| Username | `root` |
| Password | `user` (из `defaultRootPassword` в том же values) |

Отдельный пользователь **`admin`** появляется только после `./scripts/45-bootstrap-milvus-native-rbac.sh`; пароль может быть `user` или `user00` — см. `MILVUS_NATIVE_RBAC.md`.

Проверка с вашей машины (без ручного входа в UI):

```bash
chmod +x scripts/41-verify-attu-prereqs.sh
./scripts/41-verify-attu-prereqs.sh
```

Если Attu открывается, но «не подключается к серверу», сначала убедитесь, что **Milvus proxy в Ready** (`kubectl get pods -n milvus -l component=proxy`) и что Pulsar/ZK живы — без них proxy не поднимется.

## Air-gap

1. На prep: `docker save attu-nonroot:2.5.10 | gzip > attu-nonroot-2.5.10.tar.gz`
2. В контуре: загрузить в registry / `docker load`, в values указать `{{ INTERNAL_REGISTRY }}/attu-nonroot:2.5.10`.

## ИБ

Attu даёт широкий доступ к метаданным и данным коллекций. Держите сервис во **внутренней сети**, не публикуйте без SSO/Ingress с TLS и политиками. Подробнее — обсуждение TLS/RBAC в переписке и `MILVUS_NATIVE_RBAC.md`.
