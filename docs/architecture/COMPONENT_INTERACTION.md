# Архитектурная схема взаимодействия компонентов

**Версия:** 1.0  
**Дата:** 2026-06-22  
**Контур:** Milvus 2.5.x distributed + LDAP (вариант B: Envoy gateway + ldap-auth + ldap-sync)

Документ описывает **кто с кем общается**, по каким протоколам и в каком направлении. Для логики входа и RBAC см. [AUTHORIZATION.md](AUTHORIZATION.md).

---

## 1. Контекст системы

```mermaid
flowchart TB
  subgraph users["Пользователи и системы"]
    U1["Аналитик / разработчик<br/>браузер → Attu"]
    U2["ETL / CI / PyMilvus<br/>gRPC SDK"]
    U3["SIEM / мониторинг<br/>логи, метрики"]
    ADM["Администратор K8s<br/>kubectl, Helm"]
  end

  subgraph corp["Корпоративный контур"]
    AD[("Active Directory / LDAP<br/>LDAPS :636")]
    REG["Container registry<br/>{{ INTERNAL_REGISTRY }}"]
    SIEM["SIEM / ELK"]
  end

  subgraph k8s["Kubernetes — namespace milvus"]
    GW["milvus-ldap-gateway"]
    AUTH["ldap-auth-extauthz"]
    SYNC["CronJob ldap-sync"]
    MV["Milvus distributed"]
    ATTU["Attu"]
    INF["etcd · MinIO · Pulsar"]
  end

  U1 --> ATTU
  U1 --> GW
  U2 --> GW
  ATTU --> GW
  GW --> AUTH
  AUTH --> AD
  SYNC --> AD
  SYNC --> MV
  GW --> MV
  MV --> INF
  AUTH --> SIEM
  GW --> SIEM
  ADM --> k8s
  REG -.->|"docker pull / load"| k8s
  SIEM <-- U3
```

---

## 2. Полная карта компонентов в Kubernetes

```mermaid
flowchart TB
  subgraph ext["Вне кластера"]
    CLIENT["Клиенты SDK / браузер"]
    LDAPS[("AD / LDAPS")]
  end

  subgraph ns["namespace: milvus"]
    subgraph perimeter["Периметр LDAP (кастомные сервисы)"]
      SVC_GW["Service milvus-ldap-gateway<br/>:19530 TCP"]
      DEP_GW["Deployment Envoy<br/>envoy-nonroot:v1.31.2"]
      CM_GW["ConfigMap milvus-ldap-gateway-envoy"]
      SVC_AUTH["Service ldap-auth-extauthz<br/>:8080 HTTP"]
      DEP_AUTH["Deployment ldap-auth-extauthz<br/>milvus-ldap-auth-nonroot:2.5.0"]
      SEC_AUTH["Secret ldap-auth<br/>bind pwd, sync pwd"]
      CA_AUTH["ConfigMap ldap-auth-ca"]
    end

    subgraph provision["Провижининг RBAC"]
      CJ["CronJob milvus-ldap-sync<br/>schedule */15 * * * *"]
      CM_SYNC["ConfigMap milvus-ldap-sync-config"]
      SEC_SYNC["Secret milvus-ldap-sync"]
      CA_SYNC["ConfigMap milvus-ldap-sync-ca"]
    end

    subgraph milvus["Milvus 2.5 distributed"]
      SVC_M["Service milvus<br/>:19530 / :9091"]
      PX["Deployment milvus-proxy"]
      MC["Deployment milvus-mixcoord"]
      QN["Deployment milvus-querynode"]
      DN["Deployment milvus-datanode"]
      IN["Deployment milvus-indexnode"]
    end

    subgraph deps["Зависимости Milvus"]
      ETCD[("StatefulSet milvus-etcd")]
      MINIO[("StatefulSet milvus-minio")]
      PULSAR["StatefulSet Pulsar v3<br/>ZK + broker + bookie"]
    end

    subgraph ui["UI"]
      SVC_A["Service attu :3000"]
      DEP_A["Deployment attu-nonroot"]
    end

    NP["NetworkPolicy<br/>proxy ← только gateway/sync/auth"]
  end

  CLIENT --> SVC_GW
  CLIENT --> SVC_A
  SVC_GW --> DEP_GW
  CM_GW --> DEP_GW
  DEP_GW -->|"ext_authz HTTP"| SVC_AUTH
  DEP_GW -->|"gRPC upstream"| SVC_M
  DEP_AUTH --> LDAPS
  CJ --> LDAPS
  CJ --> SVC_M
  SVC_A --> DEP_A
  DEP_A --> SVC_GW
  SVC_M --> PX
  PX --> MC
  MC --> ETCD
  MC --> PULSAR
  QN & DN & IN --> MINIO
  QN & DN & IN --> PULSAR
  NP -.-> PX
```

