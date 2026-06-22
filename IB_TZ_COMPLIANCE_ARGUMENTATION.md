# Обоснование соответствия ТЗ ИБ для Milvus (LDAP-proxy, без изменения исходного кода Milvus)

**Версия:** 1.0  
**Дата:** 2026-06-22  
**Аудитория:** служба информационной безопасности, архитекторы, владелец продукта  
**Статус:** для согласования приёмки

---

## 1. Резюме

Требования ТЗ ИБ к подсистеме учётных записей Milvus **выполняются полностью** при следующих условиях:

1. **Единственный пользовательский пароль** — доменный пароль Active Directory (AD). Пользователь не создаёт и не меняет пароль в Milvus.
2. **Политика паролей, блокировка, история, срок действия** — обеспечиваются **корпоративными GPO AD** (централизованный контур, уже прошедший ИБ-аудит).
3. **API `/api/v1/user/info`** с полями из ТЗ реализован сервисом **`milvus-ldap-auth`** и доступен через **`milvus-ldap-gateway`** по тому же пути — без патча C++/Go-кода Milvus.
4. **Аудит входов** — структурированные JSON-логи `milvus-ldap-auth` и access-log Envoy, выгрузка в SIEM.
5. **Сетевая изоляция** — NetworkPolicy: пользовательский трафик к Milvus proxy только через gateway.

**Единственное архитектурное отличие от ТЗ:** не форкается upstream Milvus; функции ИБ вынесены в контролируемые sidecar-сервисы и AD. Это **не ослабление**, а перенос ответственности на уже сертифицированный корпоративный IdM.

---

## 2. Нормативная привязка к пунктам ТЗ

### 2.1. П. 1.1 — Блокировка учётных записей (превышение неудачных попыток входа)

| Требование ТЗ | Реализация | Доказательство |
|---------------|------------|----------------|
| Механизм блокировки при превышении лимита неудачных входов | **AD Account Lockout Policy** (`lockoutThreshold`, `lockoutDuration`) | Атрибуты `lockoutTime`, `badPwdCount`; отказ LDAP bind |
| Учётная запись заблокирована | Поле `account_locked: true` в `/api/v1/user/info` | Чтение AD + отказ `milvus-ldap-auth` до успешного bind |
| Причина блокировки | Поле `lock_reason: "exceeded login attempts"` | Маппинг `lockoutTime` / `badPwdCount` ≥ `lockoutThreshold` |
| Счётчик неудачных попыток | Поле `failed_login_attempts` | AD `badPwdCount` + дублирование на периметре Milvus (`/tmp/ldap_auth_state.json`) |
| Аудит | JSON-события `login_denied` / `login_granted` | `kubectl logs deploy/ldap-auth-extauthz` |

**Аргумент для ИБ:** блокировка в AD **сильнее** локального счётчика в Milvus:

- единая политика для всех систем организации;
- администрирование через GPO, а не через кастомный форк БД;
- разблокировка — стандартная процедура AD (не «ручной SQL в Milvus»).

**Периметр Milvus:** при каждом отказе `milvus-ldap-auth` фиксирует попытку в audit-log и локальном state (для SIEM-корреляции, если AD-атрибут недоступен в lab).

---

### 2.2. П. 1.2 — Политика паролей

| Подпункт ТЗ | Реализация | Доказательство |
|-------------|------------|----------------|
| Сложность (длина, регистр, цифры, спецсимволы) | **Default Domain Policy / Fine-Grained PSO** | Смена пароля только в AD; Milvus пароль пользователя не принимает |
| История 5–10 паролей | **AD Password History** | Хэши в AD (не в Milvus); повторное использование отклоняется при смене в AD |
| Срок жизни ~90 дней | **AD `maxPwdAge`** | Поле `password_expiry_date` = `pwdLastSet` + \|`maxPwdAge\|` |
| Блокировка при истечении срока | Отказ LDAP bind + `account_locked` + `lock_reason: "password expired"` | Проверка до/после bind в `milvus-ldap-auth` |

**Аргумент для ИБ:** требования ТЗ к **пользовательскому** паролю по смыслу относятся к учётной записи субъекта доступа. В нашей схеме субъект — **доменная УЗ AD**. Дублирование политики в Milvus создало бы:

- два независимых пароля (нарушение принципа единого IdM);
- рассинхрон сроков и истории;
- дополнительную поверхность атаки (хранение хэшей в Milvus).

**Внутренний sync-пароль Milvus** (`MILVUS_SYNC_DEFAULT_PASSWORD`):

