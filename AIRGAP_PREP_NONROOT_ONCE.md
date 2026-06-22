# Air-gap (non-root): один раз на prep-стенде, дальше без pull

**Изолированный контур без интернета:** см. **[ISOLATED_CONTOUR.md](./ISOLATED_CONTOUR.md)** — полный список артефактов и запрет на `kubectl`/`helm` с сетью.

## Идея

1. **Helm:** subchart'ы Milvus уже лежат в `chart/milvus/charts/` (vendored). Скрипты **не** вызывают `helm dependency update`, пока вы явно не зададите `HELM_DEPS_UPDATE=1` или не запустите `./scripts/51-refresh-helm-chart-dependencies.sh`.
2. **Образы:** все теги как в `values/values-kind-localpath.yaml` — **`*-nonroot`**. Один прогон сборки качает **только отсутствующие** базовые `FROM` (если образа нет в Docker), затем `docker build`.

## Команды (prep, есть интернет)

```bash
cd milvus-airgap
chmod +x scripts/*.sh

# Собрать non-root стек + attu (pull баз только если нет локально)
./scripts/53-build-all-nonroot-images.sh

# Сохранить tar/tar.gz в artifacts/images и упаковать чарты в artifacts/charts (без сети для Helm)
./scripts/50-collect-images.sh

# Опционально: полный bundle для переноса в контур
./scripts/80-export-airgap-bundle.sh
```

## В изолированном контуре / повторный kind

- Загрузить образы: `docker load` из `artifacts/images/*.tar` (или `.tar.gz`), либо внутренний registry.
- `helm upgrade --install` из `artifacts/charts/milvus-*.tgz` + `values-airgap-template.yaml` (см. `AIRGAP_INSTALL.md`) **или** на kind: `./scripts/60-load-images-kind.sh` и `./scripts/30-install-milvus-online.sh` (без обновления Helm-зависимостей).

## Когда снова нужен интернет

- Обновить версию Milvus / subchart'ов: `./scripts/51-refresh-helm-chart-dependencies.sh`, затем закоммитить изменения в `chart/milvus/charts/`.
- Новые базовые теги в Dockerfile'ах — снова `./scripts/53-build-all-nonroot-images.sh`.