---

## 3. Два плоскости взаимодействия

| Плоскость | Компоненты | Когда | Протокол |
|-----------|------------|-------|----------|
| **Провижининг (control)** | `milvus-ldap-sync` → AD → Milvus | CronJob каждые 15 мин (настраивается) | LDAPS search + Milvus REST/gRPC (root) |
| **Runtime (data path)** | Клиент → gateway → ldap-auth → Milvus | Каждый запрос SDK / Attu | gRPC + HTTP ext_authz + LDAPS bind |

```mermaid
flowchart LR
  subgraph control["Control plane — RBAC sync"]
    AD1[AD]
    SYNC[milvus-ldap-sync]
    MV1[Milvus RBAC]
    AD1 --> SYNC --> MV1
  end

  subgraph data["Data plane — запросы к векторной БД"]
    CL[Клиент]
    GW[milvus-ldap-gateway]
    AUTH[ldap-auth]
    AD2[AD]
    MV2[milvus-proxy]
    CL --> GW --> AUTH
    AUTH --> AD2
    GW --> MV2
  end
```

---

## 4. Последовательность: синхронизация AD → Milvus

```mermaid
sequenceDiagram
  autonumber
  participant CJ as CronJob ldap-sync
  participant AD as AD / LDAPS
  participant MV as milvus-proxy
  participant RBAC as Milvus Native RBAC

  Note over CJ: Service account bind (Secret)
  CJ->>AD: LDAPS bind (LDAP_BIND_DN)
  CJ->>AD: search users (LDAP_USER_BASE)
  loop каждый пользователь
    CJ->>AD: search groups (LDAP_GROUP_BASE, member=user DN)
    CJ->>CJ: map group → role (groupRoleMap)
    CJ->>CJ: normalize username (sAMAccountName → Milvus name)
  end
  CJ->>MV: connect (MILVUS_URI, root token)
  loop идемпотентный upsert
    CJ->>RBAC: create_user / update_password (sync pwd)
    CJ->>RBAC: grant_role(role)
  end
  CJ->>CJ: JSON log: users_synced, roles_granted
```

**Важно:** sync **не** участвует в каждом логине пользователя. Он только поддерживает учётки и роли в Milvus в актуальном состоянии относительно AD.

---

## 5. Последовательность: пользовательский запрос (Attu / SDK)

```mermaid
sequenceDiagram
  autonumber
  participant C as Клиент / Attu
  participant GW as milvus-ldap-gateway
  participant AUTH as ldap-auth-extauthz
  participant AD as AD / LDAPS
  participant MV as milvus-proxy
  participant W as query/data/index nodes

  C->>GW: gRPC :19530<br/>Authorization: base64(user:DOMAIN_PASSWORD)
  GW->>AUTH: HTTP ext_authz Check<br/>header authorization
  AUTH->>AD: LDAP bind (user DN + DOMAIN_PASSWORD)
  alt bind OK
    AUTH->>AUTH: rewrite → user:SYNC_PASSWORD
    AUTH-->>GW: 200 OK + new Authorization header
    GW->>MV: gRPC с token user:SYNC_PASSWORD
    MV->>W: внутренний RPC
    W-->>MV: результат
    MV-->>GW: ответ
    GW-->>C: ответ клиенту
  else bind fail
    AUTH-->>GW: 403 Forbidden
    GW-->>C: отказ
    AUTH->>AUTH: audit JSON login_denied
  end
```

---

## 6. API `/api/v1/user/info` (ТЗ ИБ)

Маршрут **не** идёт в Milvus — Envoy направляет его напрямую в `ldap-auth-extauthz` (ext_authz для этого path отключён).

```mermaid
sequenceDiagram
  participant C as Клиент
  participant GW as milvus-ldap-gateway
  participant AUTH as ldap-auth-extauthz
  participant AD as AD / LDAPS

  C->>GW: GET /api/v1/user/info<br/>Authorization: user:DOMAIN_PASSWORD
  GW->>AUTH: proxy route (ext_authz disabled)
  AUTH->>AD: service bind + read user attrs
  AUTH->>AUTH: map lockout, pwd expiry, badPwdCount
  AUTH-->>GW: JSON 200
  GW-->>C: last_login, password_expiry_date,<br/>account_locked, lock_reason, ...
```

