#!/usr/bin/env bash
# Набор смоук-тестов Milvus в Kubernetes + Markdown-отчёт с фрагментами вывода/логов.
# Запуск из корня milfus-main: ./tests/run_milvus_test_report.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NAMESPACE="${NAMESPACE:-milvus}"
REPORT_DIR="${REPORT_DIR:-$ROOT/tests/reports}"
TS="$(date +%Y%m%d-%H%M%S)"
REPORT="${REPORT_DIR}/milvus-test-report-${TS}.md"
mkdir -p "$REPORT_DIR"

PASS=0
FAIL=0

tmp_all="$(mktemp)"
trap 'rm -f "$tmp_all"' EXIT

md_h1() { echo "$*" >>"$REPORT"; echo >>"$REPORT"; }
md_h2() { echo "## $*" >>"$REPORT"; echo >>"$REPORT"; }
md_p() { echo "$*" >>"$REPORT"; echo >>"$REPORT"; }
md_code() {
  echo '```text' >>"$REPORT"
  # shellcheck disable=SC2002
  sed 's/\r$//' "$1" | tail -n "${2:-80}" >>"$REPORT"
  echo '```' >>"$REPORT"
  echo >>"$REPORT"
}

run_case() {
  local id="$1" title="$2"
  shift 2
  local out
  out="$(mktemp)"
  local t0
  t0="$(date +%s)"
  set +e
  "$@" >"$out" 2>&1
  local rc=$?
  set -e
  local t1
  t1="$(date +%s)"
  local dur=$((t1 - t0))

  md_h2 "${id} — ${title}"
  if [[ $rc -eq 0 ]]; then
    echo "| Статус | PASS |" >>"$REPORT"
    echo "| Время (с) | ${dur} |" >>"$REPORT"
    echo >>"$REPORT"
    PASS=$((PASS + 1))
  else
    echo "| Статус | **FAIL** (exit ${rc}) |" >>"$REPORT"
    echo "| Время (с) | ${dur} |" >>"$REPORT"
    echo >>"$REPORT"
    FAIL=$((FAIL + 1))
  fi
  md_p "**Фрагмент вывода (до 80 строк):**"
  md_code "$out" 80
  rm -f "$out"
}

# --- заголовок отчёта ---
{
  echo "# Отчёт тестов Milvus (Kubernetes)"
  echo
  echo "| Поле | Значение |"
  echo "|------|----------|"
  echo "| Дата | $(date -Iseconds 2>/dev/null || date) |"
  echo "| Namespace | \`${NAMESPACE}\` |"
  echo "| kubectl context | \`$(kubectl config current-context 2>/dev/null || echo n/a)\` |"
  echo
} >>"$REPORT"

# --- тесты ---

run_case "T1" "Критичные Deployment в Available" \
  bash -c "kubectl wait --for=condition=available deploy/milvus-proxy -n '${NAMESPACE}' --timeout=120s && \
           kubectl wait --for=condition=available deploy/milvus-mixcoord -n '${NAMESPACE}' --timeout=120s"

run_case "T2" "Сводка pod (имя / Ready / статус)" \
  kubectl get pods -n "$NAMESPACE" -o wide

run_case "T3" "Сервисы milvus и attu" \
  kubectl get svc -n "$NAMESPACE" milvus attu

run_case "T4" "Health proxy изнутри pod (9091/healthz)" \
  kubectl exec -n "$NAMESPACE" deploy/milvus-proxy -- curl -sS --max-time 10 http://127.0.0.1:9091/healthz

run_case "T5" "Достижимость TCP к milvus:19530 (ephemeral busybox)" \
  kubectl run -n "$NAMESPACE" "milvus-nc-${TS}" --rm --attach --restart=Never --image=busybox:1.36 -- \
    sh -c 'nc -z -w 5 milvus 19530 && echo "tcp 19530 OK"'

run_case "T6" "Фрагмент логов milvus-proxy (tail)" \
  kubectl logs -n "$NAMESPACE" deploy/milvus-proxy --tail=40

run_case "T7" "Фрагмент логов milvus-mixcoord (tail)" \
  kubectl logs -n "$NAMESPACE" deploy/milvus-mixcoord --tail=30

run_case "T8" "PVC в статусе Bound (кратко)" \
  kubectl get pvc -n "$NAMESPACE"

# Опционально: PyMilvus (хост должен видеть 19530, например port-forward в другом терминале)
if [[ "${RUN_PYMILVUS:-0}" == "1" ]]; then
  run_case "T9" "PyMilvus: версия сервера (localhost:19530)" \
    python3 "$ROOT/tests/milvus_pymilvus_version.py"
else
  md_h2 "T9 — PyMilvus (пропущен)"
  md_p "Запуск с проверкой SDK: \`RUN_PYMILVUS=1 ./tests/run_milvus_test_report.sh\` (нужен \`pip install pymilvus\` и \`kubectl port-forward -n milvus svc/milvus 19530:19530\`)."
fi

# Демо «медленных» search для Web UI — см. tests/SLOW_QUERY_WEBUI.md и tests/milvus_simulate_slow_queries.py
if [[ "${RUN_SLOW_QUERY_DEMO:-0}" == "1" ]]; then
  # По умолчанию — параметры под панель Slow Requests (см. values-kind-localpath.yaml proxy.slowQuerySpanInSeconds + helm upgrade).
  export SLOW_DEMO_FOR_SLOW_REQUESTS_UI="${SLOW_DEMO_FOR_SLOW_REQUESTS_UI:-1}"
  run_case "T10" "Демо тяжёлых vector search (коллекция slow_demo_webui)" \
    python3 "$ROOT/tests/milvus_simulate_slow_queries.py"
  run_case "T11" "Логи milvus-querynode после нагрузки (tail)" \
    kubectl logs -n "$NAMESPACE" deploy/milvus-querynode --tail=50
else
  md_h2 "T10–T11 — Slow query demo (пропущены)"
  md_p "Для симуляции нагрузки и просмотра в **Web UI** (\`/webui\`): \`RUN_SLOW_QUERY_DEMO=1\` + port-forward **19530** + \`pymilvus\`. Описание: \`tests/SLOW_QUERY_WEBUI.md\`, код: \`tests/milvus_simulate_slow_queries.py\`."
fi

# --- итог ---
{
  echo "## Сводка"
  echo
  echo "| PASS | FAIL |"
  echo "|------|------|"
  echo "| ${PASS} | ${FAIL} |"
  echo
} >>"$REPORT"

echo "Отчёт: $REPORT"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
