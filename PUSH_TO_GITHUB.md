# Публикация в GitHub

Локальный репозиторий уже инициализирован в этом каталоге (`git init`, коммит `main`).

## Что в Git / что нет

| В Git | Не в Git |
|-------|----------|
| Dockerfile (`docker/`, `images/*/`) | `artifacts/*.tar.gz` |
| manifests, values, scripts | `images/export/`, `images/ispravleno/` |
| документация, Helm chart | `images/init-base-nonroot/wheels/` |
| | любые `*.tar.gz` |

## Создать репозиторий на GitHub

1. https://github.com/one6way/milvusldap (уже создан) или https://github.com/new
2. **Не** добавлять README/license (у нас уже есть коммит).

## Push (токен с правом `repo`)

```bash
cd milfus-main   # или путь к клону

git remote add origin https://github.com/one6way/milvusldap.git
# один раз: ввести логин + Personal Access Token как пароль
git push -u origin main
```

Или через переменную окружения (токен **не** коммитить в файлы):

```bash
export GITHUB_TOKEN='<ваш PAT с scope repo>'
git push "https://x-access-token:${GITHUB_TOKEN}@github.com/one6way/milvusldap.git" main
```

## Проверка перед push

```bash
git ls-files | grep -E '\.tar\.gz$' || echo "OK: tar.gz не в индексе"
du -sh .git   # ожидаемо несколько MB, не GB
```

## Если push не прошёл

- `403 Resource not accessible` — у PAT нет scope **repo** (или Fine-grained: Contents read/write).
- `Invalid username or token` — токен просрочен/отозван; создать новый.

**Не публикуйте токен в чатах.** Если токен светился — отзовите в GitHub → Settings → Developer settings → Personal access tokens.
