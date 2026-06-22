# Полностью изолированный контур (без интернета)

Внутри контура **не должно быть** обращений к GitHub, Docker Hub, Helm-репозиториям и т.п. Всё готовится на **prep-стенде с интернетом**, переносится артефактами.

## Что перенести в контур

| Артефакт | Назначение |
|----------|------------|
| `artifacts/images/*.tar` (и при необходимости `.tar.gz`) | `docker load` / внутренний registry + для kind: `scripts/60-load-images-kind.sh` |
| `artifacts/charts/*.tgz` | `helm upgrade --install` (см. `ISOLATED_INSTALL.md`) |
| `chart/milvus/` или только packaged `.tgz` | Уже **без** `helm dependency update` |
| `manifests/local-path-storage.yaml` | Установка StorageClass **без** `kubectl apply -f https://...` |
| `values/*.yaml`, `scripts/*.sh`, документация | Как в `80-export-delivery-bundle.sh` |

## Образы, которые должны быть в `artifacts` (после prep)

Все **non-root** Milvus/Attu — см. `50-collect-images.sh`. Дополнительно для кластера:

- `rancher/local-path-provisioner:v0.0.35`
- `busybox:1.36` (helper pod local-path)

На prep они попадают в выгрузку после `./scripts/53-build-all-nonroot-images.sh`.

## Установка в контуре (схема)

1. Установить `kubectl`, `helm`, `docker` или `containerd`, `kind` (если используете kind) — **бинарники** переносятся отдельно (пакеты/USB).
2. `docker load -i ...` для всех образов из `artifacts/images/` **или** загрузка в ваш registry и правки `values-isolated-template.yaml`.
3. Для **kind**: после `kind create cluster` выполнить **`./scripts/60-load-images-kind.sh`** (образы должны быть загружены в Docker на хосте после `docker load`).
4. **`./scripts/20-install-local-path-provisioner.sh`** — только локальный файл `manifests/local-path-storage.yaml` (входит в bundle).
5. **`./scripts/70-install-milvus-isolated.sh`** (или ваш Helm-пайплайн) с **офлайн** values — **без** `helm repo add` и **без** `helm dependency update`.

## Образ узла kind (`kindest/node`)

Если в контуре поднимаете **kind**, заранее на prep сохраните образ узла, который использует ваша версия `kind`:

```bash
# пример; тег возьмите из вывода kind при первом create на prep
docker pull kindest/node:v1.35.0
docker save kindest/node:v1.35.0 -o artifacts/images/kindest_node__v1.35.0.tar
```

В контуре: `docker load` перед `kind create cluster`.

## Проверка «нет исходящих запросов»

- В `scripts/20-install-local-path-provisioner.sh` **нет** URL на `raw.githubusercontent.com`.
- В `scripts/30-install-milvus-online.sh` по умолчанию **нет** `helm dependency update`.
- `helm package` в `50-collect-images.sh` работает **полностью офлайн**, если чарты и `charts/` на диске.

При обновлении версий Milvus/local-path/kind node цикл повторяется **только на prep**, затем снова перенос артефактов.
