#!/usr/bin/env bash
# Test 03-B: Loki health, log ingestion, and query response
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

section "03-B  Loki Log Aggregation"
require_cmd curl python3

LOKI="${LOKI_URL}"
TIMEOUT="$HTTP_TIMEOUT"

http_get()  { curl -sf  --max-time "$TIMEOUT" "$1" 2>/dev/null; }
http_post() { curl -sf  --max-time "$TIMEOUT" -H "Content-Type: application/json" -d "$2" "$1" 2>/dev/null; }

# 1. Ready check
log "Checking Loki readiness: ${LOKI}/ready"
if resp=$(http_get "${LOKI}/ready"); then
    pass "Loki ready: ${resp}"
else
    fail "Loki not ready at ${LOKI}/ready"
    print_summary "03-loki"; exit 1
fi

# 2. Response latency
latency=$(curl -sf -o /dev/null -w '%{time_total}' --max-time "$TIMEOUT" "${LOKI}/ready" 2>/dev/null || echo "timeout")
if [[ "$latency" != "timeout" ]]; then
    ms=$(echo "scale=0; $latency * 1000 / 1" | bc)
    (( ms < 1000 )) && pass "Loki ready latency: ${ms}ms" \
                     || warn "Loki ready latency: ${ms}ms (high)"
fi

# 3. Push a test log entry
log "Pushing test log entry to Loki"
NOW_NS=$(date +%s%N)
PUSH_PAYLOAD=$(python3 -c "
import json, os
ts = '${NOW_NS}'
payload = {
    'streams': [{
        'stream': {'job': '_benchmark_probe', 'host': os.uname().nodename},
        'values': [[ts, '_benchmark_probe: Loki push test from wireguard-edge-cloud-5g benchmark suite']]
    }]
}
print(json.dumps(payload))
")

if curl -sf --max-time "$TIMEOUT" \
    -H "Content-Type: application/json" \
    -d "$PUSH_PAYLOAD" \
    "${LOKI}/loki/api/v1/push" &>/dev/null; then
    pass "Log push to Loki succeeded"
else
    fail "Log push to Loki failed — check Loki ingestion endpoint"
fi

# 4. Query back the test entry
sleep 2  # allow indexing
log "Querying test log entry back"
ENCODED_QUERY=$(python3 -c "import urllib.parse; print(urllib.parse.quote('{job=\"_benchmark_probe\"}'))")
query_result=$(http_get "${LOKI}/loki/api/v1/query_range?query=${ENCODED_QUERY}&limit=5&start=$(( NOW_NS - 30000000000 ))&end=$(date +%s%N)" || echo "{}")
log_count=$(echo "$query_result" | python3 -c "
import sys, json
d = json.load(sys.stdin)
total = sum(len(s.get('values',[])) for s in d.get('data',{}).get('result',[]))
print(total)
" 2>/dev/null || echo "0")

(( log_count > 0 )) && pass "Query returned ${log_count} log line(s) for _benchmark_probe job" \
                      || fail "No log lines returned — push may have failed or index is slow"

# 5. Check edge-journal label (Alloy log stream)
log "Checking for edge-journal logs from Alloy"
EDGE_QUERY=$(python3 -c "import urllib.parse; print(urllib.parse.quote('{job=\"edge-journal\"}'  ))")
edge_result=$(http_get "${LOKI}/loki/api/v1/labels" || echo "{}")
labels=$(echo "$edge_result" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('data', []))
" 2>/dev/null || echo "[]")
info "Loki label names: ${labels}"

if echo "$labels" | grep -q '"job"'; then
    pass "Label 'job' exists in Loki"
else
    warn "Label 'job' not found — Alloy may not be shipping logs yet"
fi

# 6. Log rate (entries per second) over last 5 minutes
log "Checking log ingestion rate"
RATE_QUERY=$(python3 -c "import urllib.parse; print(urllib.parse.quote('rate({job=~\".+\"}[5m])'))")
rate_result=$(http_get "${LOKI}/loki/api/v1/query?query=${RATE_QUERY}" || echo "{}")
rate=$(echo "$rate_result" | python3 -c "
import sys, json
d = json.load(sys.stdin)
vals = [float(v[1]) for s in d.get('data',{}).get('result',[]) for v in s.get('values',[s.get('value',['0','0'])])]
print(f'{sum(vals):.3f}')
" 2>/dev/null || echo "0")
info "Current log ingestion rate: ${rate} entries/s"
(( $(echo "$rate > 0" | bc -l) )) && pass "Logs are being ingested (rate=${rate}/s)" \
                                    || warn "No active log ingestion detected"

print_summary "03-loki"
