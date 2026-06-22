# Milvus + LDAP — с чего начать

Единая точка входа. Всё для развёртывания, тестирования и переноса в изолированный контур **внутри этого каталога** (`milfus-main/`).

---

## Быстрый маршрут

| Задача | Документ | Действие |
|--------|----------|----------|
| **Понять архитектуру** | [LDAP_DOMAIN_LOGIN_ARCHITECTURE.md](LDAP_DOMAIN_LOGIN_ARCHITECTURE.md) | Схема gateway + ldap-auth + sync |
| **Развернуть на lab (kind)** | [CORP_LDAP_DEPLOYMENT_CHECKLIST.md](CORP_LDAP_DEPLOYMENT_CHECKLIST.md) §4 | `./scripts/47-setup-ldap-lab.sh` → `49-setup-ldap-auth-gateway-lab.sh` |
| **Развернуть prod (LDAPS)** | [CORP_LDAP_DEPLOYMENT_CHECKLIST.md](CORP_LDAP_DEPLOYMENT_CHECKLIST.md) §5 | values prod + `46` / `48` install scripts |
| **Протокол тестирования** | [LDAP_MILVUS_TEST_PROTOCOL.md](LDAP_MILVUS_TEST_PROTOCOL.md) | Матрица проверок, логи, команды |
| **Обоснование требований** | [IB_TZ_COMPLIANCE_ARGUMENTATION.md](IB_TZ_COMPLIANCE_ARGUMENTATION.md) | Для согласования с заказчиком |
| **Собрать образы LDAP** | `scripts/57-build-ldap-images-nonroot.sh` | Dockerfiles в `docker/` |
| **Собрать стек Milvus** | [PREP_NONROOT_ONCE.md](PREP_NONROOT_ONCE.md) | `scripts/53-build-all-nonroot-images.sh` |
| **Установка Milvus в изолированном контуре** | [ISOLATED_INSTALL.md](ISOLATED_INSTALL.md) | `scripts/70-install-milvus-isolated.sh` |
| **Миграция Pulsar → Kafka** | [docs/kafka/README.md](docs/kafka/README.md) | maintenance window + helm upgrade |
| **Kafka: registry vs tar.gz** | [docs/kafka/IMAGES_AND_REGISTRY.md](docs/kafka/IMAGES_AND_REGISTRY.md) | корп. Kafka / internal registry |

---

## Дерево поставки (LDAP)

```
milfus-main/
├── START_HERE.md                 ← вы здесь
├── CORP_LDAP_DEPLOYMENT_CHECKLIST.md
├── LDAP_MILVUS_TEST_PROTOCOL.md
├── IB_TZ_COMPLIANCE_ARGUMENTATION.md
├── LDAP_DOMAIN_LOGIN_ARCHITECTURE.md
├── LDAPS_RBAC_SYNC_SETUP.md
│
├── docker/                       # Dockerfile sidecar (в Git)
│   ├── milvus-ldap-sync/Dockerfile
│   └── ldap-auth-extauthz/Dockerfile
│
├── scripts/
│   ├── milvus_ldap_sync.py
│   ├── ldap_auth_extauthz.py
│   ├── 46-install-ldap-sync.sh
│   ├── 47-setup-ldap-lab.sh
│   ├── 48-install-ldap-auth-gateway.sh
│   ├── 49-setup-ldap-auth-gateway-lab.sh
│   └── 57-build-ldap-images-nonroot.sh
│
├── manifests/
│   ├── ldap-sync/                # CronJob, secrets/ca examples
│   ├── ldap-auth/                # Envoy gateway, ldap-auth, NetworkPolicy
│   └── ldap-lab/                 # OpenLDAP (только lab)
│
├── values/
│   ├── values-ldap-sync-kind-lab.yaml
│   ├── values-ldap-sync-milvus-k121.yaml
│   ├── values-ldap-auth-gateway-kind-lab.yaml
│   └── values-ldap-auth-gateway.example.yaml
│
├── images/                       # Dockerfile non-root Milvus/etcd/… (в Git)
├── chart/                        # Helm chart Milvus
└── docs/kafka/                   # Pulsar → Kafka (без образов в Git)
    ├── README.md
    ├── MIGRATION.md
    ├── IMAGES_AND_REGISTRY.md
    └── values/                   # Helm overlays
```

---

## Где лежат tar.gz образов

| Назначение | Каталог | Сборка |
|------------|---------|--------|
| **LDAP sidecar** | `artifacts/images/` | `./scripts/57-build-ldap-images-nonroot.sh` |
| **Milvus стек** (etcd, minio, milvus-nonroot, …) | `milvus-delivery/k8s/images/` (вне этого репо) или локально после `scripts/56-build-nonroot-deps-and-export.sh` | см. [PREP_NONROOT_ONCE.md](PREP_NONROOT_ONCE.md) |

`artifacts/` в `.gitignore` — образы не пушатся в Git, только Dockerfile и скрипты сборки.

---

## Lab за 3 команды

```bash
cd milfus-main
./scripts/47-setup-ldap-lab.sh
./scripts/49-setup-ldap-auth-gateway-lab.sh
# Attu: milvus-ldap-gateway:19530 + LDAP-пароль
```

---

## Prod за 2 шага (после заполнения values/secrets)

```bash
VALUES_FILE=values/values-ldap-sync-prod.yaml ./scripts/46-install-ldap-sync.sh
VALUES_FILE=values/values-ldap-auth-gateway-prod.yaml ./scripts/48-install-ldap-auth-gateway.sh
```

Шаблоны: `values/*-example.yaml`, `manifests/*/*.example.yaml`.

---

## Полный README стека Milvus

Общая документация (Helm, Attu, изолированный контур, Keycloak): [README.md](README.md)

## Git-репозиторий

Целевой remote: **https://github.com/one6way/milvusldap**

Инструкция push (без образов): [PUSH_TO_GITHUB.md](PUSH_TO_GITHUB.md)

## Пакет для закрытого контура (исходники + образы)

Собрать одной командой (рядом с `milfus-main/` появится каталог `milvus-ldap-delivery/`):

```bash
./scripts/81-export-ldap-delivery.sh
```

| В пакете | Содержание |
|----------|------------|
| `images/` | 9× tar.gz (Milvus, Attu, Envoy, LDAP, etcd, minio, pulsar, config-tool) + опц. Kafka |
| `images/kafka/README.md` | когда нужны / не нужны образы Kafka |
| `docs/kafka/` | миграция Pulsar → Kafka, values overlays (без образов) |
| `source/` | полное дерево milfus-main без дублей tar |
| `load-images.sh` | docker load на целевом контуре |
| `MANIFEST.md` | SHA256 образов |

Упаковать для переноса:

```bash
tar -czf milvus-ldap-delivery.tar.gz -C .. milvus-ldap-delivery
```

