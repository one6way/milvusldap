# Keycloak + LDAP Authentication for Milvus (Offline Guide)

Этот документ описывает, как реализовать аутентификацию для Milvus в изолированном контуре, если у вас уже есть Keycloak с LDAP federation.

> Важно: Milvus обычно не интегрируется с LDAP напрямую.  
> Практический подход: **LDAP -> Keycloak -> Auth Gateway -> Milvus**.

---

## 1. Цель и модель

### Цель
- Централизованная аутентификация пользователей/сервисов через Keycloak.
- Использование LDAP/AD как источника identity.
- Защита Milvus endpoint без “прямого” LDAP в Milvus.

### Базовая модель
1. Пользователь аутентифицируется в Keycloak (через LDAP federation).
2. Клиент получает JWT access token.
3. Запрос к Milvus идет через gateway (Envoy/Nginx/OpenResty).
4. Gateway валидирует токен и проверяет группы/роли.
5. Только после этого трафик передается в Milvus.

---

## 2. Почему через gateway

- У Milvus нет “из коробки” LDAP-конфига как у некоторых корпоративных СУБД.
- Gateway позволяет:
  - проверять JWT (OIDC);
  - применять policy по группам;
  - вести аудит;
  - централизовать auth для нескольких сервисов.

---

## 3. Компоненты решения

## Обязательные
- Keycloak (в вашем контуре).
- LDAP/AD (через User Federation в Keycloak).
- Milvus (distributed/standalone).
- Auth Gateway (рекомендуется Envoy).

## Опциональные
- Sync job: Keycloak groups -> Milvus RBAC.
- SIEM/лог-пайплайн для security-аудита.

---

## 4. Варианты архитектуры

### Вариант A (быстрый старт): Gateway-only auth
- Права проверяются только на gateway.
- В Milvus остается внутренний доступ “за периметром”.
- Плюс: проще и быстрее внедрить.
- Минус: меньше granular-контроля внутри Milvus.

### Вариант B (рекомендуется для enterprise): Gateway + RBAC Sync
- Gateway контролирует вход.
- Периодический job синхронизирует LDAP/Keycloak группы в роли Milvus.
- Плюс: детальные права и прозрачный governance.
- Минус: добавляется компонент сопровождения.

---

## 5. Настройка Keycloak (под Milvus)

## 5.1 Realm и LDAP Federation
- Создайте/выделите realm для платформенных сервисов.
- Включите LDAP Federation:
  - bind user (service account),
  - корректный user search base,
  - group mapper.
- Проверьте, что пользователи и группы LDAP видны в Keycloak.

## 5.2 OIDC Client для gateway
- Client Protocol: `openid-connect`.
- Access Type: как правило `confidential` (service-to-service).
- Настройте:
  - `client_id`,
  - `client_secret`,
  - redirect/callback (если интерактивный поток),
  - audience mapper (если нужен).

## 5.3 Claims (очень важно)
- Добавьте mappers:
  - `groups` (LDAP group membership),
  - roles (realm/client roles).
- Убедитесь, что JWT реально содержит claims, по которым gateway будет принимать решение.

## 5.4 Token Policy
- Access token TTL (например 5-15 минут).
- Refresh token policy по требованиям ИБ.
- Учитывайте требования offline по синхронизации времени (NTP внутри контура).

---

## 6. Настройка Gateway (Envoy рекомендуем)

## 6.1 Почему Envoy
- Надежная поддержка gRPC-трафика.
- Гибкие auth-фильтры (`jwt_authn`, `ext_authz`).
- Хорошо ложится на Kubernetes/Istio-практики.

## 6.2 Что включить
- JWT validation:
  - issuer = ваш Keycloak realm issuer;
  - JWKS URI = endpoint ключей Keycloak (внутренний URL).
- Policy:
  - deny by default;
  - allow для нужных LDAP/Keycloak групп.
- gRPC proxy к Milvus `19530`.
- TLS termination или mTLS по вашей модели безопасности.

## 6.4 Тумблер в Helm values (уже добавлен)
В chart добавлен реальный toggle:

```yaml
auth:
  keycloak:
    enabled: false
```

