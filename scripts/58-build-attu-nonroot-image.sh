#!/usr/bin/env bash
set -euo pipefail

# Run from any path; build context = milvus-airgap root.
cd "$(dirname "$0")/.."

IMAGE_NAME="${IMAGE_NAME:-attu-nonroot}"
IMAGE_TAG="${IMAGE_TAG:-2.5.10}"

docker build \
  -t "${IMAGE_NAME}:${IMAGE_TAG}" \
  -f images/attu-nonroot/Dockerfile \
  images/attu-nonroot

docker run --rm "${IMAGE_NAME}:${IMAGE_TAG}" id
