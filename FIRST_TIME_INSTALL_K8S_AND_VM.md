# Milvus: First-Time Installation Guide (Kubernetes + VM, Offline)

Этот документ рассчитан на установку **с нуля**, как для команды, которая делает это впервые.

Покрывает:
- подготовку артефактов;
- загрузку образов во внутренний registry;
- деплой в Kubernetes через Helm;
- пример TeamCity pipeline;
- отдельный сценарий для standalone на виртуальном сервере.

---

## 0. Что уже должно быть на руках

Из подготовленного набора `milvus-delivery`:

- K8s:
  - `k8s/images/*.tar.gz`
  - `k8s/chart/milvus-4.2.33.tgz`
  - `k8s/chart/values-*.yaml`
  - `k8s/scripts/*`
- Standalone:
  - `standalone/images/*.tar.gz`
  - `standalone/compose/docker-compose.yml`
  - `standalone/scripts/*`

---

## 1. Внутренний registry: загрузка образов (K8s)

## 1.1 Загрузка tar.gz в Docker

На хосте с доступом к внутреннему registry:

```bash
mkdir -p /opt/milvus/k8s-images
cp k8s/images/*.tar.gz /opt/milvus/k8s-images/
cd /opt/milvus/k8s-images

for f in *.tar.gz; do
  gunzip -c "$f" | docker load
done
```

## 1.2 Ретег и push во внутренний registry

Пример (подставьте свои значения):

```bash
export REG="{{ INTERNAL_REGISTRY }}"

docker tag milvus-nonroot:2.5.0 ${REG}/milvus/milvus-nonroot:2.5.0
docker tag milvusdb/etcd:3.5.16-r1 ${REG}/milvus/etcd:3.5.16-r1
docker tag apachepulsar/pulsar:3.0.7 ${REG}/milvus/pulsar:3.0.7
docker tag minio/minio:RELEASE.2023-03-20T20-16-18Z ${REG}/milvus/minio:RELEASE.2023-03-20T20-16-18Z
docker tag milvusdb/milvus-config-tool:v0.1.2 ${REG}/milvus/milvus-config-tool:v0.1.2

docker push ${REG}/milvus/milvus-nonroot:2.5.0
docker push ${REG}/milvus/etcd:3.5.16-r1
docker push ${REG}/milvus/pulsar:3.0.7
docker push ${REG}/milvus/minio:RELEASE.2023-03-20T20-16-18Z
docker push ${REG}/milvus/milvus-config-tool:v0.1.2
```

---

## 2. Kubernetes: установка Helm chart

## 2.1 Подготовка namespace + imagePullSecret

```bash
kubectl create ns milvus

kubectl -n milvus create secret docker-registry internal-registry-secret \
  --docker-server="{{ INTERNAL_REGISTRY }}" \
  --docker-username="{{ REGISTRY_USER }}" \
  --docker-password="{{ REGISTRY_PASSWORD }}" \
  --docker-email="{{ REGISTRY_EMAIL }}"
```

## 2.2 Выбор values профиля

Рекомендуемые профили:

- `values-kind-localpath.yaml`  
  Полностью локальный профиль, все зависимости в chart.

- `values-external-minio-etcd-with-internal-pulsar.yaml`  
  Внешний MinIO, встроенный etcd и встроенный Pulsar.

- `values-isolated-template.yaml`  
  Шаблон под прод-адаптацию.

## 2.3 Установка

```bash
helm upgrade --install milvus ./milvus-4.2.33.tgz \
  -n milvus \
  -f values-external-minio-etcd-with-internal-pulsar.yaml
```

## 2.4 Проверка

```bash
kubectl get pods -n milvus
kubectl get svc -n milvus
kubectl get endpoints -n milvus milvus

kubectl port-forward -n milvus svc/milvus 19530:19530 9091:9091
curl -sf http://127.0.0.1:9091/healthz
```