- `enabled: false` (по умолчанию): Milvus работает в стандартном режиме, gateway не создается.
- `enabled: true`: поднимаются ресурсы `*-auth-gateway` (ConfigMap/Deployment/Service) с Envoy JWT-проверкой.
- Для клиентов используйте endpoint `milvus-auth-gateway:19530`.

Пример включения:

```bash
helm upgrade --install milvus ./chart/milvus -n milvus \
  -f values/values-kind-localpath.yaml \
  --set auth.keycloak.enabled=true \
  --set auth.keycloak.oidc.issuer="https://{{ KEYCLOAK_HOST }}/realms/{{ REALM }}" \
  --set auth.keycloak.oidc.audience="{{ MILVUS_CLIENT_ID }}" \
  --set auth.keycloak.oidc.jwksUri="https://{{ KEYCLOAK_HOST }}/realms/{{ REALM }}/protocol/openid-connect/certs" \
  --set auth.keycloak.oidc.jwksHost="{{ KEYCLOAK_HOST }}" \
  --set auth.keycloak.oidc.jwksPort=443
```

## 6.3 Логирование и аудит
- Логируйте:
  - subject (`sub`),
  - username/email (если допустимо),
  - groups/roles,
  - requested method/path,
  - allow/deny decision,
  - correlation/request id.

---

## 7. Милвус и роли

## 7.1 Базовый режим
- Клиенты ходят только через gateway endpoint.
- Прямой доступ к `svc/milvus` ограничивается NetworkPolicy/Service exposure.

## 7.2 RBAC внутри Milvus (опция)
- Для более строгого контроля:
  - создайте mapping таблицу `LDAP group -> Milvus role`;
  - синхронизируйте пользователей/роли в Milvus периодически.

Пример политики:
- `milvus-admin` -> полный доступ.
- `milvus-writer` -> insert/upsert/index management.
- `milvus-reader` -> query/search.

---

## 8. Offline подготовка артефактов

Нужно заранее подготовить:
- образы gateway, sidecar/ext-authz (если есть),
- chart/манифесты gateway,
- сертификаты внутреннего CA,
- значения для внутренних URL:
  - `{{ INTERNAL_KEYCLOAK_URL }}`
  - `{{ INTERNAL_REGISTRY }}`

Рекомендации:
- фиксируйте версии образов;
- не используйте `latest`;
- храните Helm values в Git с шаблонными плейсхолдерами.

---

## 9. Поэтапный rollout

1. Разверните gateway в тестовом namespace.
2. Настройте JWT валидацию к Keycloak.
3. Подключите Milvus backend.
4. Прогоните тесты:
   - валидный токен -> 200/успех;
   - просроченный/битый токен -> 401;
   - пользователь без группы -> 403.
5. Ограничьте прямой доступ к Milvus (только через gateway).
6. Переключите клиентов на gateway endpoint.

---

## 10. Проверки (acceptance checklist)

- [ ] JWT с нужными claims приходит от Keycloak.
- [ ] Gateway валидирует подпись и issuer/audience.
- [ ] Без токена Milvus недоступен.
- [ ] С неправильной группой доступ запрещен.
- [ ] С нужной группой доступны только разрешенные операции.
- [ ] Аудит-логи пишутся и индексируются.
- [ ] Внутренний сервисный доступ к Keycloak/JWKS работает в изолированном контуре.

---

## 11. Rollback план

- Откат DNS/endpoint клиентов обратно на внутренний service (временная мера).
- Отключение strict policy на gateway (maintenance mode).
- Сохранение логов auth-событий для последующего RCA.

---

## 12. Частые проблемы

### Проблема: `401 Unauthorized` при валидном логине
- Причина: неверный `issuer`/`audience`, не тот realm, JWKS URL недоступен.
- Решение: сверить OIDC metadata и gateway config.

### Проблема: токен валиден, но всегда `403`
- Причина: claim с группами не мапится или policy ожидает другой claim.
- Решение: проверить mappers в Keycloak и правила в gateway.

### Проблема: в тесте работает, в проде нет
- Причина: разный CA chain, не синхронизировано время (exp/nbf), сетевые policy.
- Решение: проверить cert trust, NTP, NetworkPolicy.

---

## 13. Рекомендация для вашего контура

Начните с **Keycloak + Envoy JWT auth перед Milvus** (вариант A),  
после стабилизации добавьте **RBAC Sync** (вариант B) для enterprise-уровня.

