# Протокол тестирования: Milvus 2.5.0 + LDAP (доменный вход и RBAC-sync)

| Поле | Значение |
|------|----------|
| **Дата проведения** | 2026-06-22 |
| **Стенд** | kind `milvus-k121`, namespace `milvus` |
| **Назначение** | Проверка требований к учётным записям, аутентификации, API `/api/v1/user/info`, RBAC-sync, non-root образов |
| **Версия Milvus** | 2.5.0 (`milvus-nonroot:2.5.0`) |
| **Исполнитель** | автоматизированный прогон + ручная верификация |

> **Пароли lab** в документе заменены на `**********`. Фактические значения — в `manifests/ldap-lab/` и `*.lab.yaml` (только для kind-стенда).

---

## 1. Объект тестирования

Комплекс из компонентов:

| Компонент | Образ / версия | Назначение |
|-----------|----------------|------------|
| Milvus | `milvus-nonroot:2.5.0` | Векторная БД, RBAC |
| Attu | `attu-nonroot:2.5.10` | Web UI |
| OpenLDAP (только lab) | `osixia/openldap` | Имитация корпоративного каталога |
| `milvus-ldap-sync` | `milvus-ldap-sync-nonroot:2.5.0` | CronJob: LDAP → пользователи/роли Milvus |
| `milvus-ldap-auth` | `milvus-ldap-auth-nonroot:2.5.0` | LDAP bind, ext_authz, `/api/v1/user/info` |
| `milvus-ldap-gateway` | `envoy-nonroot:v1.31.2` | Единая точка входа `:19530` |

**Архитектура:**

```
OpenLDAP (lab) / AD LDAPS (prod)
        │
        ├─► milvus-ldap-sync (CronJob) ──► Milvus users/roles
        │
Клиент ─► milvus-ldap-gateway (Envoy) ──► milvus-ldap-auth ──► Milvus proxy
              доменный пароль              LDAP bind + token rewrite
```

---

## 2. Конфигурация стенда (фактические значения lab)

### 2.1. LDAP RBAC Sync (`ConfigMap/milvus-ldap-sync-config`)

```yaml
LDAP_URI: ldap://openldap-lab:389
LDAP_BIND_DN: cn=admin,dc=lab,dc=local
LDAP_USER_BASE: ou=users,dc=lab,dc=local
LDAP_GROUP_BASE: ou=groups,dc=lab,dc=local
LDAP_USER_FILTER: (objectClass=inetOrgPerson)
LDAP_USERNAME_ATTR: uid
LDAP_USERNAME_NORMALIZE: none
LDAP_GROUP_ROLE_MAP_JSON: '{"g-milvus-read": "reader"}'
LDAP_ROLE_PRIVILEGES_JSON: '{"reader": ["CollectionReadOnly", "DatabaseReadOnly"]}'
LDAP_MILVUS_REVOKE_ORPHAN: "true"
LDAP_SYNC_DRY_RUN: "false"
MILVUS_HOST: milvus
MILVUS_PORT: "19530"
MILVUS_ROOT_USER: root
MILVUS_SUPER_USERS: root,admin
```

Секреты (`Secret/milvus-ldap-sync`): `LDAP_BIND_PASSWORD`, `MILVUS_ROOT_PASSWORD`, `MILVUS_SYNC_DEFAULT_PASSWORD` — **не приводятся в протоколе** (хранятся в K8s Secret).

Внутренний sync-пароль Milvus для lab-пользователей: `**********` (≥6 символов, требование Milvus API).

### 2.2. LDAP Auth Gateway (`ConfigMap/ldap-auth-extauthz-config`)

```yaml
LDAP_URI: ldap://openldap-lab:389
LDAP_BIND_DN: cn=admin,dc=lab,dc=local
LDAP_USER_BASE: ou=users,dc=lab,dc=local
LDAP_USER_FILTER: (objectClass=inetOrgPerson)
LDAP_USERNAME_ATTR: uid
LDAP_USERNAME_NORMALIZE: none
HTTP_PORT: "8080"
```

### 2.3. Lab-учётные записи

| LDAP uid | LDAP-пароль | Группа | Роль Milvus |
|----------|-------------|--------|-------------|
| `testuser` | `**********` | `g-milvus-read` | `reader` |
| `milvus655` | `**********` | `g-milvus-read` | `reader` |

