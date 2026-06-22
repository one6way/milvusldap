# Jaeger all-in-one, UID:GID 65000:65000.
# Storage: in-memory for smoke/quick checks.
FROM jaegertracing/all-in-one:1.57

USER root
RUN mkdir -p /tmp/jaeger && chown -R 65000:65000 /tmp \
    && chown -R 65000:65000 /go 2>/dev/null || true

USER 65000:65000
ENV SPAN_STORAGE_TYPE=memory
