# ТЗ ИБ vs архитектура LDAP-proxy (без патча исходников Milvus)

Документ для согласования с ИБ и командой, которая предлагает **форк Milvus** под требования учётных записей.

## Контекст

**Вариант коллег (ТЗ):** правки исходного кода Milvus — lockout, политика паролей, расширение `/user/info`, сборка кастомных образов.

**Наш вариант:** корпоративный **AD/LDAPS** + sidecar-сервисы:

```
AD/LDAPS ──► milvus-ldap-sync (CronJob) ──► Milvus users/roles (RBAC)
Клиент ──► milvus-ldap-gateway (Envoy) ──► milvus-ldap-auth ──► Milvus proxy
              │ LDAP bind доменным паролем
              └── подмена token на внутренний sync-пароль Milvus
```

Пользователь вводит **доменный логин/пароль**; пароль AD **не хранится** в Milvus.

---

## Соответствие пунктам ТЗ

### 1.1 Блокировка учётных записей (превышение неудачных входов)

| ТЗ | Форк Milvus | LDAP-proxy |
|----|-------------|------------|
| Счётчик failed attempts | В БД Milvus | **AD** (lockout policy / `lockoutThreshold`) |
| Блокировка | `account_locked` в Milvus | При LDAP bind → `49` / `775` → ldap-auth отклоняет; в AD учётка locked |
| Аудит | Логи Milvus | JSON-логи `ldap-auth-extauthz`: `user`, `result`, `reason`, `client_ip` |

**Вывод:** для доменных пользователей блокировка **централизована в AD** — это сильнее, чем локальный счётчик в Milvus.  
**Нюанс:** break-glass доступ напрямую на `milvus:19530` с sync-паролем обходит ldap-auth — в prod закрыть **NetworkPolicy** (только gateway → proxy).

**Опционально (без форка Milvus):** счётчик в Redis/SQLite в `ldap-auth` + алерт в SIEM, если нужен дублирующий контроль на периметре Milvus.

---

### 1.2 Политика паролей

| Подпункт ТЗ | Форк Milvus | LDAP-proxy |
|-------------|-------------|------------|
| Сложность (длина, регистр, цифры, спецсимволы) | Код в Milvus | **GPO AD** на доменных учётках |
| История 5–10 паролей | Хранение хэшей в Milvus | **AD password history** |
| Срок жизни ~90 дней, блок при истечении | Milvus internal | **AD max password age**; bind с просроченным паролем → отказ LDAP |

**Вывод:** требования к **доменному** паролю закрывает **Active Directory**, без дублирования в Milvus.

**Внутренний sync-пароль** Milvus (`MILVUS_USER_PASSWORD` в sync) — сервисный, не вводится пользователем:

- ротация по регламенту (Secret + re-sync);
- длина/энтропия по внутреннему стандарту;
- не попадает под ТЗ «пароль пользователя», т.к. пользователь его не знает.

---

### 1.3 Расширение API `/user/info`

ТЗ требует поля:

| Поле | Источник при LDAP-proxy | Комментарий |
|------|-------------------------|-------------|
| `last_login` | AD `lastLogon` / `lastLogonTimestamp` | Запрос ldap-auth или отдельный read-only LDAP |
| `password_expiry_date` | AD `pwdLastSet` + `maxPwdAge` | Расчёт на стороне proxy |
| `account_locked` | AD `lockoutTime` / `userAccountControl` | LDAP-атрибуты |
| `lock_reason` | ldap-auth / AD | `"exceeded login attempts"`, `"password expired"`, `"disabled"` |
| `failed_login_attempts` | AD / опционально Redis в ldap-auth | AD — при наличии прав на чтение |
| `is_active` | AD `userAccountControl` ACCOUNTDISABLE | Sync может деактивировать Milvus user |

**Gap:** нативный Milvus `/user/info` **не отдаёт** эти поля — реализовано в **`milvus-ldap-auth`** на том же пути через gateway.

**Реализовано (без форка Milvus):**

1. `GET /api/v1/user/info` на `milvus-ldap-auth`, маршрут через `milvus-ldap-gateway` (см. `IB_TZ_COMPLIANCE_ARGUMENTATION.md`).
2. Attu/SDK: доменный пароль через gateway; `/user/info` — для ИБ/мониторинга.
3. Прямой вызов: `ldap-auth-extauthz:8080/api/v1/user/info`.

~~4. Минимальный патч Milvus~~ — **не используется** (решение ИБ: эквивалентная реализация на периметре).

---

### 2. Обновления и сборка (из ТЗ)

| ТЗ | Наш путь |
|----|----------|
| Патч исходников Milvus | **Vanilla** `milvus-nonroot:2.5.0` |
| Docker-образы | `milvus-ldap-sync-nonroot`, `milvus-ldap-auth-nonroot`, `envoy-nonroot` |
| Helm | Параметры sync/auth в values + `securityContext` UID/GID **65000** |
| Аудит/логирование | Envoy access log + structured JSON в ldap-auth/sync |

Сборка и выгрузка в изолированном контуре:

```bash
cd milfus-main
./scripts/57-build-ldap-images-nonroot.sh
# artifacts/images/milvus-ldap-sync-nonroot_2.5.0.tar.gz
# artifacts/images/milvus-ldap-auth-nonroot_2.5.0.tar.gz
```

---

## Почему LDAP-proxy предпочтительнее форка Milvus

1. **Единый источник истины** — AD уже проходит ИБ-аудит (GPO, lockout, история паролей).
2. **Меньше техдолга** — не тащим форк Milvus на каждый релиз 2.5.x → 2.6.x.
3. **Разделение ответственности** — ИБ домена = AD; доступ к векторам = Milvus RBAC.
4. **Offline** — два небольших Python-образа + Envoy, без пересборки C++ Milvus.

## Риски и митигации

| Риск | Митигация |
|------|-----------|
| Прямой доступ к Milvus минуя gateway | NetworkPolicy, только `milvus-ldap-gateway` → `milvus-proxy` |
| ТЗ требует именно Milvus `/user/info` | Sidecar-прокси или точечный патч только REST proxy (не core) |
| Sync-пароль скомпрометирован | Ротация Secret, audit Milvus connections, отключить direct access |
| AD недоступен | Readiness ldap-auth; cached deny; алерт |

## Что согласовать с ИБ (чеклист)

- [ ] Доменный пароль = единственный пользовательский пароль (sync-пароль internal).
- [ ] Блокировка и политика паролей — **политики AD**, ссылка на GPO в приложении.
- [ ] `/user/info` — отдельный endpoint ldap-auth **или** формальное исключение для Attu/SDK.
- [ ] Break-glass: кто и как ходит на `milvus:19530` напрямую (роль admin, VPN, audit).
- [ ] Логи ldap-auth/sync в SIEM (поля: timestamp, user, action, result, source_ip).

## Связанные документы

- **[IB_TZ_COMPLIANCE_ARGUMENTATION.md](IB_TZ_COMPLIANCE_ARGUMENTATION.md)** — полное обоснование для приёмки ИБ
- [LDAP_DOMAIN_LOGIN_ARCHITECTURE.md](LDAP_DOMAIN_LOGIN_ARCHITECTURE.md)
- [LDAPS_RBAC_SYNC_SETUP.md](LDAPS_RBAC_SYNC_SETUP.md)
- [CORP_LDAP_DEPLOYMENT_CHECKLIST.md](CORP_LDAP_DEPLOYMENT_CHECKLIST.md)