### 2.4. Расписание sync

```text
CronJob: milvus-ldap-sync
Schedule: */15 * * * *
ConcurrencyPolicy: Forbid
```

### 2.5. SecurityContext (целевой)

| Workload | runAsUser | runAsGroup | fsGroup | readOnlyRootFilesystem |
|----------|-----------|------------|---------|------------------------|
| `milvus-ldap-sync` | 65000 | 65000 | 65000 | true |
| `ldap-auth-extauthz` | 65000 | 65000 | 65000 | true |
| `milvus-ldap-gateway` (envoy) | 65000 | 65000 | 65000 | — |

---

## 3. Реестр артефактов поставки

### 3.1. Образы LDAP-sidecar (prep-стенд → изолированный контур)

Каталог: `milfus-main/artifacts/images/`

| Файл | Размер | Тег внутри tar.gz | Проверка |
|------|--------|-------------------|----------|
| `milvus-ldap-sync-nonroot_2.5.0.tar.gz` | 163 MB | `milvus-ldap-sync-nonroot:2.5.0` | `tar -tzf` OK, `id` → uid=65000 |
| `milvus-ldap-auth-nonroot_2.5.0.tar.gz` | 48 MB | `milvus-ldap-auth-nonroot:2.5.0` | `tar -tzf` OK, `id` → uid=65000 |

Загрузка на изолированном контуре:

```bash
gunzip -c milvus-ldap-sync-nonroot_2.5.0.tar.gz | docker load
gunzip -c milvus-ldap-auth-nonroot_2.5.0.tar.gz | docker load
```

> **Примечание:** в `milvus-ldap-sync` после протокола внесён fix совместимости с OpenLDAP (fallback атрибутов AD). Перед prod пересобрать: `./scripts/57-build-ldap-images-nonroot.sh` и обновить tar.gz.

### 3.2. Образы стека Milvus (отдельный каталог)

Каталог: `milvus-delivery/k8s/images/` — non-root Milvus, etcd, minio, pulsar, config-tool и др. (собираются `scripts/53-build-all-nonroot-images.sh`, `scripts/56-build-nonroot-deps-and-export.sh`).

### 3.3. Исходники и манифесты (`milfus-main/`)

| Категория | Путь |
|-----------|------|
| **Dockerfile sync** | `docker/milvus-ldap-sync/Dockerfile` |
| **Dockerfile auth** | `docker/ldap-auth-extauthz/Dockerfile` |
| **Скрипты** | `scripts/milvus_ldap_sync.py`, `scripts/ldap_auth_extauthz.py` |
| **Сборка образов** | `scripts/57-build-ldap-images-nonroot.sh` |
| **Установка** | `scripts/46-install-ldap-sync.sh`, `scripts/48-install-ldap-auth-gateway.sh` |
| **Lab bootstrap** | `scripts/47-setup-ldap-lab.sh`, `scripts/49-setup-ldap-auth-gateway-lab.sh` |
| **K8s manifests sync** | `manifests/ldap-sync/cronjob.yaml`, `*-secret.example.yaml`, `*-ca.example.yaml` |
| **K8s manifests auth** | `manifests/ldap-auth/*.yaml` (envoy, deployment, networkpolicy) |
| **Lab OpenLDAP** | `manifests/ldap-lab/openldap.yaml` |
| **Values lab** | `values/values-ldap-sync-kind-lab.yaml`, `values/values-ldap-auth-gateway-kind-lab.yaml` |
| **Values prod examples** | `values/values-ldap-sync-milvus-k121.yaml`, `values/values-ldap-auth-gateway.example.yaml` |
| **Документация** | `LDAP_DOMAIN_LOGIN_ARCHITECTURE.md`, `LDAPS_RBAC_SYNC_SETUP.md`, `CORP_LDAP_DEPLOYMENT_CHECKLIST.md`, `IB_TZ_COMPLIANCE_ARGUMENTATION.md` |

**Helm:** компоненты LDAP поставляются **отдельными K8s-манифестами** (не subchart Milvus Helm). Milvus core — штатный Helm chart (`helm install milvus`).

---

## 4. Матрица тестов и результаты

