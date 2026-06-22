FROM python:3.11-slim

ARG RUNTIME_UID=65000
ARG RUNTIME_GID=65000

RUN pip install --no-cache-dir ldap3==2.9.1

RUN set -eux; \
    if ! getent group "${RUNTIME_GID}" >/dev/null; then \
      groupadd -g "${RUNTIME_GID}" milvus; \
    fi; \
    if ! getent passwd "${RUNTIME_UID}" >/dev/null; then \
      useradd -u "${RUNTIME_UID}" -g "${RUNTIME_GID}" -m -s /usr/sbin/nologin milvus; \
    fi; \
    mkdir -p /app; \
    chown -R "${RUNTIME_UID}:${RUNTIME_GID}" /app

WORKDIR /app
COPY --chown=${RUNTIME_UID}:${RUNTIME_GID} scripts/ldap_auth_extauthz.py /app/ldap_auth_extauthz.py

EXPOSE 8080
USER ${RUNTIME_UID}:${RUNTIME_GID}
ENTRYPOINT ["python", "/app/ldap_auth_extauthz.py"]
