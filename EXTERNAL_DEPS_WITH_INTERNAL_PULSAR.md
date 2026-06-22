# Milvus Profile: External MinIO + External etcd + Internal Pulsar

Профиль для случаев, когда в кластере уже есть:
- внешний MinIO (S3),
- внешний etcd (пока может отсутствовать),
- но **нет** внешнего Pulsar.

## Файл профиля

`values/values-external-minio-etcd-with-internal-pulsar.yaml`

## Что делает профиль

- Отключает встроенный `minio`.
- Оставляет встроенный `etcd` по умолчанию.
- Включает `externalS3` и держит `externalEtcd` как заготовку (disabled).
- Оставляет `pulsarv3` встроенным.
- Использует non-root образ `milvus-nonroot:2.5.0` и securityContext `UID/GID=1000`.

## Что обязательно заполнить

- `{{ EXTERNAL_MINIO_HOST }}`
- `{{ EXTERNAL_MINIO_ACCESS_KEY }}`
- `{{ EXTERNAL_MINIO_SECRET_KEY }}`
- `{{ EXTERNAL_MINIO_BUCKET }}`
- `{{ EXTERNAL_ETCD_HOST_1 }}` (понадобится позже, когда будете включать externalEtcd)

Если `externalS3.useSSL: true` и у MinIO внутренний/self-signed CA:
- создайте Secret с CA-сертификатом:
```bash
kubectl -n milvus create secret generic external-minio-ca \
  --from-file=ca.crt=./external-minio-ca.crt
```
- оставьте в values:
  - `externalS3.tls.enabled: true`
  - `externalS3.tls.caSecretName: external-minio-ca`
  - `externalS3.tls.caSecretKey: ca.crt`

## Установка

```bash
helm upgrade --install milvus chart/milvus \
  -n milvus \
  -f values/values-external-minio-etcd-with-internal-pulsar.yaml
```

## Важно

- Сейчас работает встроенный etcd.
- Когда получите адрес внешнего etcd:
  1. `etcd.enabled: false`
  2. `externalEtcd.enabled: true`
  3. заполните `externalEtcd.endpoints`
- Для `externalEtcd` используйте отдельный прикладной etcd, **не** etcd control-plane Kubernetes.
- Bucket в MinIO должен быть создан заранее и доступен для ключей Milvus.