---

## 7. Таблица сетевых endpoint'ов

| Service | Порт | Протокол | Кто обращается | Назначение |
|---------|------|----------|----------------|------------|
| `milvus-ldap-gateway` | 19530 | gRPC/HTTP2 | SDK, Attu, CI | **Единая точка входа** для пользователей |
| `ldap-auth-extauthz` | 8080 | HTTP | Envoy (внутри кластера) | ext_authz + `/api/v1/user/info` |
| `milvus` (proxy) | 19530 | gRPC | gateway, sync, break-glass | Ядро Milvus |
| `milvus` (proxy) | 9091 | HTTP | ops, Web UI | Метрики, slow query UI |
| `attu` | 3000 | HTTP | браузер | Веб-консоль |
| AD / LDAPS | 636 | LDAPS | ldap-auth, ldap-sync | Каталог |

---

## 8. Зависимости данных Milvus (runtime)

Пользовательский gRPC-запрос после авторизации обрабатывается стандартным distributed-стеком:

```mermaid
flowchart TB
  PX["milvus-proxy"]
  MC["mixcoord"]
  QN["querynode"]
  DN["datanode"]
  IN["indexnode"]
  ETCD[("etcd — метаданные")]
  MINIO[("MinIO — сегменты, индексы")]
  PL["Pulsar — внутренняя шина"]

  PX --> MC
  MC --> ETCD
  MC --> QN & DN & IN
  QN & DN & IN --> MINIO
  MC & DN & QN & IN --> PL
```

Подробнее: [INFRASTRUCTURE_ARCHITECTURE.md](../../INFRASTRUCTURE_ARCHITECTURE.md).

---

## 9. Сетевая изоляция (NetworkPolicy)

```mermaid
flowchart TB
  subgraph allowed["Разрешён ingress на milvus-proxy :19530"]
    GW["milvus-ldap-gateway"]
    SYNC["milvus-ldap-sync"]
    AUTH["ldap-auth-extauthz"]
    NS["pods в namespace milvus<br/>(break-glass / port-forward)"]
  end

  subgraph denied["Заблокировано для внешних клиентов"]
    EXT["Прямой SDK → milvus:19530<br/>с доменным паролем"]
  end

  PX["milvus-proxy"]
  GW & SYNC & AUTH & NS --> PX
  EXT -.->|deny| PX
```

Манифест: `manifests/ldap-auth/networkpolicy-milvus-ldap.yaml`.

---

## 10. Lab vs Prod

| Аспект | Lab (kind + OpenLDAP) | Prod (корп. AD) |
|--------|----------------------|-----------------|
| LDAP | OpenLDAP в `manifests/ldap-lab/` | LDAPS корпоративного AD |
| Адрес Milvus в Attu | `milvus-ldap-gateway:19530` | то же |
| Пароль в UI | доменный (lab) или sync (без gateway) | **только доменный** через gateway |
| Атрибуты AD | fallback без `userAccountControl` | полный набор ТЗ ИБ |
| Образы | `kind load` / локальный registry | `{{ INTERNAL_REGISTRY }}` |

---

## 11. Наблюдаемость и аудит

```mermaid
flowchart LR
  AUTH["ldap-auth-extauthz"]
  GW["Envoy gateway"]
  SYNC["ldap-sync"]
  SIEM["SIEM / ELK"]
  PROM["Prometheus / Grafana"]

  AUTH -->|"JSON: login_granted,<br/>login_denied, user_info_ok"| SIEM
  GW -->|"access log"| SIEM
  SYNC -->|"users_synced, errors"| SIEM
  MV["milvus-proxy :9091"] --> PROM
```

---

## 12. Что намеренно вне этой схемы

- **Keycloak / JWT gateway** — альтернативный путь (вариант A), см. [KEYCLOAK_AUTH_FOR_MILVUS.md](../../KEYCLOAK_AUTH_FOR_MILVUS.md).
- **Миграция Pulsar → Kafka** — см. [docs/kafka/README.md](../kafka/README.md).
- **Init Jobs** Pulsar/BookKeeper — одноразовые pod'ы при установке.

---

*Схемы соответствуют манифестам `manifests/ldap-auth/`, скриптам `scripts/ldap_auth_extauthz.py`, `scripts/milvus_ldap_sync.py` и Helm chart Milvus 4.2.33.*
