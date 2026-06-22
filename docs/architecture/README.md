# Архитектурная документация (Milvus + LDAP)

> **Главная точка входа:** [ARCHITECTURE_LDAP_AD.md](../ARCHITECTURE_LDAP_AD.md) — схемы LDAP/AD без Keycloak в корне репозитория.

Подробные схемы для согласования с ИБ, архитекторами и эксплуатацией. Диаграммы в **Mermaid** — на GitHub отображаются при просмотре `.md`.

| Документ | Содержание |
|----------|------------|
| [COMPONENT_INTERACTION.md](COMPONENT_INTERACTION.md) | **Взаимодействие компонентов**: клиенты, K8s, AD, Milvus distributed, LDAP sync/auth, потоки данных |
| [AUTHORIZATION.md](AUTHORIZATION.md) | **Авторизация**: доменный пароль, token rewrite, RBAC sync, `/api/v1/user/info`, NetworkPolicy |

## Связанные материалы

| Документ | Назначение |
|----------|------------|
| [LDAP_DOMAIN_LOGIN_ARCHITECTURE.md](../../LDAP_DOMAIN_LOGIN_ARCHITECTURE.md) | Краткая схема и пошаговая установка gateway |
| [INFRASTRUCTURE_ARCHITECTURE.md](../../INFRASTRUCTURE_ARCHITECTURE.md) | Ядро Milvus, Pulsar, etcd, MinIO |
| [IB_TZ_COMPLIANCE_ARGUMENTATION.md](../../IB_TZ_COMPLIANCE_ARGUMENTATION.md) | Обоснование соответствия ТЗ ИБ |
| [LDAPS_RBAC_SYNC_SETUP.md](../../LDAPS_RBAC_SYNC_SETUP.md) | Настройка CronJob sync |

## Выбранный контур (prod)

**Вариант B — LDAP + Envoy**, без Keycloak и без форка Milvus (единственный рабочий контур в этом репозитории):

```
AD/LDAPS → ldap-sync (CronJob) → Milvus users/roles
Клиент → milvus-ldap-gateway (Envoy) → ldap-auth (ext_authz) → milvus-proxy
```
