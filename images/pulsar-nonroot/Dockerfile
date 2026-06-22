FROM apachepulsar/pulsar:3.0.7

USER root

RUN export LD_PRELOAD=""; set -eux; \
    if ! getent group 65000 >/dev/null 2>&1; then groupadd -g 65000 milvus; fi; \
    if ! id -u 65000 >/dev/null 2>&1; then useradd -u 65000 -g 65000 -m -s /sbin/nologin milvus; fi; \
    mkdir -p /pulsar /pulsar/data /pulsar/logs; \
    chown -R 65000:65000 /pulsar

USER 65000:65000
