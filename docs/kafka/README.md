# Milvus: переход Pulsar → Kafka

Отдельная папка с инструкциями и Helm overlays. **Docker-образы Kafka в Git не хранятся** — при корпоративном Kafka используйте только values.

## Документы

| Файл | Назначение |
|------|------------|
| [MIGRATION.md](MIGRATION.md) | Пошаговая миграция (maintenance window, flush, helm upgrade, rollback) |
| [IMAGES_AND_REGISTRY.md](IMAGES_AND_REGISTRY.md) | Когда нужны tar.gz, когда достаточно `{{ INTERNAL_REGISTRY }}` или внешнего кластера |

## Values (Helm overlay)

| Файл | Сценарий |
|------|----------|
| [values/values-external-kafka-overlay.yaml](values/values-external-kafka-overlay.yaml) | **Prod:** Kafka компании, без образов в пакете |
| [values/values-kafka-internal-overlay.yaml](values/values-kafka-internal-overlay.yaml) | Встроенный Bitnami Kafka, образы из internal registry |

Пример upgrade:

```bash
helm upgrade milvus ./chart/milvus -n milvus \
  -f values/values-mvp-production.yaml \
  -f docs/kafka/values/values-external-kafka-overlay.yaml \
  --reset-then-reuse-values --timeout 30m --wait
```

## Скрипты (образы только на prep-стенде, не в Git)

| Скрипт | Когда |
|--------|--------|
| `scripts/59-export-kafka-images.sh` | Нужны tar.gz Bitnami Kafka для изолированного контура |
| `scripts/81-export-ldap-delivery.sh` | Собрать полный пакет переноса (доки Kafka копируются автоматически) |

## Быстрый выбор

```
Kafka в компании уже есть?
  └─ ДА → values-external-kafka-overlay.yaml + MIGRATION.md
  └─ НЕТ → IMAGES_AND_REGISTRY.md (сценарий B или C)
```

Не затрагивает: Attu, LDAP gateway/sync, Envoy ldap-auth.
