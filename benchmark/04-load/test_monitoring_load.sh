#!/usr/bin/env bash
# Test 04-B: Monitoring stack under concurrent query load
# Sends parallel requests to Prometheus, Loki, Grafana and measures response times
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

section "04-B  Monitoring Stack Load Test"
require_cmd curl bc

CONCURRENCY="${CONCURRENCY:-10}"          # concurrent requests per service
ITERATIONS="${ITERATIONS:-30}"            # total requests per endpoint
MAX_P95_MS="${MAX_P95_MS:-3000}"          # p95 response time threshold (ms)

REPORT_FILE="${REPORT_DIR}/monitoring_load_$(date '+%Y%m%d_%H%M%S').csv"
mkdir -p "$REPORT_DIR"
echo "service,endpoint,request_ms" > "$REPORT_FILE"

# Fire N concurrent curl requests to URL, collect latencies
load_test_endpoint() {
    local label="$1" url="$2" count="${3:-$ITERATIONS}" auth_flag="${4:-}"
    log "Load testing: ${label} (${count} requests, concurrency=${CONCURRENCY})"

    local latencies=()
    local tmpdir; tmpdir=$(mktemp -d)
    local pids=()

    local i=0
    while (( i < count )); do
        # Batch up to CONCURRENCY requests in parallel
        local batch=0
        while (( batch < CONCURRENCY && i < count )); do
            (
                local ms
                # shellcheck disable=SC2086
                ms=$(curl -sf -o /dev/null -w '%{time_total}' \
                    --max-time "$HTTP_TIMEOUT" $auth_flag "$url" 2>/dev/null || echo "timeout")
                echo "$ms" > "${tmpdir}/req_${i}_${batch}"
            ) &
            pids+=($!)
            (( batch++ )) || true
            (( i++ ))   || true
        done
        # Wait for current batch
        for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
        pids=()
    done

    # Collect results
    local times=()
    local failed=0
    for f in "${tmpdir}"/req_*; do
        local val; val=$(cat "$f" 2>/dev/null || echo "timeout")
        if [[ "$val" == "timeout" || "$val" == "" ]]; then
            (( failed++ )) || true
        else
            local ms; ms=$(echo "scale=0; $val * 1000 / 1" | bc 2>/dev/null || echo "0")
            times+=("$ms")
            echo "${label},${url},${ms}" >> "$REPORT_FILE"
        fi
    done
    rm -rf "$tmpdir"

    if (( ${#times[@]} == 0 )); then
        fail "${label}: all ${count} requests failed"
        return 1
    fi

    # Compute stats
    local n=${#times[@]}
    local sorted; sorted=$(printf '%s\n' "${times[@]}" | sort -n)
    local p50 p95 p99 mean_ms max_ms
    if (( n > 0 )); then
        p50=$(echo "$sorted" | awk -v n="$n" 'NR==int(n*0.50)+1{print}')
        p95=$(echo "$sorted" | awk -v n="$n" 'NR==int(n*0.95)+1{print}')
        p99=$(echo "$sorted" | awk -v n="$n" 'NR==int(n*0.99)+1{print}')
        max_ms=$(echo "$sorted" | tail -1)
        mean_ms=$(printf '%s\n' "${times[@]}" | awk '{s+=$1}END{printf "%.0f", s/NR}')
    else
        p50="0" p95="0" p99="0" max_ms="0" mean_ms="0"
    fi

    # Ensure empty vars get defaults
    p50="${p50:-0}"
    p95="${p95:-0}"
    p99="${p99:-0}"
    max_ms="${max_ms:-0}"
    mean_ms="${mean_ms:-0}"

    info "${label}: n=${n} fail=${failed} mean=${mean_ms}ms p50=${p50}ms p95=${p95}ms p99=${p99}ms max=${max_ms}ms"

    local ok=true
    (( failed > count / 5 ))                      && { fail "${label}: too many failures (${failed}/${count})"; ok=false; }
    (( ${p95:-9999} > MAX_P95_MS ))               && { warn "${label}: p95=${p95}ms exceeds ${MAX_P95_MS}ms"; }

    $ok && pass "${label}: p95=${p95}ms mean=${mean_ms}ms"
}

# ─── Prometheus load ──────────────────────────────────────────────────────────
load_test_endpoint "prometheus-health"  "${PROMETHEUS_URL}/-/healthy"
load_test_endpoint "prometheus-query"   "${PROMETHEUS_URL}/api/v1/query?query=up"
load_test_endpoint "prometheus-range"   "${PROMETHEUS_URL}/api/v1/query_range?query=node_cpu_seconds_total&start=$(( $(date +%s) - 300 ))&end=$(date +%s)&step=15"

# ─── Loki load ────────────────────────────────────────────────────────────────
load_test_endpoint "loki-ready"   "${LOKI_URL}/ready"
LOKI_Q=$(python3 -c "import urllib.parse; print(urllib.parse.quote('{job=~\".+\"}'  ))")
load_test_endpoint "loki-query"   "${LOKI_URL}/loki/api/v1/query?query=${LOKI_Q}&limit=10"

# ─── Grafana load ─────────────────────────────────────────────────────────────
load_test_endpoint "grafana-health"    "${GRAFANA_URL}/api/health" 20 "-u admin:${GRAFANA_ADMIN_PASSWORD}"
load_test_endpoint "grafana-datasrc"   "${GRAFANA_URL}/api/datasources" 20 "-u admin:${GRAFANA_ADMIN_PASSWORD}"

# ─── Node Exporter load ───────────────────────────────────────────────────────
load_test_endpoint "node-exporter-edge"  "${NODE_EXPORTER_EDGE}/metrics" 15

info "CSV report saved: ${REPORT_FILE}"
print_summary "04-monitoring-load"