Ожидаемо:
- `healthz` возвращает `OK`;
- ключевые pod (`proxy`, `mixcoord`, `querynode`, `datanode`, `indexnode`, `etcd`, `pulsar`, `minio`) — `Running/Ready`.

---

## 3. TeamCity: pipeline для chart deployment

Ниже простой и практичный пайплайн из 3 стадий.

## 3.1 Stage A: Prepare/Validate

Шаги:
1. Скопировать chart/values из артефактов.
2. Прогнать `helm lint`.
3. Прогнать `helm template` (валидация рендера).

Пример команд:

```bash
helm lint ./milvus-4.2.33.tgz
helm template milvus ./milvus-4.2.33.tgz -n milvus -f values.yaml >/tmp/rendered.yaml
```

## 3.2 Stage B: Deploy

Шаги:
1. Подключить `KUBECONFIG` service account контурного кластера.
2. Выполнить `helm upgrade --install`.
3. Подождать rollout.

```bash
helm upgrade --install milvus ./milvus-4.2.33.tgz -n milvus -f values.yaml
kubectl rollout status deployment/milvus-proxy -n milvus --timeout=600s
```

## 3.3 Stage C: Smoke test

```bash
kubectl -n milvus port-forward svc/milvus 19530:19530 9091:9091 &
PF_PID=$!
sleep 5
curl -sf http://127.0.0.1:9091/healthz
kill $PF_PID
```

---

## 4. TeamCity (Kotlin DSL skeleton)

```kotlin
project {
  buildType(Prepare)
  buildType(Deploy)
  buildType(Smoke)
}

object Prepare : BuildType({
  name = "Milvus - Prepare"
  steps {
    script {
      scriptContent = """
        set -euo pipefail
        helm lint ./milvus-4.2.33.tgz
        helm template milvus ./milvus-4.2.33.tgz -n milvus -f values.yaml >/tmp/rendered.yaml
      """.trimIndent()
    }
  }
})

object Deploy : BuildType({
  name = "Milvus - Deploy"
  dependencies { snapshot(Prepare) {} }
  steps {
    script {
      scriptContent = """
        set -euo pipefail
        helm upgrade --install milvus ./milvus-4.2.33.tgz -n milvus -f values.yaml
      """.trimIndent()
    }
  }
})

object Smoke : BuildType({
  name = "Milvus - Smoke"
  dependencies { snapshot(Deploy) {} }
  steps {
    script {
      scriptContent = """
        set -euo pipefail
        kubectl -n milvus port-forward svc/milvus 19530:19530 9091:9091 >/tmp/pf.log 2>&1 &
        PF_PID=$!
        sleep 5
        curl -sf http://127.0.0.1:9091/healthz
        kill $PF_PID
      """.trimIndent()
    }
  }
})
```

---

## 5. Standalone на виртуальном сервере (offline)

## 5.1 Перенос файлов

На VM перенести:
- `standalone/images/*.tar.gz`
- `standalone/compose/docker-compose.yml`
- `standalone/scripts/*`

## 5.2 Загрузка образов

```bash
cd /opt/milvus-standalone
chmod +x scripts/*.sh
./scripts/load-images.sh
```

## 5.3 Запуск

```bash
./scripts/run.sh
./scripts/healthcheck.sh
```

---

## 6. Переключение на внешний etcd позже

Когда получите адрес внешнего etcd:

1. В values:
   - `etcd.enabled: false`
   - `externalEtcd.enabled: true`
   - заполнить `externalEtcd.endpoints`
2. Выполнить `helm upgrade --install`.
3. Проверить лог proxy/mixcoord/querynode на успешное подключение к external etcd.

---

## 7. Частые ошибки

- Неправильный `imagePullSecret` -> `ImagePullBackOff`.
- Попытка использовать etcd control-plane Kubernetes как externalEtcd.
- Неправильный bucket/credentials MinIO.
- Нет storageClass для встроенных PVC (если профиль со встроенными зависимостями).

---

## 8. Минимальный rollback

```bash
helm rollback milvus 1 -n milvus
# или
helm uninstall milvus -n milvus
```

