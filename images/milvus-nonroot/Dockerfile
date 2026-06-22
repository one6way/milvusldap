FROM milvusdb/milvus:v2.5.0

# Create a non-root runtime user with fixed UID/GID=65000.
# Keep it minimal and compatible with air-gapped image mirroring.
RUN export LD_PRELOAD=""; set -eux; \
    if getent group 65000 >/dev/null 2>&1; then \
      group_name="$(getent group 65000 | cut -d: -f1)"; \
    else \
      groupadd -g 65000 milvus; \
      group_name="milvus"; \
    fi; \
    if id -u 65000 >/dev/null 2>&1; then \
      user_name="$(getent passwd 65000 | cut -d: -f1)"; \
    else \
      useradd -u 65000 -g 65000 -m -s /sbin/nologin milvus; \
      user_name="milvus"; \
    fi; \
    mkdir -p /var/lib/milvus /milvus /milvus/configs /milvus/tools; \
    chown -R 65000:65000 /var/lib/milvus /milvus

USER 65000:65000
