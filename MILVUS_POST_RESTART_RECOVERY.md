# Milvus в Kubernetes: сбой после рестарта Docker / kind (RCA и профилактика)

Документ фиксирует типовой инцидент и действия для будущих кейсов (локальный `kind`, однонодовый control-plane).

## Симптомы

- После перезапуска хоста / Docker / кластера `kind` поды Milvus в `CrashLoopBackOff` или `Error`, при этом часть инфраструктуры уже `Running`.
- В логах `milvus-proxy` (и других компонентов) встречаются:
  - `init with etcd failed` / `context deadline exceeded`;
  - `dial tcp: lookup milvus-etcd-0....svc.cluster.local: operation was canceled`;
  - при обрыве DNS — стектрейсы вокруг `net.(*Resolver).lookupIP`.
- Поды **CoreDNS** в `kube-system` могли быть временно **не Ready** (readiness `503` сразу после `SandboxChanged`).
- **etcd** для Milvus (`milvus-etcd-0`) долго не становится **Ready** из‑за `readinessProbe` с большим **`initialDelaySeconds`** (в Bitnami-чарте часто **60s** и более).

## Корневая причина

**Гонка порядка запуска после холодного старта кластера:**

1. Kubelet пересоздаёт sandbox подов (`SandboxChanged`).
2. **CoreDNS** и **etcd** поднимаются не мгновенно; DNS для `*.svc.cluster.local` и клиентские подключения к etcd становятся стабильными позже, чем стартуют процессы Milvus.
3. Компоненты Milvus при старте **сразу** подключаются к etcd (и резолвят headless‑имена). Таймаут инициализации конфигурации через etcd **короткий** (порядка секунд); при неудаче proxy/mixcoord и др. завершаются с ошибкой.
4. **Kubernetes перезапускает** контейнеры; часть зависимостей к этому моменту уже готова, но образ может остаться в цикле ошибок до явного перезапуска workload или до стабильного порядка старта.

Итог: это не «сломался чарт», а **временная недоступность DNS/etcd** в окне старта Milvus.

## Что сделать сразу (восстановление)

1. Убедиться, что инфраструктура зелёная:
   ```bash
   kubectl get pods -n kube-system -l k8s-app=kube-dns
   kubectl get pods -n milvus -l app.kubernetes.io/name=etcd
   kubectl get pods -n milvus | rg pulsarv3
   ```
2. Когда **etcd** и **Pulsar** (если используется) в **Ready**, перезапустить **только** компоненты Milvus (не трогая etcd/MinIO без необходимости):
   ```bash
   kubectl rollout restart deployment/milvus-datanode deployment/milvus-indexnode \
     deployment/milvus-mixcoord deployment/milvus-proxy deployment/milvus-querynode \
     -n milvus
   ```
3. Дождаться проб (у proxy часто **`initialDelaySeconds: 90`**):
   ```bash
   kubectl get pods -n milvus -w
   ```
4. Проверить health:
   ```bash
   kubectl exec -n milvus deploy/milvus-proxy -- curl -sf http://127.0.0.1:9091/healthz
   ```

## Как снизить вероятность (профилактика)

| Мера | Комментарий |
|------|-------------|
| **Операционно** | После старта кластера подождать 1–2 минуты перед проверкой Milvus; при ошибках выполнить `rollout restart` перечисленных deployment’ов. |
| **Зависимости** | Мониторить **CoreDNS Ready** и **etcd Ready** как предусловие для алертов по Milvus. |
| **Helm / chart** | Рассмотреть `initContainer` с ожиданием DNS и TCP до `milvus-etcd` (например `busybox` + `nslookup`/`nc`) для proxy и координаторов. |
| **Пробы** | Точечно увеличить `initialDelaySeconds` liveness/readiness у компонентов Milvus на dev/stage, если гонка повторяется. |
| **Прод** | Вынести etcd (и при необходимости MQ) во внешние отказоустойчивые сервисы; на однонодовом kind проблема проявляется чаще. |

## Helm upgrade на kind и `ImagePullBackOff`

После `helm upgrade` Kubernetes может пересоздать StatefulSet/Deployment и запланировать **новые** pod’ы. Если образы с коротким именем (например `milvus-etcd-nonroot:tag`) существуют только **локально** (custom build / изолированный контур), kubelet попытается тянуть их как `docker.io/library/...` и получит **pull access denied**.

**Что сделать:** с хоста, где собраны образы, снова загрузить их в узел kind:

```bash
kind load docker-image milvus-etcd-nonroot:3.5.16-r1 \
  milvus-minio-nonroot:RELEASE.2023-03-20T20-16-18Z \
  milvus-nonroot:2.5.0 milvus-pulsar-nonroot:3.0.7 \
  --name milvus-local
```

Затем удалить застрявшие pod’ы (`kubectl delete pod ...`) или дождаться повторной попытки pull.

## Связанные документы

- [MILVUS_PODS_EXPLAINED.md](./MILVUS_PODS_EXPLAINED.md) — состав подов и быстрая диагностика.
- [MILVUS_NATIVE_RBAC.md](./MILVUS_NATIVE_RBAC.md) — встроенная аутентификация Milvus (после включения `authorizationEnabled` клиенты должны передавать учётные данные).
