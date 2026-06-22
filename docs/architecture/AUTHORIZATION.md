# Архитектурная схема авторизации

**Версия:** 1.0  
**Дата:** 2026-06-22  
**Контур:** доменный логин AD + Milvus Native RBAC (без форка Milvus, без Keycloak)

Документ описывает **модель авторизации**: кто проверяет пароль, где принимаются решения о правах, как связаны AD-группы и роли Milvus. Для топологии компонентов см. [COMPONENT_INTERACTION.md](COMPONENT_INTERACTION.md).

---

## 1. Принципы

| Принцип | Реализация |
|---------|------------|
| **Единый пароль для человека** | Доменный пароль AD; пользователь не знает внутренний sync-пароль Milvus |
| **Единый источник политики ИБ** | GPO AD: lockout, сложность, срок пароля, история |
| **Права в Milvus** | Native RBAC (роли `reader` / `writer` / `admin`), провижининг из AD-групп |
| **Периметр** | Envoy `milvus-ldap-gateway` + `ldap-auth-extauthz`; прямой доступ к proxy ограничен NetworkPolicy |
| **Без форка Milvus** | Milvus проверяет только свой token `user:password`; LDAP bind — в sidecar |

---

## 2. Две подсистемы авторизации

```mermaid
flowchart TB
  subgraph idm["Корпоративный IdM"]
    AD[("Active Directory")]
    GPO["GPO: lockout, pwd policy"]
    GPO --> AD
  end

  subgraph prov["A. Провижининг (периодический)"]
    SYNC["milvus-ldap-sync<br/>CronJob"]
    MAP["groupRoleMap<br/>g-milvus-admin → admin"]
    SYNC --> MAP
  end

  subgraph runtime["B. Runtime (каждый запрос)"]
    GW["milvus-ldap-gateway"]
    AUTH["ldap-auth-extauthz"]
    GW --> AUTH
  end

  subgraph mv["Milvus Native RBAC"]
    USERS["users"]
    ROLES["roles + privileges"]
    CHECK["authorizationEnabled<br/>token check"]
  end

  AD -->|"LDAPS read + bind SA"| SYNC
  SYNC -->|"create_user, grant_role<br/>password = SYNC_PASSWORD"| USERS
  SYNC --> ROLES

  AD -->|"LDAP bind DOMAIN_PASSWORD"| AUTH
  AUTH -->|"rewrite token<br/>user:SYNC_PASSWORD"| GW
  GW --> CHECK
  CHECK --> ROLES
```

| Подсистема | Вопрос | Ответ даёт |
|------------|--------|------------|
| **A. ldap-sync** | Кто существует в Milvus и какая у него роль? | AD-группы → `groupRoleMap` → Milvus RBAC |
| **B. ldap-auth** | Верный ли доменный пароль прямо сейчас? | LDAP bind к AD |
| **Milvus proxy** | Разрешена ли операция для этой роли? | Native RBAC по token после rewrite |

---

## 3. Жизненный цикл учётной записи

```mermaid
stateDiagram-v2
  [*] --> AD_User: сотрудник в AD
  AD_User --> Milvus_User: ldap-sync create_user
  Milvus_User --> Milvus_Role: ldap-sync grant_role по группе
  Milvus_Role --> Login_OK: ldap-auth bind OK + RBAC allow
  Milvus_Role --> Login_Deny: ldap-auth bind fail
  Login_OK --> Milvus_Role: следующий запрос
  AD_User --> Removed: уволен / удалён из AD
  Removed --> Milvus_Revoke: sync удаляет / отзывает роль
```

---

## 4. Маппинг AD → Milvus RBAC

### 4.1 Группы → роли

```yaml
# values-ldap-sync-*.yaml / LDAP_GROUP_ROLE_MAP_JSON
groupRoleMap:
  g-milvus-admin: admin
  g-milvus-read: reader
  g-milvus-write: writer
```

```mermaid
flowchart LR
  subgraph ad_groups["AD groups (cn)"]
    G1["g-milvus-admin"]
    G2["g-milvus-read"]
    G3["g-milvus-write"]
  end

  subgraph milvus_roles["Milvus roles"]
    R1["admin"]
    R2["reader"]
    R3["writer"]
  end

  subgraph privs["Privileges (пример)"]
    P1["CollectionReadWrite, DatabaseReadWrite"]
    P2["CollectionReadOnly, DatabaseReadOnly"]
  end

  G1 --> R1
  G2 --> R2
  G3 --> R3
  R2 --> P2
  R3 --> P1
```

### 4.2 Нормализация имени

| Этап | Правило | Пример |
|------|---------|--------|
| AD login | `sAMAccountName` | `test514512` |
| Normalize | `LDAP_USERNAME_NORMALIZE` (sanitize / lower) | `test514512` |
| Milvus user | до 32 символов, `[A-Za-z0-9_]` | `test514512` |

