# Kafka для Milvus: образы, registry, air-gap

Дополнение к [MIGRATION.md](MIGRATION.md) (полная пошаговая миграция).

---

## Три сценария (выберите один)

| Сценарий | Образы в пакете `images/` | Values overlay |
|----------|---------------------------|----------------|
| **A. Внешний Kafka компании** (рекомендуется prod) | **Не нужны** | `docs/kafka/values/values-external-kafka-overlay.yaml` |
| **B. Внутренний Kafka, образы уже в registry** | **Не нужны** | `docs/kafka/values/values-kafka-internal-overlay.yaml` + правка `repository` |
| **C. Air-gap, встроенный Bitnami Kafka** | `bitnami-kafka_*.tar.gz`, `bitnami-zookeeper_*.tar.gz` | `values-kafka-internal-overlay.yaml` |

---

## A. Корпоративный Kafka (образ в вашем registry)

Milvus **не запускает** Kafka в K8s — только подключается к брокерам.

### 1. Узнать у админов Kafka

| Параметр | Пример |
|----------|--------|
| `brokerList` | `kafka-1.corp.local:9092,kafka-2.corp.local:9092` |
| `securityProtocol` | `SASL_SSL` / `PLAINTEXT` |
| SASL | `SCRAM-SHA-512`, user/password для Milvus |
| CA | PEM для TLS |

### 2. Заполнить overlay

Файл: `docs/kafka/values/values-external-kafka-overlay.yaml`

```yaml
externalKafka:
  enabled: true
  brokerList: "kafka-1.corp.local:9092,kafka-2.corp.local:9092"
  securityProtocol: SASL_SSL
  sasl:
    mechanisms: SCRAM-SHA-512
    username: "milvus"
    password: "{{ KAFKA_MILVUS_PASSWORD }}"   # K8s Secret в prod
```

### 3. Образ Kafka в registry

**Не требуется для Milvus** — используется кластер, который уже крутит платформа/Kafka-команда.

В Helm **не** включаете `kafka.enabled: true`. Образ из registry нужен только команде Kafka, не Milvus.

### 4. Upgrade

```bash
helm upgrade milvus ./chart/milvus -n milvus \
  -f values/values-mvp-production.yaml \
  -f docs/kafka/values/values-external-kafka-overlay.yaml \
  --reset-then-reuse-values --timeout 30m --wait
```

Дальше — [MIGRATION.md](MIGRATION.md) §5 (maintenance window).

---

## B. Внутренний Kafka (subchart), образы в `{{ INTERNAL_REGISTRY }}`

Если Bitnami Kafka уже загружен в корпоративный registry (другой тег — нормально).

### 1. Уточнить теги в registry

```bash
# пример
{{ INTERNAL_REGISTRY }}/bitnami/kafka:3.1.0-debian-10-r52
{{ INTERNAL_REGISTRY }}/bitnami/zookeeper:3.8.0-debian-10-r63
```

### 2. Правка overlay

`docs/kafka/values/values-kafka-internal-overlay.yaml`:

```yaml
kafka:
  enabled: true
  image:
    repository: "{{ INTERNAL_REGISTRY }}/bitnami/kafka"
    tag: "ВАШ_ТЕГ_ИЗ_REGISTRY"
  zookeeper:
    enabled: true
    image:
      repository: "{{ INTERNAL_REGISTRY }}/bitnami/zookeeper"
      tag: "ВАШ_ТЕГ_ИЗ_REGISTRY"
```

### 3. imagePullSecrets (если registry private)

В базовом values Milvus:

```yaml
image:
  all:
    pullSecrets:
      - name: internal-registry
```

Аналогично для subchart — глобальные `global.imagePullSecrets` в Bitnami chart (см. `helm show values chart/milvus/charts/kafka` после `helm dependency update`).

**tar.gz в пакете не кладёте** — только ссылка на registry в values.

---

## C. Air-gap: положить Kafka в пакет `images/`

Если **нет** готового Kafka в registry и нужен **встроенный** subchart.

### 1. На prep-стенде (с интернетом)

```bash
cd source   # каталог milfus-main внутри пакета
./scripts/59-export-kafka-images-airgap.sh
```

Или вручную (теги сверить с `chart/milvus/values.yaml` → секция `kafka:`):

```bash
export KAFKA_IMAGE=bitnami/kafka:3.1.0-debian-10-r52
export ZK_IMAGE=bitnami/zookeeper:3.8.0-debian-10-r63

docker pull "$KAFKA_IMAGE"
docker pull "$ZK_IMAGE"
docker save "$KAFKA_IMAGE" | gzip > bitnami-kafka_3.1.0-debian-10-r52.tar.gz
docker save "$ZK_IMAGE" | gzip > bitnami-zookeeper_3.8.0-debian-10-r63.tar.gz
```

> Если `docker pull` не находит старый тег Bitnami — возьмите **тот же образ**, что уже есть в корпоративном registry, и укажите его тег в values (сценарий B).

### 2. Положить в пакет

```text
milvus-ldap-airgap-delivery/images/
  bitnami-kafka_3.1.0-debian-10-r52.tar.gz
  bitnami-zookeeper_3.8.0-debian-10-r63.tar.gz
```

### 3. На закрытом контуре

```bash
gunzip -c images/bitnami-kafka_*.tar.gz | docker load
gunzip -c images/bitnami-zookeeper_*.tar.gz | docker load

# retag + push в internal registry (пример)
docker tag bitnami/kafka:3.1.0-debian-10-r52 {{ INTERNAL_REGISTRY }}/bitnami/kafka:3.1.0-debian-10-r52
docker push {{ INTERNAL_REGISTRY }}/bitnami/kafka:3.1.0-debian-10-r52
```

### 4. Миграция

Следовать [MIGRATION.md](MIGRATION.md) полностью.

---

## Что не меняется при переходе на Kafka

| Компонент |
|-----------|
| Milvus, Attu, Envoy LDAP gateway |
| milvus-ldap-sync, milvus-ldap-auth |
| etcd, MinIO (PVC не трогать) |

---

## Быстрый выбор

```
Есть корпоративный Kafka-кластер?
  └─ ДА → сценарий A (values-external-kafka-overlay.yaml), образы в пакет не класть
  └─ НЕТ → образы Kafka уже в internal registry?
        └─ ДА → сценарий B
        └─ НЕТ → сценарий C (tar.gz + load + push)
```