- не известен пользователю;
- не вводится в UI;
- ротируется по регламенту K8s Secret;
- соответствует требованию «≥6 символов» Milvus API;
- **не является предметом п. 1.2 ТЗ** (не пользовательский пароль).

---

### 2.3. П. 1.3 — Расширение API `/user/info`

ТЗ требует поля в ответе метода `/user/info`:

| Поле ТЗ | Источник | Пример |
|---------|----------|--------|
| `last_login` | AD `lastLogonTimestamp` / `lastLogon`; fallback — успешный вход через gateway | `"2026-06-22T18:30:00+00:00"` |
| `password_expiry_date` | AD `pwdLastSet` + domain `maxPwdAge` | `"2026-09-20T00:00:00+00:00"` |
| `account_locked` | AD `lockoutTime`, `userAccountControl`, expiry | `true` / `false` |
| `lock_reason` | Детализация: `exceeded login attempts`, `password expired`, `account disabled` | строка |
| `failed_login_attempts` | AD `badPwdCount` + периметр | `3` |
| `is_active` | AD `userAccountControl` ACCOUNTDISABLE | `true` / `false` |

**Эндпоинт (контракт ТЗ):**

```http
GET http://milvus-ldap-gateway:19530/api/v1/user/info
Authorization: Basic <base64(sAMAccountName:domain_password)>
```

**Ответ 200:**

```json
{
  "username": "ivanov",
  "milvus_username": "ivanov",
  "last_login": "2026-06-22T15:04:05+00:00",
  "password_expiry_date": "2026-09-20T00:00:00+00:00",
  "account_locked": false,
  "lock_reason": "",
  "failed_login_attempts": 0,
  "is_active": true
}
```

**Маршрутизация:** Envoy `milvus-ldap-gateway` направляет `/api/v1/user/info` и `/user/info` на `milvus-ldap-auth` (см. `manifests/ldap-auth/envoy-milvus-gateway.yaml`). Путь совпадает с ожиданием ТЗ; реализация — в контролируемом Python-сервисе, а не в форке Milvus core.

**Аргумент для ИБ:** ТЗ описывает **поведение API для потребителя** (поля ответа), а не обязательное место внедрения (внутри процесса `milvus`). Функциональная эквивалентность достигнута: тот же URL через gateway, тот же набор полей, аутентификация доменным паролем.

Прямой вызов внутри кластера (диагностика):

```http
GET http://ldap-auth-extauthz:8080/api/v1/user/info
```

---

### 2.4. П. 2 — Обновления и сборка

| Требование ТЗ | Реализация |
|---------------|------------|
| Изменение кода для ИБ, аудита, аутентификации | `scripts/ldap_auth_extauthz.py`, `scripts/milvus_ldap_sync.py` |
| Docker-образы | `milvus-ldap-auth-nonroot:2.5.0`, `milvus-ldap-sync-nonroot:2.5.0` (UID/GID **65000**) |
| Helm / K8s | CronJob sync, Deployment ldap-auth, Deployment gateway, NetworkPolicy |
| Milvus core | **Без изменений** — `milvus-nonroot:2.5.0` upstream |

Сборка для изолированного контура:

```bash
./scripts/57-build-ldap-images-nonroot.sh
```

---

## 3. Почему отказ от форка Milvus не является компромиссом

| Критерий | Форк Milvus | LDAP-proxy + AD |
|----------|-------------|-----------------|
| Единый IdM | Нет (второй пароль/политика) | **Да** |
| Соответствие корп. GPO | Локальная копия правил | **Нативно AD** |
| Сопровождение релизов Milvus | Высокий риск merge | **Низкий** (vanilla Milvus) |
| Атака на хранилище паролей Milvus | Релевантно | **Не релевантно** (пользовательский пароль не хранится) |
| Аудит ИБ | Только логи Milvus | AD + gateway + ldap-auth (SIEM) |
| Сертификация | Повторная оценка форка | AD уже в контуре ИБ |

Форк оправдан только если ИБ **формально** требует, чтобы код полей `/user/info` исполнялся внутри бинарника `milvus`. Текущая реализация закрывает **функциональные** требования ТЗ через gateway — стандартная практика Zero Trust (policy enforcement point на периметре).

---

## 4. Сетевая модель и break-glass

**NetworkPolicy** `milvus-proxy-ingress-from-gateway-only`:

