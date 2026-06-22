# Архитектура: Milvus + LDAP / AD (без Keycloak)

**Это основная схема проекта.** Keycloak, JWT и `auth.keycloak.enabled` **не используются**.

| Нужно | Файл |
|-------|------|
| **Схема здесь (кратко)** | этот документ |
| **Подробно: взаимодействие** | [docs/architecture/COMPONENT_INTERACTION.md](docs/architecture/COMPONENT_INTERACTION.md) |
| **Подробно: авторизация** | [docs/architecture/AUTHORIZATION.md](docs/architecture/AUTHORIZATION.md) |
| **Установка gateway** | [LDAP_DOMAIN_LOGIN_ARCHITECTURE.md](LDAP_DOMAIN_LOGIN_ARCHITECTURE.md) |
| **Ядро Milvus (etcd, Pulsar…)** | [INFRASTRUCTURE_ARCHITECTURE.md](INFRASTRUCTURE_ARCHITECTURE.md) §3–6 |

---

## 1. Общая схема (LDAP + AD)

```mermaid
flowchart TB
  subgraph user["Пользователь"]
    U["логин AD + доменный пароль"]
  end

  subgraph corp["Корпоративный контур"]
    AD[("Active Directory<br/>LDAPS :636")]
  end

  subgraph k8s["Kubernetes — namespace milvus"]
    ATTU["Attu :3000"]
    GW["milvus-ldap-gateway<br/>Envoy :19530"]
    AUTH["ldap-auth-extauthz<br/>LDAP bind + token rewrite"]
    SYNC["CronJob milvus-ldap-sync<br/>AD группы → роли"]
    MV["milvus-proxy :19530"]
    CORE["mixcoord · query/data/index · etcd · MinIO · Pulsar"]
  end

  U --> ATTU
  U --> GW
  ATTU -->|"gRPC user:DOMAIN_PASSWORD"| GW
  GW -->|"ext_authz"| AUTH
  AUTH -->|"4. LDAP bind"| AD
  AUTH -->|"5. token user:SYNC_PASSWORD"| GW
  GW --> MV
  MV --> CORE

  AD -->|"service account read"| SYNC
  SYNC -->|"create_user / grant_role"| MV
```

---

## 2. Поток входа (каждый запрос)

```mermaid
sequenceDiagram
  participant C as Клиент / Attu
  participant G as milvus-ldap-gateway
  participant L as ldap-auth-extauthz
  participant D as AD / LDAPS
  participant M as milvus-proxy

  C->>G: gRPC + user:DOMAIN_PASSWORD
  G->>L: ext_authz Check
  L->>D: LDAP bind
  alt пароль верный
    L-->>G: OK + user:SYNC_PASSWORD
    G->>M: gRPC с внутренним token
    M-->>C: ответ (RBAC по роли из sync)
  else пароль неверный / УЗ заблокирована
    L-->>G: 403
    G-->>C: отказ
  end
```

---

## 3. Синхронизация пользователей и прав (фон)

Отдельно от входа, по расписанию (CronJob):

```mermaid
sequenceDiagram
  participant CJ as milvus-ldap-sync
  participant AD as AD / LDAPS
  participant M as milvus-proxy

  CJ->>AD: LDAPS bind (service account)
  CJ->>AD: search users + groups
  CJ->>M: create_user / grant_role
  Note over CJ,M: groupRoleMap: g-milvus-admin → admin и т.д.
```

---

## 4. Два слоя — не путать

| Слой | Компонент | Вопрос | Когда |
|------|-----------|--------|-------|
| **Провижининг** | `milvus-ldap-sync` | Кто есть в Milvus и какая роль? | CronJob (~15 мин) |
| **Runtime** | `ldap-auth-extauthz` | Верный ли доменный пароль? | Каждый gRPC-запрос |

Milvus **не** ходит в LDAP при каждом search/insert — только **ldap-auth** при входе. Права проверяет **Native RBAC** Milvus по роли, назначенной sync.

---

## 5. Endpoints для клиентов

| Кто | Куда | Пароль |
|-----|------|--------|
| Attu / SDK / CI (prod) | `milvus-ldap-gateway:19530` | **доменный** |
| Lab без gateway | `milvus:19530` | sync-пароль (только стенд) |

---

## 6. Не путать с JWT / Keycloak

Схема **«клиент → JWT → Envoy → Milvus»** в [INFRASTRUCTURE_ARCHITECTURE.md](INFRASTRUCTURE_ARCHITECTURE.md) §7 — это **шаблон upstream Helm**, SSO через Keycloak. **В наш проект не входит.**

Наш Envoy: **ext_authz + LDAP bind**, не `jwt_authn`.
