# Lightweight non-root base image for init/utility jobs.
# UID:GID fixed to 65000:65000 for Kubernetes restricted policies.
FROM alpine:3.20

RUN set -eux; \
    apk add --no-cache \
      bash \
      curl \
      bind-tools \
      iputils \
      iproute2 \
      netcat-openbsd \
      busybox-extras; \
    addgroup -g 65000 -S initgrp; \
    adduser -u 65000 -S -G initgrp inituser; \
    mkdir -p /work /tmp/init && chown -R 65000:65000 /work /tmp/init

WORKDIR /work
USER 65000:65000

# Default to shell; override command in Kubernetes Job as needed.
ENTRYPOINT ["/bin/sh"]