Sync и ldap-auth **должны использовать одинаковый** `LDAP_USERNAME_NORMALIZE`.

---

## 5. Token flow (доменный пароль → Milvus)

```mermaid
flowchart LR
  subgraph client["Клиент"]
    T1["token = base64<br/>user:DOMAIN_PASSWORD"]
  end

  subgraph gateway["milvus-ldap-gateway"]
    EXT["filter ext_authz"]
    RW["header rewrite"]
  end

  subgraph auth["ldap-auth-extauthz"]
    BIND["LDAP bind"]
    T2["token = base64<br/>user:SYNC_PASSWORD"]
  end

  subgraph milvus["milvus-proxy"]
    RBAC["RBAC check"]
  end

  T1 --> EXT --> BIND
  BIND -->|"OK"| T2
  T2 --> RW --> RBAC
```

| Token | Кто знает | Где хранится |
|-------|-----------|--------------|
| `user:DOMAIN_PASSWORD` | Пользователь | Не хранится; только в запросе |
| `user:SYNC_PASSWORD` | Только K8s Secret | `ldap-auth-secret`, `ldap-sync-secret` |

`SYNC_PASSWORD` (`MILVUS_SYNC_DEFAULT_PASSWORD`) — технический пароль Milvus API, **не** предмет политики паролей для пользователя (см. [IB_TZ_COMPLIANCE_ARGUMENTATION.md](../../IB_TZ_COMPLIANCE_ARGUMENTATION.md)).

---

## 6. Последовательность: успешный вход

```mermaid
sequenceDiagram
  autonumber
  participant U as Пользователь
  participant A as Attu / SDK
  participant G as milvus-ldap-gateway
  participant L as ldap-auth-extauthz
  participant D as AD
  participant M as milvus-proxy

  U->>A: логин + DOMAIN_PASSWORD
  A->>G: gRPC Connect<br/>Authorization: Basic user:DOMAIN_PASSWORD
  G->>L: ext_authz POST /check
  L->>L: parse username, normalize
  L->>D: search user DN (service bind)
  L->>D: bind user DN + DOMAIN_PASSWORD
  D-->>L: success
  L->>L: record login_granted (JSON audit)
  L-->>G: 200 + Authorization: user:SYNC_PASSWORD
  G->>M: gRPC с переписанным token
  M->>M: RBAC: роль из sync
  M-->>G: OK (list DB, search, ...)
  G-->>A: ответ
  A-->>U: UI / данные
```

---

## 7. Последовательность: отказ (неверный пароль / блокировка)

```mermaid
sequenceDiagram
  autonumber
  participant A as Клиент
  participant G as gateway
  participant L as ldap-auth
  participant D as AD

  A->>G: user:WRONG_PASSWORD
  G->>L: ext_authz
  L->>D: bind → LDAP_INVALID_CREDENTIALS
  L->>L: failed_login_attempts++ (local state)
  L->>L: audit login_denied
  L-->>G: 403 Forbidden
  G-->>A: connection / auth error

  Note over D,L: При lockout в AD bind также fail;<br/>lock_reason в /user/info
```

---

## 8. Решение о правах на операцию (Milvus RBAC)

После успешного rewrite Milvus **не** обращается к LDAP:

```mermaid
flowchart TB
  REQ["gRPC: Search / Insert / CreateCollection"]
  PX["milvus-proxy"]
  AUTHZ["authorizationEnabled"]
  ROLE{"Роль пользователя"}
  PRIV["privileges роли"]
  ALLOW["200 OK"]
  DENY["Permission denied"]

  REQ --> PX --> AUTHZ --> ROLE
  ROLE --> PRIV
  PRIV -->|"privilege covers op"| ALLOW
  PRIV -->|"нет права"| DENY
```

| Роль | Типовые privileges | Операции |
|------|-------------------|----------|
| `reader` | CollectionReadOnly, DatabaseReadOnly | search, query, describe |
| `writer` | CollectionReadWrite, DatabaseReadWrite | insert, upsert, flush, create collection |
| `admin` | All | управление, grant, DDL |

Роль назначает **только** ldap-sync из AD-группы.

---

## 9. API `/api/v1/user/info` — поля ТЗ ИБ

```mermaid
flowchart TB
  REQ["GET /api/v1/user/info"]
  GW["Envoy: route → ldap-auth<br/>(ext_authz off)"]
  AUTH["ldap-auth-extauthz"]
  AD[("AD attributes")]
  JSON["JSON response"]

  REQ --> GW --> AUTH
  AUTH --> AD
  AUTH --> JSON
```

| Поле ответа | Источник AD | Назначение |
|-------------|-------------|------------|
| `last_login` | `lastLogonTimestamp` / local state | Аудит активности |
| `password_expiry_date` | `pwdLastSet` + `maxPwdAge` | Контроль срока пароля |
| `account_locked` | `lockoutTime`, `userAccountControl` | Блокировка УЗ |
| `lock_reason` | lockout / expired / disabled | Текст для ИБ |
| `failed_login_attempts` | `badPwdCount` + local state | П. 1.1 ТЗ |
| `password_last_changed` | `pwdLastSet` | История пароля |

