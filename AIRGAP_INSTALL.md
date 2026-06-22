# Air-Gap Installation Guide: Milvus (Distributed)

## 1) Цель

Развернуть Milvus в Kubernetes в изолированном контуре без доступа в интернет, используя:

- заранее выгруженные docker image tar-файлы;
- helm chart, доставленный офлайн;
- values с внутренним registry.

## 2) Артефакты, которые нужно подготовить на prep-стенде

Из папки `milvus-airgap`:

```bash
chmod +x scripts/*.sh
# non-root образы (один раз на prep, см. AIRGAP_PREP_NONROOT_ONCE.md):
./scripts/53-build-all-nonroot-images.sh
./scripts/50-collect-images.sh
```

`50-collect-images.sh` **не** вызывает `helm dependency update` — только `helm package` (subchart'ы уже в `chart/milvus/charts/`).

Скрипт создаст:

- `artifacts/images/*.tar` и **`.tar.gz`** — non-root образы (`milvus-nonroot`, `milvus-etcd-nonroot`, `milvus-minio-nonroot`, `milvus-pulsar-nonroot`, `attu-nonroot`), после `./scripts/53-build-all-nonroot-images.sh`;
- `artifacts/charts/milvus-<version>.tgz` — Helm chart Milvus;
- `artifacts/charts/attu-<version>.tgz` — Helm chart **Attu** (веб-UI).

Текущий стабильный профиль использует chart `4.2.33` (Milvus `2.5.0`).

## 3) Что перенести в изолированный контур

- `artifacts/images/*.tar` (и при наличии `*.tar.gz` для Attu)
- `artifacts/charts/milvus-<version>.tgz`
- `artifacts/charts/attu-0.1.0.tgz` (опционально, для UI)
- `values/values-airgap-template.yaml`, `values/values-attu-kind.yaml` (для Attu)
- `scripts/70-install-milvus-airgap.sh`, `scripts/31-install-attu.sh` (опционально)
- каталог **`manifests/`** (local-path **без** обращения к GitHub в контуре)
- документацию из корня bundle (в т.ч. **`ISOLATED_CONTOUR.md`**, **`MILVUS_COMPONENT_FAILURE_RUNBOOK.md`**)

## 4) Загрузка образов во внутренний registry

Пример (на хосте с доступом к registry):

```bash
for f in artifacts/images/*.tar; do
  docker load -i "$f"
done
```

Далее каждый образ перетегировать и отправить во внутренний registry:

```bash
# пример шаблона:
docker tag milvusdb/milvus:v2.4.13 {{ INTERNAL_REGISTRY }}/milvusdb/milvus:v2.4.13
docker push {{ INTERNAL_REGISTRY }}/milvusdb/milvus:v2.4.13
```

Аналогично для всех образов из `scripts/50-collect-images.sh`.

## 5) Настройка values для изолированного контура

Откройте `values/values-airgap-template.yaml` и заполните:

- `global.imageRegistry` = `{{ INTERNAL_REGISTRY }}`
- `imagePullSecrets`
- `persistence.storageClass` (например `local-path`/`nfs-client`/`rook-ceph-block`)
- ресурсы при необходимости.

## 6) Установка в изолированном контуре

```bash
chmod +x scripts/70-install-milvus-airgap.sh
./scripts/70-install-milvus-airgap.sh
```

## 7) Проверка

```bash
kubectl get pods -n milvus
kubectl get pvc -n milvus
kubectl port-forward -n milvus svc/milvus 19530:19530 9091:9091
curl -sf http://127.0.0.1:9091/healthz
```

Ожидаем:

- `healthz` возвращает `ok`;
- все pod в `Running/Ready`.

## 8) Опционально: Attu в air-gap

1. Загрузить образ `attu-nonroot:2.5.10` (`docker load` из `.tar` или `.tar.gz` из `artifacts/images/`).
2. В internal registry при необходимости перетегировать и прописать в `values/values-attu-kind.yaml`.
3. Установка: `./scripts/31-install-attu.sh` или  
   `helm upgrade --install attu artifacts/charts/attu-0.1.0.tgz -n milvus -f values/values-attu-kind.yaml`  
   (путь к `.tgz` поправьте под распакованный bundle).

Подключение из браузера и логин/пароль: **`ATTU.md`**.

## 9) Важные замечания

- Для тестового стенда без HA выбран `local-path`.
- Данные могут потеряться при переносе/пересоздании pod/node.
- Для production лучше использовать отказоустойчивый storage backend.
