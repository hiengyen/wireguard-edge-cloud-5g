#!/usr/bin/env bash
# Test 03-A: Prometheus health, scrape targets, and metric availability
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

section "03-A  Prometheus Service"
require_cmd curl

PROM="${PROMETHEUS_URL}"
TIMEOUT="$HTTP_TIMEOUT"

http_get() {
    curl -sf --max-time "$TIMEOUT" "$1" 2>/dev/null
}

# 1. Health endpoint
log "Checking Prometheus health: ${PROM}/-/healthy"
if resp=$(http_get "${PROM}/-/healthy"); then
    pass "Prometheus healthy: ${resp}"
else
    fail "Prometheus health check failed at ${PROM}/-/healthy"
    print_summary "03-prometheus"; exit 1
fi

# 2. Ready endpoint
log "Checking Prometheus ready: ${PROM}/-/ready"
if resp=$(http_get "${PROM}/-/ready"); then
    pass "Prometheus ready"
else
    fail "Prometheus not ready: ${PROM}/-/ready"
fi

# 3. Response latency
log "Measuring query API response time"
latency=$(curl -sf -o /dev/null -w '%{time_total}' --max-time "$TIMEOUT" \
    "${PROM}/api/v1/query?query=up" 2>/dev/null || echo "timeout")
if [[ "$latency" != "timeout" ]]; then
    ms=$(echo "scale=0; $latency * 1000 / 1" | bc)
    (( ms < 500 )) && pass "Query API latency: ${ms}ms" \
                   || warn "Query API latency: ${ms}ms (high — check Prometheus CPU)"
else
    fail "Prometheus query API timed out"
fi

# 4. Scrape targets — active client target must be UP
log "Checking scrape targets status"
targets_json=$(http_get "${PROM}/api/v1/targets" || echo "{}")
total=$(echo "$targets_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(len(d.get('data',{}).get('activeTargets',[])))
" 2>/dev/null || echo "0")

up=$(echo "$targets_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(sum(1 for t in d.get('data',{}).get('activeTargets',[]) if t.get('health')=='up'))
" 2>/dev/null || echo "0")

down=$(echo "$targets_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for t in d.get('data',{}).get('activeTargets',[]):
    if t.get('health') != 'up':
        print(f\"  DOWN: {t.get('labels',{}).get('job','?')} @ {t.get('scrapeUrl','?')}\")
" 2>/dev/null || true)

info "Scrape targets: ${up}/${total} UP"
[[ -n "$down" ]] && warn "Down targets:${down}"

# Verify specifically if our current client target is active and up
client_status=$(echo "$targets_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
client_ip = sys.argv[1]
found = False
client_up = False
for t in d.get('data',{}).get('activeTargets',[]):
    if f'{client_ip}:9100' in t.get('scrapeUrl', ''):
        found = True
        if t.get('health') == 'up':
            client_up = True
            break
print(f'{found},{client_up}')
" "$WG_CLIENT_IP" 2>/dev/null || echo "False,False")

IFS=',' read -r client_found client_up <<< "$client_status"

if [[ "$client_found" == "True" ]]; then
    if [[ "$client_up" == "True" ]]; then
        pass "Scrape target for edge node ${WG_CLIENT_IP} is UP"
    else
        fail "Scrape target for edge node ${WG_CLIENT_IP} is DOWN"
    fi
else
    warn "Scrape target for edge node ${WG_CLIENT_IP} not found in Prometheus active targets"
fi

# 5. Key metrics present
log "Verifying key metrics are present"
check_metric() {
    local metric="$1" label="$2"
    local result
    result=$(http_get "${PROM}/api/v1/query?query=${metric}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(len(d.get('data',{}).get('result',[])))
" 2>/dev/null || echo "0")
    (( result > 0 )) && pass "Metric present: ${label} (${result} series)" \
                       || fail "Metric missing: ${label}"
}

check_metric "up"                                   "up (all targets)"
check_metric "node_cpu_seconds_total"               "node CPU (cloud)"
check_metric "node_memory_MemAvailable_bytes"       "node memory"
check_metric "node_filesystem_avail_bytes"          "node disk"
check_metric "node_network_receive_bytes_total"     "network RX bytes"

# 6. Storage retention info
log "Checking Prometheus storage"
tsdb_info=$(http_get "${PROM}/api/v1/status/tsdb" || echo "{}")
num_series=$(echo "$tsdb_info" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('data',{}).get('headStats',{}).get('numSeries',0))
" 2>/dev/null || echo "?")
info "Active time series: ${num_series}"

print_summary "03-prometheus"
