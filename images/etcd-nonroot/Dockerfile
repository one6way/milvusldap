FROM milvusdb/etcd:3.5.16-r1

USER root

RUN export LD_PRELOAD=""; set -eux; \
    if ! getent group 65000 >/dev/null 2>&1; then groupadd -g 65000 milvus; fi; \
    if ! id -u 65000 >/dev/null 2>&1; then useradd -u 65000 -g 65000 -m -s /sbin/nologin milvus; fi; \
    mkdir -p /bitnami/etcd /opt/bitnami/etcd/data; \
    chown -R 65000:65000 /bitnami /opt/bitnami

USER 65000:65000
