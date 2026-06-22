# Non-root runtime (UID/GID 65000) for Kubernetes securityContext; base: official Attu.
# Build: ./scripts/58-build-attu-nonroot-image.sh
FROM zilliz/attu:v2.5.10

USER root
RUN set -eux; \
    if ! getent group 65000 >/dev/null 2>&1; then groupadd -g 65000 attu; fi; \
    if ! id -u 65000 >/dev/null 2>&1; then useradd -u 65000 -g 65000 -m -s /sbin/nologin attu; fi; \
    chown -R 65000:65000 /app

USER 65000:65000
