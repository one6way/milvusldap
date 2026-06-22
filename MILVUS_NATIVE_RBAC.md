# Встроенный RBAC Milvus (user/password) в Kubernetes

Кратко: это **не** Kubernetes RBAC (ServiceAccount/Role), а **встроенная** авторизация Milvus (`common.security` в `milvus.yaml`), учётные записи хранятся в метаданных (etcd).

## Что включено в профиле `values-kind-localpath.yaml`

В `extraConfigFiles.user.yaml` задаётся:

- `common.security.authorizationEnabled: true` — обязательные логин/пароль для клиентов.
- `common.security.defaultRootPassword` — начальный пароль пользователя **`root`** (суперпользователь по умолчанию).
- `common.security.superUsers` — список имён с особыми правилами (например обход части проверок при смене пароля); в профиле указаны **`root`** и **`admin`**.

Учётная запись **`admin`** в метаданных **не появляется сама** — её создаёт скрипт bootstrap (см. ниже).

## Учётные данные (целевой сценарий)

| Пользователь | Пароль | Примечание |
|--------------|--------|------------|
| `root` | `user` | Задаётся `defaultRootPassword` в values (смените в проде). |
| `admin` | `user` | Создаётся скриптом `scripts/45-bootstrap-milvus-native-rbac.sh`. |

### Ограничение длины пароля Milvus

Для вызова **`create_user`** сервер Milvus обычно требует пароль **не короче 6 символов**. Строка **`user`** (4 символа) может быть **отклонена** при создании пользователя `admin`.

Скрипт bootstrap сначала пытается пароль из переменной окружения `MILVUS_ADMIN_PASSWORD` (по умолчанию `user`); при ошибке валидации **один раз** пробует пароль **`user00`** (6 символов) и пишет явное сообщение в лог. При необходимости задайте сразу допустимый пароль:

```bash
export MILVUS_ADMIN_PASSWORD='user1234'
./scripts/45-bootstrap-milvus-native-rbac.sh
```

## Порядок внедрения

1. Обновить релиз Helm (подтянуть изменения `values-kind-localpath.yaml` с `extraConfigFiles`).
2. Дождаться перезапуска подов Milvus и готовности proxy.
3. Выполнить (из каталога `milvus-airgap`, при необходимости выставить `NAMESPACE`):
   ```bash
   chmod +x scripts/45-bootstrap-milvus-native-rbac.sh
   ./scripts/45-bootstrap-milvus-native-rbac.sh
   ```

Скрипт идемпотентен: повторный запуск не ломает уже созданного `admin`.

## Подключение клиента (пример)

```python
from pymilvus import connections
connections.connect(
    alias="default",
    host="127.0.0.1",
    port="19530",
    user="admin",
    password="user",  # или user00 / ваш MILVUS_ADMIN_PASSWORD
)
```

С включённым RBAC без учётных данных подключение к gRPC будет отклонено.

## Прод и air-gap

- Не храните пароли в открытом виде в Git: вынесите в **Secret** и подставляйте через CI/CD или `helm --set-file` / внешние values.
- Скрипт bootstrap использует образ `python:3.11-slim` и `pip install pymilvus` — на изолированном контуре нужен **внутренний registry** и заранее собранный образ с установленным `pymilvus`, либо offline wheel.

## См. также

- [Authenticate User Access](https://milvus.io/docs/v2.5.x/authenticate.md) (официальная документация Milvus 2.5.x).
- [MILVUS_POST_RESTART_RECOVERY.md](./MILVUS_POST_RESTART_RECOVERY.md) — если после рестарта кластера поды не поднимаются.