Пути: `/api/v1/user/info`, `/user/info`, `/ldap/user/info` — см. `USER_INFO_PATHS` в `scripts/ldap_auth_extauthz.py`.

---

## 10. Зоны доверия

```mermaid
flowchart TB
  subgraph untrusted["Недоверенная зона"]
    USER["Пользователь / рабочая станция"]
  end

  subgraph dmz["Периметр K8s — доверенный код организации"]
    GW["milvus-ldap-gateway"]
    AUTH["ldap-auth-extauthz"]
  end

  subgraph trusted["Доверенная зона — данные"]
    MV["milvus-proxy + workers"]
    DATA[("векторные данные")]
  end

  subgraph idm["Корпоративный IdM"]
    AD[("AD")]
  end

  USER -->|"только :19530 gateway<br/>доменный пароль"| GW
  GW --> AUTH
  AUTH -->|"LDAPS"| AD
  GW --> MV
  MV --> DATA
```

**NetworkPolicy** (`manifests/ldap-auth/networkpolicy-milvus-ldap.yaml`):

- Ingress на `milvus-proxy:19530` — только от gateway, ldap-sync, ldap-auth.
- Break-glass: pods в namespace `milvus` (port-forward админом).

---

## 11. Сравнение режимов

| Режим | Milvus address | Пароль в UI | LDAP runtime | Для prod |
|-------|----------------|-------------|--------------|----------|
| **Lab без gateway** | `milvus:19530` | sync-пароль | нет (только sync) | только lab |
| **Prod LDAP gateway** | `milvus-ldap-gateway:19530` | доменный | да (bind на каждый запрос) | **да** |

Sync (`milvus-ldap-sync`) нужен **в обоих** режимах — он создаёт пользователей и роли в Milvus из AD-групп.

---

## 12. Аудит и корреляция

```mermaid
flowchart LR
  subgraph events["События"]
    E1["login_granted"]
    E2["login_denied"]
    E3["user_info_ok"]
    E4["users_synced"]
  end

  subgraph fields["Обязательные поля JSON"]
    F["ts, component, event, username, client_ip"]
  end

  subgraph sink["Приёмник"]
    SIEM["SIEM"]
  end

  E1 & E2 & E3 & E4 --> F --> SIEM
```

Источники:

- `kubectl logs deploy/ldap-auth-extauthz`
- Envoy access log (ConfigMap gateway)
- CronJob ldap-sync logs

---

## 13. Отказоустойчивость авторизации

| Сбой | Поведение | Действие ops |
|------|-----------|--------------|
| AD недоступен | ext_authz → 403, вход невозможен | Проверить LDAPS, CA, firewall |
| ldap-auth pod down | Envoy `failure_mode_allow: false` → отказ | Restart deployment, HPA |
| sync не бежал | Пользователь есть в AD, нет в Milvus | Ручной Job sync |
| Неверная группа AD | В Milvus роль `reader` по умолчанию / нет grant | Проверить `groupRoleMap` |
| Прямой `milvus:19530` | NetworkPolicy deny (prod) | Только break-glass |

---

## 14. Rollback авторизации

```bash
kubectl -n milvus delete deploy,svc,cm -l app.kubernetes.io/name=milvus-ldap-gateway
kubectl -n milvus delete deploy,svc -l app.kubernetes.io/name=ldap-auth-extauthz
# NetworkPolicy — удалить или ослабить
# Attu → milvus:19530 + sync-пароль (временно)
```

**ldap-sync CronJob не удалять** — RBAC остаётся актуальным.

---

## 15. Связанные артефакты

| Артефакт | Путь |
|----------|------|
| ext_authz + user/info | `scripts/ldap_auth_extauthz.py` |
| RBAC sync | `scripts/milvus_ldap_sync.py` |
| Envoy config | `manifests/ldap-auth/envoy-milvus-gateway.yaml` |
| Deploy ldap-auth | `manifests/ldap-auth/ldap-auth-extauthz.yaml` |
| NetworkPolicy | `manifests/ldap-auth/networkpolicy-milvus-ldap.yaml` |
| Установка | `scripts/48-install-ldap-auth-gateway.sh` |
| Тесты | [LDAP_MILVUS_TEST_PROTOCOL.md](../../LDAP_MILVUS_TEST_PROTOCOL.md) |

---

*Модель согласована с [IB_TZ_COMPLIANCE_ARGUMENTATION.md](../../IB_TZ_COMPLIANCE_ARGUMENTATION.md) и [IS_REQUIREMENTS_LDAP_PROXY.md](../../IS_REQUIREMENTS_LDAP_PROXY.md).*
