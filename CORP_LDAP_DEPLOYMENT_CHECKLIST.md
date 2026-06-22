# Корпоративный LDAP: чеклист деплоя (prod) и результаты lab

Единая точка входа. **OpenLDAP в prod не нужен** — только для lab на kind.

| Документ | Содержание |
|----------|------------|
| [LDAPS_RBAC_SYNC_SETUP.md](LDAPS_RBAC_SYNC_SETUP.md) | Sync AD → Milvus RBAC, Attu без доменного пароля |
| [LDAP_DOMAIN_LOGIN_ARCHITECTURE.md](LDAP_DOMAIN_LOGIN_ARCHITECTURE.md) | Доменный пароль через Envoy + ldap-auth |
| [IS_REQUIREMENTS_LDAP_PROXY.md](IS_REQUIREMENTS_LDAP_PROXY.md) | ТЗ ИБ vs LDAP-proxy (краткая матрица) |
| **[IB_TZ_COMPLIANCE_ARGUMENTATION.md](IB_TZ_COMPLIANCE_ARGUMENTATION.md)** | **Обоснование для ИБ (приёмка, без форка Milvus)** |
| **[LDAP_MILVUS_TEST_PROTOCOL.md](LDAP_MILVUS_TEST_PROTOCOL.md)** | **Протокол тестирования (lab, логи, артефакты)** |
| Этот файл | Lab-тесты, команды, образы, prod vs lab |

---

## 1. Lab vs prod

| | **Lab (kind `milvus-k121`)** | **Prod (работа)** |
|--|------------------------------|-------------------|
| Каталог | OpenLDAP pod `openldap-lab` | **Корпоративный AD/LDAPS** |
| Нужен ли OpenLDAP | Да, для отладки | **Нет** |
| Выгрузка групп в OpenLDAP | Не нужна | — |
| Подключение | `ldap://openldap-lab:389` | `ldaps://{{ LDAP_HOST }}:636` + CA |
| Service account | `cn=admin,dc=lab,dc=local` | `CN=milvus-sync,OU=...` от AD |

Sync и ldap-auth **напрямую читают** корпоративный каталог — реплика в OpenLDAP не требуется.

---

## 2. Какие образы нужны (не только Milvus + Attu + Envoy)

| Образ | Обязателен | Назначение |
|-------|------------|------------|
| `milvus-nonroot:2.5.0` | да | Milvus |
| `attu-nonroot:2.5.10` | да | Attu UI |
| `envoy-nonroot:v1.31.2` | да | `milvus-ldap-gateway` (доменный пароль) |
| **`milvus-ldap-sync-nonroot:2.5.0`** (alias `milvus-ldap-sync:2.5.0`) | **да** | CronJob: AD группы → Milvus users/roles |
| **`milvus-ldap-auth-nonroot:2.5.0`** (alias `milvus-ldap-auth:2.5.0`) | **да** | LDAP bind + подмена token для Milvus |
| `osixia/openldap` | **только lab** | Имитация AD |
| Keycloak | нет (вариант A позже) | SSO |

**Итого в prod добавляются 2 образа:** `milvus-ldap-sync-nonroot` и `milvus-ldap-auth-nonroot` (UID/GID **65000**).  
Штатный Envoy JWT-gateway из чарта (`auth.keycloak.enabled`) **не используется** — отдельный Deployment `milvus-ldap-gateway`.

Сборка и `tar.gz` для registry / изолированный контур:

```bash
./scripts/57-build-ldap-images-nonroot.sh
# → artifacts/images/milvus-ldap-sync-nonroot_2.5.0.tar.gz
# → artifacts/images/milvus-ldap-auth-nonroot_2.5.0.tar.gz
```

---

## 3. Тесты на локалке (проведены)

**Кластер:** kind `milvus-k121`, namespace `milvus`, дата: 2026-06-22.

### 3.1 LDAP RBAC sync

```text
LDAP -> Milvus sync start
ldap users fetched: 2
create user 'milvus655' roles=['reader']
LDAP -> Milvus sync OK
```

Пользователи: `testuser`, `milvus655` с ролью `reader`.

### 3.2 LDAP domain-login gateway