| ID | Проверка | Метод | Ожидание | Результат |
|----|----------|-------|----------|-----------|
| T-01 | Состояние подов LDAP-стека | `kubectl get pods -n milvus` | Running: gateway, ldap-auth, openldap-lab | **PASS** |
| T-02 | Non-root образы (UID 65000) | `docker run --entrypoint id …` | uid=gid=65000 | **PASS** |
| T-03 | tar.gz целостность | `tar -tzf`, manifest RepoTags | 2 архива, корректные теги | **PASS** |
| T-04 | LDAP → Milvus RBAC sync | Job/CronJob + логи | users=2, roles=reader | **PASS** |
| T-05 | Список пользователей Milvus | `list_users()` от root | `testuser`, `milvus655` | **PASS** |
| T-06 | Вход через gateway (`testuser`) | pymilvus → `milvus-ldap-gateway:19530` | `list_databases()` OK | **PASS** |
| T-07 | Вход через gateway (`milvus655`) | то же | OK | **PASS** |
| T-08 | Отказ при неверном пароле | неверный пароль | PERMISSION_DENIED | **PASS** |
| T-09 | API `/api/v1/user/info` (ldap-auth) | GET + Basic Auth | 6 полей ТЗ в JSON | **PASS** |
| T-10 | API `/api/v1/user/info` (gateway) | GET через Envoy route | тот же JSON | **PASS** |
| T-11 | Аудит входов | логи ldap-auth | JSON `login_granted` / `login_denied` | **PASS** |
| T-12 | NetworkPolicy на Milvus proxy | `kubectl get networkpolicy` | ingress только от gateway/sync/auth | **PASS** |
| T-13 | Break-glass прямой Milvus | `milvus:19530` + sync-пароль | OK (документированный путь) | **PASS** |
| T-14 | CronJob nonroot image | manifest + securityContext | `milvus-ldap-sync-nonroot:2.5.0`, uid 65000 | **PASS** (после apply manifest) |

---

## 5. Фрагменты логов

### 5.1. LDAP → Milvus sync (T-04)

```text
LDAP -> Milvus sync start
ldap users fetched: 2
update user 'milvus655' roles=['reader']
update user 'testuser' roles=['reader']
LDAP -> Milvus sync OK
```

### 5.2. Успешный вход через gateway (T-06, T-07)

```text
testuser OK ['default']
milvus655 OK ['default']
```

### 5.3. Отказ при неверном пароле (T-08)

```text
DENIED _InactiveRpcError
status = StatusCode.PERMISSION_DENIED
```

Соответствующая запись аудита:

```json
{"ts":"2026-06-22T18:48:56.498582+00:00","component":"milvus-ldap-auth","event":"login_denied","username":"testuser","reason":"invalid_credentials","failed_login_attempts":1,"client_result":"deny"}
```

### 5.4. Успешный вход — аудит (T-11)

```json
{"ts":"2026-06-22T18:48:55.177268+00:00","component":"milvus-ldap-auth","event":"login_granted","username":"testuser","milvus_username":"testuser","client_result":"allow"}
{"ts":"2026-06-22T18:48:55.288493+00:00","component":"milvus-ldap-auth","event":"login_granted","username":"milvus655","milvus_username":"milvus655","client_result":"allow"}
```

### 5.5. API `/api/v1/user/info` (T-09, T-10)

Запрос:

```http
GET /api/v1/user/info HTTP/1.1
Host: milvus-ldap-gateway:19530
Authorization: Basic dGVzdHVzZXI6VGVzdGxkcDE=
```

Ответ `200 OK`:

```json
{
  "username": "testuser",
  "milvus_username": "testuser",
  "last_login": "2026-06-22T18:49:03.004267+00:00",
  "password_expiry_date": null,
  "account_locked": false,
  "lock_reason": "",
  "failed_login_attempts": 0,
  "is_active": true
}
```

> `password_expiry_date: null` на OpenLDAP lab — ожидаемо; на prod AD заполняется из `pwdLastSet` + `maxPwdAge`.

Аудит:

```json
{"ts":"2026-06-22T18:40:23.462415+00:00","component":"milvus-ldap-auth","event":"user_info_ok","username":"testuser","account_locked":false}
```

### 5.6. Пользователи Milvus после sync (T-05)