- Ingress на Milvus proxy `:19530` — от `milvus-ldap-gateway`, sync CronJob, ldap-auth;
- обход gateway с пользовательским sync-паролем с произвольного pod **закрыт**.

**Break-glass** (аварийный доступ `root` / admin):

- только из namespace `milvus` или через port-forward под аудитом;
- оформляется регламентом ИБ (кто, когда, ticket);
- не используется для повседневной работы Attu/SDK.

---

## 5. Аудит и мониторинг (для SIEM)

События `milvus-ldap-auth` (JSON, одна строка = одно событие):

| event | Когда |
|-------|-------|
| `login_granted` | Успешный LDAP bind, доступ к Milvus |
| `login_denied` | Неверный пароль, блокировка, неактивная УЗ |
| `user_info_ok` | Успешный запрос `/api/v1/user/info` |
| `ext_authz_denied` | Отказ Envoy ext_authz |

Обязательные поля: `ts`, `username`, `reason`, `failed_login_attempts`, `client_result`.

Envoy: access log gateway (источник IP, upstream, код ответа).

Sync CronJob: логи создания/обновления пользователей Milvus; неактивные AD-УЗ **не синхронизируются** (`userAccountControl` DISABLE, `nsAccountLock`).

---

## 6. Чеклист приёмки ИБ

- [ ] Подтверждено: пользовательский пароль = только AD.
- [ ] Приложена ссылка на GPO: lockout, password history, max age, complexity.
- [ ] Проверен отказ входа заблокированной УЗ через `milvus-ldap-gateway`.
- [ ] Проверен `GET /api/v1/user/info` — все 6 полей ТЗ присутствуют.
- [ ] Проверена блокировка по истечению пароля (`lock_reason: password expired`).
- [ ] Логи `login_denied` / `login_granted` поступают в SIEM.
- [ ] NetworkPolicy применена в prod (`kubectl apply -f manifests/ldap-auth/networkpolicy-milvus-ldap.yaml`).
- [ ] Break-glass задокументирован в регламенте эксплуатации.
- [ ] Образы nonroot 65000 загружены из `artifacts/images/*.tar.gz`.

### Команды проверки (prod / lab)

```bash
# Статус учётки (все поля ТЗ)
kubectl -n milvus run userinfo-test --rm -i --restart=Never \
  --image=curlimages/curl:8.5.0 --command -- \
  curl -sS -u 'USER:DOMAIN_PASSWORD' \
  http://milvus-ldap-gateway:19530/api/v1/user/info | jq .

# Отказ при неверном пароле
kubectl -n milvus logs deploy/ldap-auth-extauthz --tail=20 | grep login_denied

# NetworkPolicy
kubectl -n milvus get networkpolicy milvus-proxy-ingress-from-gateway-only
```

---

## 7. Распределение ответственности

| Зона | Владелец | Что контролирует |
|------|----------|------------------|
| Доменные УЗ, GPO, lockout, password policy | **AD / ИБ домена** | П. 1.1, 1.2 ТЗ |
| API `/user/info`, ext_authz, audit perimeter | **milvus-ldap-auth** | П. 1.3, аудит входа |
| RBAC Milvus (роли, привилегии) | **milvus-ldap-sync** + Milvus RBAC | Доступ к коллекциям |
| Транспорт, TLS, маршрутизация | **Envoy gateway** | Единая точка входа |
| Данные векторов | **Milvus** (без форка) | Авторизация по token после gateway |

---

## 8. Заключение

Архитектура **LDAP-proxy + Active Directory** обеспечивает **полное функциональное соответствие** ТЗ ИБ по блокировке, политике паролей и API `/user/info` **без изменения исходного кода Milvus**.

Отличие от буквальной формулировки ТЗ («модификация исходного кода Milvus») — **целенаправленное архитектурное решение**: перенос контролей ИБ на корпоративный IdM и периметр, что соответствует лучшим практикам и снижает операционный риск в изолированном контуре.

**Рекомендация:** принять решение как **эквивалентную реализацию** требований ТЗ с фиксацией в протоколе ИБ (ссылка на настоящий документ).

---

## Связанные материалы

- [LDAP_DOMAIN_LOGIN_ARCHITECTURE.md](LDAP_DOMAIN_LOGIN_ARCHITECTURE.md)
- [IS_REQUIREMENTS_LDAP_PROXY.md](IS_REQUIREMENTS_LDAP_PROXY.md)
- [CORP_LDAP_DEPLOYMENT_CHECKLIST.md](CORP_LDAP_DEPLOYMENT_CHECKLIST.md)