| Тест | Результат |
|------|-----------|
| `milvus-ldap-gateway` + `testuser` / `Testldap1` (LDAP) | OK `['default']` |
| `milvus-ldap-gateway` + `milvus655` / `Ab12345678` | OK |
| `milvus-ldap-gateway` + неверный пароль | Отклонено |
| `milvus:19530` + `testuser` / `AttuTest1` (прямой путь) | OK (break-glass / старый режим) |
| Attu + `milvus-ldap-gateway:19530` + LDAP-пароль | OK (вручную) |

### 3.3 Lab-учётки

| User | LDAP password | Milvus internal (скрыт) |
|------|---------------|-------------------------|
| testuser | Testldap1 | AttuTest1 |
| milvus655 | Ab12345678 | AttuTest1 |

---

## 4. Команды lab (повторить локально)

```bash
cd milfus-main

# OpenLDAP + sync (если с нуля)
./scripts/47-setup-ldap-lab.sh

# Gateway доменного пароля
./scripts/49-setup-ldap-auth-gateway-lab.sh

# Attu
kubectl port-forward -n milvus svc/attu 3000:3000
# http://127.0.0.1:3000
#   Milvus: milvus-ldap-gateway:19530
#   User:   testuser
#   Pass:   Testldap1
```

Ручной smoke:

```bash
kubectl -n milvus run gw-test --rm -i --restart=Never \
  --image=milvus-ldap-sync:2.5.0-lab --image-pull-policy=IfNotPresent \
  --command -- python - <<'PY'
from pymilvus import MilvusClient
c = MilvusClient(uri="http://milvus-ldap-gateway:19530", token="testuser:Testldap1")
print(c.list_databases())
PY
```

---

## 5. Команды prod (корпоративный LDAPS)

### 5.1 Подготовка (prep → registry / изолированный контур)

```bash
cd milfus-main

./scripts/57-build-ldap-images-nonroot.sh
# или вручную + push в {{ INTERNAL_REGISTRY }}:
#   milvus-ldap-sync-nonroot:2.5.0 / milvus-ldap-auth-nonroot:2.5.0

docker build -t envoy-nonroot:v1.31.2 -f images/envoy-nonroot/Dockerfile images/envoy-nonroot

# изолированный контур на целевом контуре:
# gunzip -c milvus-ldap-sync-nonroot_2.5.0.tar.gz | docker load
# gunzip -c milvus-ldap-auth-nonroot_2.5.0.tar.gz | docker load
```

### 5.2 Файлы конфигурации

```bash
cp values/values-ldap-sync-milvus-k121.yaml values/values-ldap-sync-prod.yaml
cp values/values-ldap-auth-gateway.example.yaml values/values-ldap-auth-gateway-prod.yaml
cp manifests/ldap-sync/ldap-sync-secret.example.yaml manifests/ldap-sync/ldap-sync-secret.yaml
cp manifests/ldap-sync/ldap-sync-ca.example.yaml manifests/ldap-sync/ldap-sync-ca.yaml
cp manifests/ldap-auth/ldap-auth-secret.example.yaml manifests/ldap-auth/ldap-auth-secret.yaml
cp manifests/ldap-auth/ldap-auth-ca.example.yaml manifests/ldap-auth/ldap-auth-ca.yaml
```

Заполнить в **обоих** values и secrets:

```yaml
ldap:
  uri: "ldaps://ldap.corp.local:636"
  bindDn: "CN=milvus-sync,OU=Service Accounts,DC=corp,DC=local"
  userBase: "OU=Users,DC=corp,DC=local"
  groupBase: "OU=Groups,DC=corp,DC=local"
  usernameAttr: sAMAccountName
  usernameNormalize: sanitize

groupRoleMap:
  g-milvus-admin: admin
  g-milvus-read: reader
  g-milvus-write: writer
```

Secret (одинаковый `MILVUS_SYNC_DEFAULT_PASSWORD` в sync и auth):

```yaml
LDAP_BIND_PASSWORD: "<service account>"
MILVUS_ROOT_PASSWORD: "<milvus root>"
MILVUS_SYNC_DEFAULT_PASSWORD: "<внутренний, min 6 символов>"
```

CA: PEM корпоративного CA в `ldap-sync-ca.yaml` и `ldap-auth-ca.yaml`.

### 5.3 Установка в K8s

