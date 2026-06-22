# Milvus Pods Explained (Kubernetes)

Документ описывает, какие pod сейчас работают в namespace `milvus`, зачем они нужны, что критично, и как быстро диагностировать проблемы.

## Контекст

Сейчас развернут **Milvus Distributed**.  
Поэтому, в отличие от standalone, используется несколько ролей (proxy, coord, data/query/index node) и внешние зависимости (etcd, minio, pulsar/bookkeeper).

---

## 1. Критичные pod Milvus (ядро сервиса)

### `milvus-proxy-*`
- **Роль:** входная точка для клиентских запросов.
- **Порты:** gRPC `19530`, metrics/health `9091`.
- **Зачем нужен:** через него идут SDK-запросы (`insert`, `search`, `query` и т.д.).
- **Если падает:** клиенты не подключаются к Milvus.
- **Критичность:** очень высокая.

### `milvus-mixcoord-*`
- **Роль:** координатор (объединение root/query/data/index coord в одном процессе).
- **Зачем нужен:** управляет метаданными, роутингом задач, состоянием сегментов/индексов.
- **Если падает:** кластер теряет координацию, операции начинают сбоить.
- **Критичность:** очень высокая.

### `milvus-querynode-*`
- **Роль:** исполняет `search/query` по загруженным сегментам/индексам.
- **Зачем нужен:** фактическая обработка поисковых запросов.
- **Если падает:** поиск/чтение недоступны или частично деградируют.
- **Критичность:** очень высокая.

### `milvus-datanode-*`
- **Роль:** обработка потока вставок, flush/compaction, запись данных.
- **Зачем нужен:** обеспечивает путь записи данных в хранилище.
- **Если падает:** вставки/ингест ломаются или сильно деградируют.
- **Критичность:** очень высокая.

### `milvus-indexnode-*`
- **Роль:** построение индексов.
- **Зачем нужен:** ускорение векторного поиска.
- **Если падает:** поиск может остаться только на FLAT/без обновления индексов, рост latency.
- **Критичность:** высокая.

---

## 2. Критичные зависимости Milvus

### `milvus-etcd-0`
- **Роль:** метахранилище состояния кластера.
- **Зачем нужно:** хранит служебные метаданные Milvus.
- **Если падает:** критическая деградация/недоступность кластера.
- **Критичность:** очень высокая.

### `milvus-minio-*`
- **Роль:** S3-совместимое объектное хранилище.
- **Зачем нужно:** хранит данные сегментов и артефакты индексов.
- **Если падает:** запись/чтение данных срываются.
- **Критичность:** очень высокая.

### `milvus-pulsarv3-broker-0`
- **Роль:** message broker для внутренних событий/очередей Milvus.
- **Если падает:** нарушается асинхронный data flow.
- **Критичность:** очень высокая.

### `milvus-pulsarv3-zookeeper-0`
- **Роль:** координация компонентов Pulsar/BookKeeper.
- **Если падает:** Pulsar-стек становится нестабилен.
- **Критичность:** очень высокая.

### `milvus-pulsarv3-bookie-{0,1,2}`
- **Роль:** durable log storage для Pulsar (BookKeeper).
- **Если падает:** риск потери устойчивости message-слоя.
- **Критичность:** очень высокая.

### `milvus-pulsarv3-recovery-0`
- **Роль:** autorecovery BookKeeper.
- **Если падает:** падает самовосстановление bookie-кластера.
- **Критичность:** высокая.

### `milvus-pulsarv3-proxy-0`
- **Роль:** proxy-слой Pulsar.
- **Если падает:** доступ к broker-слою может деградировать.
- **Критичность:** высокая.

---

## 3. Технические init pod (нормально, что Completed)

### `milvus-pulsarv3-bookie-init-*`
### `milvus-pulsarv3-pulsar-init-*`
- **Роль:** одноразовая инициализация Pulsar/BookKeeper metadata.
- **Статус `Completed`:** это нормально, не ошибка.
- **Критичность:** низкая после завершения.

---

## 4. Приоритет важности (что мониторить в первую очередь)

1. `proxy`, `mixcoord`
2. `querynode`, `datanode`, `indexnode`
3. `etcd`, `minio`, `pulsar broker/zookeeper/bookie`
4. `pulsar recovery/proxy`
5. init pod (`Completed`)

---

## 5. Быстрая диагностика инцидента

```bash
kubectl get pods -n milvus
kubectl get endpoints -n milvus milvus
kubectl logs -n milvus deploy/milvus-proxy --tail=200
kubectl logs -n milvus deploy/milvus-mixcoord --tail=200
kubectl get pvc -n milvus
kubectl get events -n milvus --sort-by=.lastTimestamp | tail -n 50
```

### Типовые сигналы
- Нет `milvus-proxy` Ready -> клиенты не подключаются.
- Нет `mixcoord` Ready -> оркестрация задач ломается.
- Нет `querynode` Ready -> поиск недоступен.
- Нет `datanode` Ready -> вставки не проходят.
- Нет `etcd/minio/pulsar` Ready -> системная авария distributed-режима.

---

## 6. После рестарта Docker / kind и встроенный RBAC

- Если поды Milvus падают с таймаутом etcd/DNS сразу после холодного старта кластера, см. **[MILVUS_POST_RESTART_RECOVERY.md](./MILVUS_POST_RESTART_RECOVERY.md)** (RCA, `rollout restart`, профилактика).
- Если включена аутентификация Milvus (`authorizationEnabled`), см. **[MILVUS_NATIVE_RBAC.md](./MILVUS_NATIVE_RBAC.md)** (логины, bootstrap пользователя `admin`).
- Пошаговый порядок восстановления при отказе компонентов (что за чем чинить, команды `rollout restart`): **[MILVUS_COMPONENT_FAILURE_RUNBOOK.md](./MILVUS_COMPONENT_FAILURE_RUNBOOK.md)**.

