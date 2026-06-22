# Non-root образы под Helm `values-kind-localpath` / air-gap

Исходники **Dockerfile** по компонентам:

| Каталог | Назначение |
|---------|------------|
| `milvus-nonroot/` | Образ Milvus (distributed) |
| `attu-nonroot/` | Attu UI |
| `etcd-nonroot/` | etcd |
| `minio-nonroot/` | MinIO |
| `pulsar-nonroot/` | Pulsar (Zookeeper / Bookie / Broker и т.д. в одном базовом образе по скриптам) |
| `milvus-config-tool-nonroot/` | Вспомогательный tooling |

**Не хранить в Git** готовые `*.tar.gz` из `artifacts/images/` — они собираются на prep-стенде. См. корневой **`.gitignore`**.

Сборка пакета образов: `scripts/53-build-all-nonroot-images.sh`, выгрузка tar (если нужен air-gap): `scripts/50-collect-images.sh`.