```bash
export NAMESPACE=milvus

# 1) RBAC sync
VALUES_FILE=values/values-ldap-sync-prod.yaml \
SECRET_FILE=manifests/ldap-sync/ldap-sync-secret.yaml \
CA_FILE=manifests/ldap-sync/ldap-sync-ca.yaml \
LDAP_AUTH_IMAGE={{ INTERNAL_REGISTRY }}/milvus-ldap-sync-nonroot:2.5.0 \
./scripts/46-install-ldap-sync.sh

kubectl -n milvus create job milvus-ldap-sync-manual --from=cronjob/milvus-ldap-sync
kubectl -n milvus logs job/milvus-ldap-sync-manual

# 2) Domain-login gateway
VALUES_FILE=values/values-ldap-auth-gateway-prod.yaml \
SECRET_FILE=manifests/ldap-auth/ldap-auth-secret.yaml \
CA_FILE=manifests/ldap-auth/ldap-auth-ca.yaml \
LDAP_AUTH_IMAGE={{ INTERNAL_REGISTRY }}/milvus-ldap-auth-nonroot:2.5.0 \
ENVOY_IMAGE={{ INTERNAL_REGISTRY }}/envoy-nonroot:v1.31.2 \
./scripts/48-install-ldap-auth-gateway.sh
```

### 5.4 Проверка prod

```bash
kubectl -n milvus get pods -l 'app.kubernetes.io/name in (milvus-ldap-sync,milvus-ldap-gateway,ldap-auth-extauthz)'

kubectl -n milvus run corp-ldap-test --rm -i --restart=Never \
  --image={{ INTERNAL_REGISTRY }}/milvus-ldap-sync-nonroot:2.5.0 \
  --command -- python - <<'PY'
from pymilvus import MilvusClient
c = MilvusClient(uri="http://milvus-ldap-gateway:19530", token="YOUR_SAM:YOUR_DOMAIN_PASSWORD")
print(c.list_databases())
PY
```

### 5.5 Attu (prod)

| Поле | Значение |
|------|----------|
| Milvus address | `milvus-ldap-gateway:19530` |
| Username | `sAMAccountName` |
| Password | **доменный пароль** |

### 5.6 API `/api/v1/user/info` (ТЗ ИБ п. 1.3)

```bash
kubectl -n milvus run userinfo-test --rm -i --restart=Never \
  --image=curlimages/curl:8.5.0 --command -- \
  curl -sS -u 'sAMAccountName:DOMAIN_PASSWORD' \
  http://milvus-ldap-gateway:19530/api/v1/user/info
```

Ожидаемые поля: `last_login`, `password_expiry_date`, `account_locked`, `lock_reason`, `failed_login_attempts`, `is_active`.

Обоснование для ИБ: [IB_TZ_COMPLIANCE_ARGUMENTATION.md](IB_TZ_COMPLIANCE_ARGUMENTATION.md).

---

## 6. Milvus Helm (без изменений MQ)

```yaml
extraConfigFiles:
  user.yaml: |
    common:
      security:
        authorizationEnabled: true
        defaultRootPassword: "{{ MILVUS_ROOT_PASSWORD }}"
        superUsers: root,admin

auth:
  keycloak:
    enabled: false   # JWT Envoy из чарта — НЕ наш LDAP gateway
```

---

## 7. Что запросить у AD-админов

- [ ] LDAPS endpoint `:636`
- [ ] CA certificate (PEM)
- [ ] Service account + пароль (read users/groups)
- [ ] `userBase`, `groupBase`
- [ ] Имена групп для `groupRoleMap`
- [ ] Сетевой доступ из namespace `milvus` до LDAPS

---

## 8. Скрипты

| Скрипт | Назначение |
|--------|------------|
| `scripts/57-build-ldap-images-nonroot.sh` | Сборка sync/auth nonroot + tar.gz |
| `scripts/46-install-ldap-sync.sh` | CronJob sync |
| `scripts/47-setup-ldap-lab.sh` | Lab: OpenLDAP + sync |
| `scripts/48-install-ldap-auth-gateway.sh` | Gateway prod/lab |
| `scripts/49-setup-ldap-auth-gateway-lab.sh` | Lab: gateway + smoke |

---

*OpenLDAP — только lab. Prod = корпоративный LDAPS напрямую.*
