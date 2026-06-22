FROM minio/minio:RELEASE.2023-03-20T20-16-18Z

USER root

RUN set -eux; \
    if ! getent group 65000 >/dev/null 2>&1; then groupadd -g 65000 milvus; fi; \
    if ! id -u 65000 >/dev/null 2>&1; then useradd -u 65000 -g 65000 -m -s /sbin/nologin milvus; fi; \
    mkdir -p /data /minio_data; \
    chown -R 65000:65000 /data /minio_data

USER 65000:65000