```text
milvus users: ['milvus655', 'root', 'testuser']
```

### 5.7. NetworkPolicy (T-12)

```yaml
podSelector:
  matchLabels:
    app.kubernetes.io/name: milvus
    component: proxy
ingress:
  - from:
      - podSelector:
          matchLabels:
            app.kubernetes.io/name: milvus-ldap-gateway
      - podSelector:
          matchLabels:
            app.kubernetes.io/name: milvus-ldap-sync
      - podSelector:
          matchLabels:
            app.kubernetes.io/name: ldap-auth-extauthz
    ports:
      - port: 19530
        protocol: TCP
```

---

## 6. Команды воспроизведения

```bash
# Контекст
export NS=milvus
kubectl config use-context kind-milvus-k121

# Sync вручную
kubectl -n $NS create job milvus-ldap-sync-test --from=cronjob/milvus-ldap-sync
kubectl -n $NS wait --for=condition=complete job/milvus-ldap-sync-test --timeout=120s
kubectl -n $NS logs job/milvus-ldap-sync-test

# Gateway + user/info (из pod с pymilvus)
kubectl -n $NS run test-runner --restart=Never \
  --image=milvus-ldap-sync-nonroot:2.5.0 --image-pull-policy=IfNotPresent \
  --command -- sleep 600
kubectl -n $NS wait --for=condition=Ready pod/test-runner --timeout=60s

kubectl -n $NS exec test-runner -- python3 -c "
from pymilvus import MilvusClient
c=MilvusClient(uri='http://milvus-ldap-gateway:19530', token='testuser:**********')
print(c.list_databases())
"

kubectl -n $NS exec test-runner -- python3 -c "
import urllib.request, base64, json
req=urllib.request.Request('http://milvus-ldap-gateway:19530/api/v1/user/info')
req.add_header('Authorization','Basic '+base64.b64encode(b'testuser:**********').decode())
print(json.loads(urllib.request.urlopen(req).read()))
"

kubectl -n $NS delete pod test-runner
```

---

## 7. Замечания и действия перед prod

| # | Замечание | Действие |
|---|-----------|----------|
| 1 | Lab использует OpenLDAP, prod — `ldaps://` + корпоративный CA | Заполнить `values-*-prod.yaml`, CA в Secret/ConfigMap |
| 2 | `password_expiry_date` на lab = null | На AD проверить отдельным прогоном T-09 |
| 3 | Пересборка `milvus-ldap-sync` tar.gz после fix OpenLDAP | `./scripts/57-build-ldap-images-nonroot.sh` |
| 4 | Break-glass `milvus:19530` доступен из namespace | Ограничить регламентом; NetworkPolicy уже применена |
| 5 | Attu: адрес `milvus-ldap-gateway:19530`, пароль — LDAP | Проверено вручную ранее на стенде |

---

## 8. Итоговое заключение

На стенде **kind `milvus-k121`** проведено **14 проверок**, результат **14 PASS / 0 FAIL**.

Подтверждено:

- доменный (LDAP) пароль принимается через `milvus-ldap-gateway`;
- RBAC-sync создаёт и обновляет пользователей Milvus из LDAP-групп;
- API `/api/v1/user/info` возвращает полный набор полей требований;
- отказ при неверном пароле фиксируется в audit-log;
- sidecar-образы работают от non-root UID/GID **65000**;
- tar.gz архивы LDAP-образов подготовлены в `milfus-main/artifacts/images/`;
- исходники, Dockerfile, K8s-манифесты, values и документация находятся в `milfus-main/`.

**Рекомендация:** допустить комплект к переносу на изолированный контур после пересборки sync-образа и заполнения prod-конфигурации LDAPS.

---

## 9. Подписи (заполняется при официальной приёмке)

| Роль | ФИО | Подпись | Дата |
|------|-----|---------|------|
| Исполнитель тестов | | | |
| Ответственный за эксплуатацию | | | |
| Представитель заказчика | | | |

---

*Связанные документы: [CORP_LDAP_DEPLOYMENT_CHECKLIST.md](CORP_LDAP_DEPLOYMENT_CHECKLIST.md), [IB_TZ_COMPLIANCE_ARGUMENTATION.md](IB_TZ_COMPLIANCE_ARGUMENTATION.md)*
