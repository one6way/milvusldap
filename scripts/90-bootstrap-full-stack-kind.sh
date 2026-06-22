#!/usr/bin/env bash
# Полный подъём на kind: local-path + non-root образы из artifacts (или сборка один раз) + Milvus + Attu.
# Сеть не нужна для Helm. Интернет только если нет локальных образов (тогда запускается 53).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f "$ROOT/chart/milvus/Chart.yaml" ]]; then
  echo "ERROR: ожидается chart/milvus (полный bootstrap только из каталога milvus-airgap)." >&2
  exit 1
fi

need() { command -v "$1" >/dev/null || { echo "ERROR: missing command: $1" >&2; exit 1; }; }
need docker
docker info >/dev/null 2>&1 || { echo "ERROR: Docker daemon not running." >&2; exit 1; }
need kind
need kubectl
need helm

CLUSTER_NAME="${CLUSTER_NAME:-milvus-local}"
export CLUSTER_NAME

chmod +x scripts/*.sh 2>/dev/null || true

marker="artifacts/images/milvus-nonroot__2.5.0.tar"
if [[ ! -f "$marker" ]] || ! docker image inspect "milvus-nonroot:2.5.0" >/dev/null 2>&1; then
  echo "==> Сборка non-root образов и выгрузка в artifacts (один раз; нужен интернет для базовых pull)"
  ./scripts/53-build-all-nonroot-images.sh
  ./scripts/50-collect-images.sh
fi

echo "==> 1/5 kind cluster"
./scripts/10-create-kind-cluster.sh

echo "==> 2/5 local-path"
./scripts/20-install-local-path-provisioner.sh

echo "==> 3/5 загрузка образов в kind"
./scripts/60-load-images-kind.sh

echo "==> 4/5 Milvus (Helm без dependency update)"
./scripts/30-install-milvus-online.sh

echo "==> 5/5 Attu"
./scripts/31-install-attu.sh

echo "==> проверка API"
./scripts/40-verify-milvus-api.sh

echo ""
echo "Готово. Чеклист: MILVUS_KIND_STACK_TEST_CHECKLIST.md"
echo "  kubectl port-forward -n milvus svc/attu 3000:3000"
echo "  ./scripts/41-verify-attu-prereqs.sh"
