#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-milvus-nonroot}"
IMAGE_TAG="${IMAGE_TAG:-2.5.0}"

docker build \
  -t "${IMAGE_NAME}:${IMAGE_TAG}" \
  -f images/milvus-nonroot/Dockerfile \
  images/milvus-nonroot

docker run --rm "${IMAGE_NAME}:${IMAGE_TAG}" id
