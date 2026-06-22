# Вынос в приватный Git (только Milvus / K8s + доки стека)

Репозиторий задуман как **самостоятельный каталог** `milfus-main`: чарты, `values/`, `scripts/`, `images/*/Dockerfile`, документация, `tests/`, `kind/`, `chart/`, `manifests/` — **без** `kub_help` и прочих проектов.

## Что не попадает в Git (образы)

- Каталог **`artifacts/`** целиком (tar образов и прочее prep-стенда, часто гигабайты) — в репо только **Dockerfile** в `images/` (см. `images/README.md`).
- **`milvus-delivery-bundle*.tar.gz`** в корне — локальные сборки, не коммитить.

Helm-пакеты **`.tgz`** в `chart/` и при необходимости `artifacts/charts/` **можно** хранить (это не Docker-образы); при желании ужесточить — добавь правило в `.gitignore`.

## K8s и «standalone на сервере»

- **Kubernetes:** основной сценарий — Helm `chart/milvus`, `values/*`, скрипты `scripts/*.sh`.
- **Standalone на ВМ:** ориентир по структуре и шагам — `FIRST_TIME_INSTALL_K8S_AND_VM.md` (раздел про `standalone/`). Каталог `standalone/` можно завести позже (compose + скрипты) и добавить в тот же репозиторий — он остаётся в рамках Milvus.

## Первичная заливка

Из **родителя** не коммить: копируй только дерево `milfus-main/` в новый клон или делай `git init` **внутри** `milfus-main`.

```bash
cd milfus-main
git init -b main
git add .
git status   # убедись, что нет *.tar.gz образов и bundle
git commit -m "Milvus offline: charts, values, images (Dockerfile), scripts, tests, docs"
```

Добавь remote на приватный хост (GitLab / Bitbucket и т.д.):

```bash
git remote add origin https://<host>/<group>/milfus-main.git
```

### Токен (не светить в истории)

- **Не вставляй** токен в коммиченные файлы и не клади в URL в общий чат скринами с историей.
- Предпочтительно: **Personal Access Token** / **Project token** + обычный `git push` (запрос пароля = токен) или менеджер учётных данных.
- Временный вариант (осторожно, попадает в `~/.git-credentials` если настроено):

  ```bash
  git push https://oauth2:<TOKEN>@<host>/<group>/milfus-main.git main
  ```

  После push смени токен при подозрении на утечку.

## Проверка перед push

```bash
git ls-files | grep -E '\.tar\.gz$' || echo "OK: no tar.gz tracked"
du -sh .git  # разумный размер без образов
```

Когда будут **URL репозитория и способ аутентификации**, можно выполнить push с этой машины тем же набором файлов — **только содержимое `milfus-main`**, без изменений из других частей `kub_help`.
