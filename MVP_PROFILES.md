# Milvus MVP Profiles (Production Pilot)

Этот документ помогает быстро выбрать подходящий `values` профиль для MVP запуска в промышленном контуре.

## Профили

- `values/values-mvp-production.yaml`  
  Базовый MVP для промышленного пилота: внутренние `etcd + MinIO + Pulsar`.

- `values/values-mvp-production-external-s3.yaml`  
  MVP с внешним S3/MinIO (`externalS3`), внутренний `etcd`, внутренний `Pulsar`.

- `values/values-mvp-production-external-etcd-s3.yaml`  
  MVP с внешним `etcd` и внешним S3/MinIO, внутренний `Pulsar`.

- `values/values-keycloak-enabled.yaml`  
  Профиль с включенным Keycloak gateway (`auth.keycloak.enabled: true`).

## Что выбрать

- Если нужен самый простой надежный старт в кластере:  
  используйте `values-mvp-production.yaml`.

- Если у вас уже есть корпоративное S3/MinIO:  
  используйте `values-mvp-production-external-s3.yaml`.

- Если у вас уже есть выделенный внешний etcd-кластер и S3:  
  используйте `values-mvp-production-external-etcd-s3.yaml`.

## Рекомендации по ресурсам (MVP)

- Минимум для пилота (ориентир):  
  `>= 12 vCPU`, `>= 48 GiB RAM`, быстрый storage (SSD/NVMe), отдельный storage class для stateful.

- Для профиля с внутренним MinIO:
  - MinIO PVC: `500Gi` (в профиле уже задано)
  - etcd PVC: `100Gi` (в профиле уже задано)

- Для профилей с external S3:
  - Контролируйте latency до S3/MinIO endpoint.
  - Проверьте throughput на больших вставках/индексации.

## Pre-flight checklist

- [ ] Все образы non-root (UID/GID 1000) загружены в registry/cluster.
- [ ] Корректный `storageClass` и достаточная емкость PVC.
- [ ] `externalS3` (если включен): host/port/accessKey/secretKey/bucket валидны.
- [ ] Если `externalS3.useSSL=true` и CA внутренний: создан Secret `external-minio-ca` c `ca.crt`.
- [ ] `externalEtcd` (если включен): endpoints доступны из namespace Milvus.
- [ ] NetworkPolicy разрешает трафик к S3/etcd/Keycloak (если используется).
- [ ] NTP синхронизирован (важно для OIDC/JWT).
- [ ] Namespace и imagePullSecret подготовлены.

## Команды запуска

```bash
helm upgrade --install milvus ./chart/milvus -n milvus \
  -f values/values-mvp-production.yaml
```

```bash
helm upgrade --install milvus ./chart/milvus -n milvus \
  -f values/values-mvp-production-external-s3.yaml
```

```bash
helm upgrade --install milvus ./chart/milvus -n milvus \
  -f values/values-mvp-production-external-etcd-s3.yaml
```

## Быстрая верификация

```bash
kubectl get pods -n milvus -o wide
kubectl get pvc -n milvus
kubectl get svc -n milvus
```

Если включен Keycloak gateway:

```bash
kubectl get svc -n milvus | rg auth-gateway
```
