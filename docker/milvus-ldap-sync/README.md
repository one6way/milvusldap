# milvus-ldap-sync image

| Dockerfile | База | Когда |
|------------|------|--------|
| `Dockerfile` | `python:3.11-slim` (Debian, manylinux) | prep / macOS, есть интернет |
| `Dockerfile.alpine` | `python:3.11-alpine` / `alpine-python:3.11.9` | **prod / закрытый контур (musl)** |

## Alpine + offline

На prep-стенде (интернет):

```bash
./scripts/57a-download-ldap-alpine-wheels.sh
# → docker/milvus-ldap-sync/wheels-alpine/*.whl (musllinux)
# → artifacts/ldap-alpine-wheels.tar.gz
```

На закрытом контуре:

```bash
tar -xzf ldap-alpine-wheels.tar.gz -C /path/to/milfus-main/docker/
export BASE_IMAGE=alpine-python:3.11.9   # ваш тег
export VARIANT=alpine
./scripts/57-build-ldap-images-nonroot.sh
```

Сборка **без pip из сети** — только `--no-index --find-links=/wheels`.

## Проверка musllinux

В логе build должно быть: `deps OK 2.5.0`  
Ключевой wheel: `grpcio-*-musllinux_*.whl` (не manylinux).
