# Milvus в Kubernetes (изолированный контур)

Репозиторий — **готовый контур** для развёртывания **Milvus 2.5.x** в **distributed**-режиме (Helm), сценариев **kind** / **прод-пилота**, **non-root** образов и переноса в **изолированный контур** без интернета.

---

## Оглавление

| Раздел | О чём |
|--------|--------|
| [Инфраструктурная схема](INFRASTRUCTURE_ARCHITECTURE.md) | Mermaid: distributed Milvus в Kubernetes |
| [Карта репозитория](#карта-репозитория) | Каталоги и назначение |
| [Быстрый старт (kind)](#быстрый-старт-kind) | Минимальные команды для локального кластера |
| [Документация (все guide)](#документация-все-guide) | Ссылки на `.md` в корне |
| [Тесты и отчёты](#тесты-и-отчёты) | `tests/`, Web UI, Slow Requests |
| [Helm и values](#helm-и-values) | Чарт, профили values |
| [Скрипты](#скрипты) | Нумерованные `scripts/*.sh` |
| [Образы Docker](#образы-docker) | `images/*/Dockerfile` |
| [Изолированный контур и Git](#изолированный-контур-и-git) | Перенос, приватный репозиторий |
| [Снятие стенда](#снятие-стенда) | Helm / namespace / kind |
| [Известные фиксы](#известные-фиксы) | Pulsar bookie, версия chart |

---

## Инфраструктурная схема (K8s)

**[INFRASTRUCTURE_ARCHITECTURE.md](INFRASTRUCTURE_ARCHITECTURE.md)** — наглядные диаграммы **Mermaid** (рендер на GitHub): клиенты, Service, **proxy / mixcoord / query·data·index node**, **etcd**, **MinIO**, **Pulsar v3**, поток **search**, PVC/образы; отдельный раздел **§7** — **Keycloak**, **LDAP/AD**, **Envoy `*-auth-gateway`**, JWKS, опциональный **RBAC sync** и **SIEM**.

---

## Карта репозитория

| Путь | Назначение |
|------|------------|
| [`chart/milvus/`](chart/milvus/) | Vendored Helm-чарт Milvus (subchart’ы внутри; см. [README чарта](chart/milvus/README.md)) |
| [`chart/attu/`](chart/attu/) | Чарт **Attu** (веб-UI к Milvus) |
| [`values/`](values/) | Профили установки: kind, nodeport, изолированный контур, MVP, Keycloak |
| [`scripts/`](scripts/) | Создание kind, установка Milvus/Attu, сборка образов, пакет для переноса |
| [`images/`](images/) | **Dockerfile** non-root образов ([описание](images/README.md)) |
| [`kind/`](kind/) | Конфиг **kind** (проброс портов на localhost) |
| [`manifests/`](manifests/) | Манифесты вспомогательные (например local-path) |
| [`tests/`](tests/) | Автоотчёты kubectl/PyMilvus, демо нагрузки, доки ([tests/README.md](tests/README.md)) |
| [`artifacts/`](artifacts/) | **Не в Git** (см. [.gitignore](.gitignore)): локальные tar образов после prep |

---

## Быстрый старт (kind)

Подробнее про полный bootstrap: [PREP_NONROOT_ONCE.md](PREP_NONROOT_ONCE.md), [MILVUS_KIND_STACK_TEST_CHECKLIST.md](MILVUS_KIND_STACK_TEST_CHECKLIST.md).

```bash
cd milfus-main
chmod +x scripts/*.sh

./scripts/10-create-kind-cluster.sh
./scripts/20-install-local-path-provisioner.sh
./scripts/30-install-milvus-online.sh
./scripts/40-verify-milvus-api.sh
```

Attu и «всё одним скриптом»: [ATTU.md](ATTU.md), [`scripts/90-bootstrap-full-stack-kind.sh`](scripts/90-bootstrap-full-stack-kind.sh).

---

## Документация (все guide)

Ниже — **только корневые** файлы этого репозитория (удобно для навигации). Вложенные README чартов Zilliz/Bitnami в `chart/milvus/charts/` при необходимости смотри локально — в оглавление они не дублируются.

### Установка и контуры

| Документ | Содержание |
|----------|------------|
| [docs/architecture/README.md](docs/architecture/README.md) | **Архитектура LDAP:** взаимодействие и авторизация (Mermaid) |
| [ISOLATED_INSTALL.md](ISOLATED_INSTALL.md) | Установка Milvus в изолированном контуре |
| [PREP_NONROOT_ONCE.md](PREP_NONROOT_ONCE.md) | Prep один раз: non-root образы, без лишнего `helm dependency update` |
| [ISOLATED_CONTOUR.md](ISOLATED_CONTOUR.md) | Работа без интернета: что переносить, local-path, образ kind node |
| [FIRST_TIME_INSTALL_K8S_AND_VM.md](FIRST_TIME_INSTALL_K8S_AND_VM.md) | Первый раз: K8s и сценарий ВМ / standalone (по мере появления каталога) |
| [EXTERNAL_DEPS_WITH_INTERNAL_PULSAR.md](EXTERNAL_DEPS_WITH_INTERNAL_PULSAR.md) | Внешние зависимости при внутреннем Pulsar |

### Профили и безопасность

| Документ | Содержание |
|----------|------------|
| [MVP_PROFILES.md](MVP_PROFILES.md) | MVP values: прод-пилот, внешние S3/etcd |
| [KEYCLOAK_AUTH_FOR_MILVUS.md](KEYCLOAK_AUTH_FOR_MILVUS.md) | Keycloak gateway для Milvus |
| [MILVUS_NATIVE_RBAC.md](MILVUS_NATIVE_RBAC.md) | Встроенный RBAC (`root`/`user`), скрипт `scripts/45-bootstrap-milvus-native-rbac.sh` |

### Эксплуатация и инциденты

| Документ | Содержание |
|----------|------------|
| [MILVUS_COMPONENT_FAILURE_RUNBOOK.md](MILVUS_COMPONENT_FAILURE_RUNBOOK.md) | Порядок разбора: etcd, MinIO, Pulsar, Milvus, Attu; **standalone** в конце |
| [MILVUS_POST_RESTART_RECOVERY.md](MILVUS_POST_RESTART_RECOVERY.md) | Рестарт кластера: etcd/DNS, гонки |
| [MILVUS_PODS_EXPLAINED.md](MILVUS_PODS_EXPLAINED.md) | Роли подов distributed vs standalone |

### Интерфейсы и чеклисты

| Документ | Содержание |
|----------|------------|
| [ATTU.md](ATTU.md) | Attu: Helm, NodePort, образ `attu-nonroot` |
| [MILVUS_KIND_STACK_TEST_CHECKLIST.md](MILVUS_KIND_STACK_TEST_CHECKLIST.md) | Чеклист после полного подъёма на kind |

### Репозиторий и приватность

| Документ | Содержание |
|----------|------------|
| [PRIVATE_REPO_PUSH.md](PRIVATE_REPO_PUSH.md) | Вынос каталога в приватный Git без tar-образов (`artifacts/` вне Git) |

### Архитектура

| Документ | Содержание |
|----------|------------|
| [INFRASTRUCTURE_ARCHITECTURE.md](INFRASTRUCTURE_ARCHITECTURE.md) | Инфраструктурные схемы distributed Milvus в Kubernetes (Mermaid) |

---

## Тесты и отчёты

| Ресурс | Ссылка |
|--------|--------|
| Обзор тестов, переменные `RUN_*` | [tests/README.md](tests/README.md) |
| Папка артефактов отчётов | [tests/reports/README.md](tests/reports/README.md) |
| Пример разобранного прогона | [tests/TEST_RUN_DOCUMENTED_SAMPLE.md](tests/TEST_RUN_DOCUMENTED_SAMPLE.md) |
| Web UI (9091), панель **Slow Requests** | [tests/SLOW_QUERY_WEBUI.md](tests/SLOW_QUERY_WEBUI.md) |
| Скрипт отчёта | [`tests/run_milvus_test_report.sh`](tests/run_milvus_test_report.sh) |
| Демо нагрузки / PyMilvus | [`tests/milvus_simulate_slow_queries.py`](tests/milvus_simulate_slow_queries.py), [`tests/milvus_pymilvus_version.py`](tests/milvus_pymilvus_version.py) |
| Зависимости Python для тестов | [`tests/requirements-tests.txt`](tests/requirements-tests.txt) |

Пример ручной сессии (Web UI): [tests/reports/milvus-webui-demo-session-20260328.md](tests/reports/milvus-webui-demo-session-20260328.md). Автогенерируемые `milvus-test-report-*.md` по умолчанию в [tests/reports/.gitignore](tests/reports/.gitignore) не коммитятся.

---

## Helm и values

| Файл | Назначение |
|------|------------|
| [values/values-kind-localpath.yaml](values/values-kind-localpath.yaml) | Kind + `local-path`, non-root образы, RBAC, **proxy.slowQuerySpanInSeconds** для демо Web UI |
| [values/values-kind-nodeport.yaml](values/values-kind-nodeport.yaml) | NodePort Milvus |
| [values/values-attu-kind.yaml](values/values-attu-kind.yaml) | Attu под kind |
| [values/values-attu-nodeport.yaml](values/values-attu-nodeport.yaml) | Attu NodePort |
| [values/values-isolated-template.yaml](values/values-isolated-template.yaml) | Шаблон для изолированного контура (registry, pullSecrets, StorageClass) |
| [values/values-keycloak-enabled.yaml](values/values-keycloak-enabled.yaml) | Keycloak gateway |
| [values/values-mvp-production.yaml](values/values-mvp-production.yaml) | MVP прод-пилот |
| [values/values-mvp-production-external-s3.yaml](values/values-mvp-production-external-s3.yaml) | MVP + внешний S3/MinIO |
| [values/values-mvp-production-external-etcd-s3.yaml](values/values-mvp-production-external-etcd-s3.yaml) | MVP + внешние etcd и S3 |
| [values/values-external-minio-etcd-with-internal-pulsar.yaml](values/values-external-minio-etcd-with-internal-pulsar.yaml) | Внешние MinIO/etcd, внутренний Pulsar |

Установка из локального чарта: [`scripts/30-install-milvus-online.sh`](scripts/30-install-milvus-online.sh) (values по умолчанию — `values-kind-localpath.yaml`).

---

## Скрипты

Все в [`scripts/`](scripts/). Нумерация отражает типичный порядок.

| Скрипт | Назначение |
|--------|------------|
| [`10-create-kind-cluster.sh`](scripts/10-create-kind-cluster.sh) | Kind + [`kind/kind-config-milvus-local.yaml`](kind/kind-config-milvus-local.yaml) |
| [`20-install-local-path-provisioner.sh`](scripts/20-install-local-path-provisioner.sh) | StorageClass `local-path` |
| [`30-install-milvus-online.sh`](scripts/30-install-milvus-online.sh) | `helm upgrade --install` Milvus |
| [`31-install-attu.sh`](scripts/31-install-attu.sh) | Установка Attu |
| [`40-verify-milvus-api.sh`](scripts/40-verify-milvus-api.sh) | Health + порт 19530 |
| [`41-verify-attu-prereqs.sh`](scripts/41-verify-attu-prereqs.sh) | Готовность Milvus+Attu, учётные данные для формы |
| [`45-bootstrap-milvus-native-rbac.sh`](scripts/45-bootstrap-milvus-native-rbac.sh) | Пользователь `admin` (см. [MILVUS_NATIVE_RBAC.md](MILVUS_NATIVE_RBAC.md)) |
| [`50-collect-images.sh`](scripts/50-collect-images.sh) | Сохранение образов в `artifacts/images` + package chart |
| [`51-refresh-helm-chart-dependencies.sh`](scripts/51-refresh-helm-chart-dependencies.sh) | Обновление subchart’ов (**нужен интернет**) |
| [`53-build-all-nonroot-images.sh`](scripts/53-build-all-nonroot-images.sh) | Сборка non-root образов на prep |
| [`55-build-milvus-nonroot-image.sh`](scripts/55-build-milvus-nonroot-image.sh) | Сборка образа Milvus non-root |
| [`56-build-nonroot-deps-and-export.sh`](scripts/56-build-nonroot-deps-and-export.sh) | Зависимости non-root и export |
| [`58-build-attu-nonroot-image.sh`](scripts/58-build-attu-nonroot-image.sh) | Образ Attu non-root |
| [`60-load-images-kind.sh`](scripts/60-load-images-kind.sh) | `docker load` / загрузка в kind |
| [`70-install-milvus-isolated.sh`](scripts/70-install-milvus-isolated.sh) | Установка из внутреннего registry |
| [`80-export-delivery-bundle.sh`](scripts/80-export-delivery-bundle.sh) | Бандл для переноса |
| [`90-bootstrap-full-stack-kind.sh`](scripts/90-bootstrap-full-stack-kind.sh) | Полный подъём kind-стека |

---

## Образы Docker

Исходники и смысл каталогов: [images/README.md](images/README.md).

| Каталог | Образ |
|---------|--------|
| [`images/milvus-nonroot/`](images/milvus-nonroot/) | Milvus |
| [`images/attu-nonroot/`](images/attu-nonroot/) | Attu |
| [`images/etcd-nonroot/`](images/etcd-nonroot/) | etcd |
| [`images/minio-nonroot/`](images/minio-nonroot/) | MinIO |
| [`images/pulsar-nonroot/`](images/pulsar-nonroot/) | Pulsar (база под компоненты стека) |
| [`images/milvus-config-tool-nonroot/`](images/milvus-config-tool-nonroot/) | Вспомогательный tooling |

---

## Изолированный контур и Git

1. На prep: сборка / выгрузка образов — [PREP_NONROOT_ONCE.md](PREP_NONROOT_ONCE.md), [`scripts/53-build-all-nonroot-images.sh`](scripts/53-build-all-nonroot-images.sh), [`scripts/50-collect-images.sh`](scripts/50-collect-images.sh).  
2. Перенос в контур без сети — [ISOLATED_CONTOUR.md](ISOLATED_CONTOUR.md), [ISOLATED_INSTALL.md](ISOLATED_INSTALL.md).  
3. Каталог **`artifacts/`** в Git не входит (тяжёлые tar); в репозитории только Dockerfile. Подробности: [PRIVATE_REPO_PUSH.md](PRIVATE_REPO_PUSH.md).

---

## Снятие стенда

```bash
helm uninstall milvus -n milvus
kubectl delete ns milvus
kind delete cluster --name milvus-local
```

При отдельном релизе Attu — `helm uninstall attu -n milvus` (или твой namespace).

---

## Известные фиксы

- **Pulsar bookkeeper**: `pulsarv3.bookkeeper.replicaCount` **3**, а не 1 — иначе broker init ждёт три bookie и Milvus не становится Ready.  
- **Версия chart**: зафиксирована **4.2.33** (`appVersion` **2.5.0**), без beta-линейки по умолчанию.

---

*Вопросы по конкретному сценарию начинай с соответствующей строки в таблице [Документация (все guide)](#документация-все-guide).*
