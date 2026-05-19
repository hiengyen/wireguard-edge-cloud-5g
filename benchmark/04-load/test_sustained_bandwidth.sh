#!/usr/bin/env bash
# Test 04-A: Sustained bandwidth test — run iperf3 for an extended period
# and track throughput stability (no degradation over time)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

section "04-A  Sustained Bandwidth (${SUSTAINED_DURATION}s)"
require_cmd iperf3 python3 bc

MIN_SUSTAINED_MBPS="${MIN_SUSTAINED_MBPS:-3}"
MAX_VARIANCE_PCT="${MAX_VARIANCE_PCT:-40}"  # max allowed stddev as % of mean
INTERVAL=5                                  # iperf3 report interval (seconds)

REPORT_FILE="${REPORT_DIR}/sustained_$(date '+%Y%m%d_%H%M%S').csv"
mkdir -p "$REPORT_DIR"

log "Checking iperf3 server at ${IPERF3_SERVER}:${IPERF3_PORT}"
if ! iperf3 -c "$IPERF3_SERVER" -p "$IPERF3_PORT" -t 1 -J &>/dev/null; then
    fail "iperf3 server unreachable — start: iperf3 -s -D"
    print_summary "04-sustained-bandwidth"; exit 1
fi
pass "iperf3 server reachable"

run_sustained() {
    local label="$1" extra_flags="${2:-}"
    log "Starting ${label} (${SUSTAINED_DURATION}s)"

    local json_output
    # shellcheck disable=SC2086
    json_output=$(iperf3 -c "$IPERF3_SERVER" -p "$IPERF3_PORT" \
        -t "$SUSTAINED_DURATION" \
        -i "$INTERVAL" \
        -P "$IPERF3_PARALLEL" \
        --json $extra_flags 2>/dev/null)

    if [[ -z "$json_output" ]]; then
        fail "${label}: no output"; return 1
    fi

    # Parse JSON output and write to CSV
    local analysis
    analysis=$(python3 -c "
import sys, json, math

try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    print('ERROR: invalid JSON output from iperf3')
    sys.exit(1)

if 'error' in data:
    print('ERROR: iperf3 error: ' + data['error'])
    sys.exit(1)

intervals = data.get('intervals', [])
if not intervals:
    print('ERROR: no intervals in iperf3 output')
    sys.exit(1)

mbps_series = []

with open('${REPORT_FILE}', 'a') as f:
    f.write('label,interval_start,mbps\n')
    for iv in intervals:
        bits = sum(s.get('bits_per_second', 0) for s in iv.get('streams', []))
        mbps = bits / 1e6
        start = iv['sum']['start']
        mbps_series.append(mbps)
        f.write(f'${label},{start:.1f},{mbps:.2f}\n')

mean_mbps = sum(mbps_series) / len(mbps_series)
min_mbps = min(mbps_series)
max_mbps = max(mbps_series)
stddev = math.sqrt(sum((x - mean_mbps)**2 for x in mbps_series) / len(mbps_series))
variance_pct = (stddev / mean_mbps * 100) if mean_mbps > 0 else 0

print(f'{mean_mbps:.2f} {min_mbps:.2f} {max_mbps:.2f} {variance_pct:.1f}')
" <<< "$json_output")

    if [[ "$analysis" == ERROR:* ]]; then
        fail "${label}: ${analysis}"
        return 1
    fi

    # Read computed values back
    local analysis
    analysis=$(python3 -c "
import json, math, sys
data = json.loads(open('/dev/stdin').read())
intervals = data.get('intervals', [])
vals = [sum(s.get('bits_per_second',0) for s in iv.get('streams',[])) / 1e6 for iv in intervals]
if not vals: sys.exit(1)
mean = sum(vals)/len(vals)
sd = math.sqrt(sum((x-mean)**2 for x in vals)/len(vals))
vp = sd/mean*100 if mean > 0 else 0
print(f'{mean:.2f} {min(vals):.2f} {max(vals):.2f} {vp:.1f}')
" <<< "$json_output")

    local mean_mbps min_mbps max_mbps variance_pct
    read -r mean_mbps min_mbps max_mbps variance_pct <<< "$analysis"

    info "${label}: mean=${mean_mbps}Mbps min=${min_mbps} max=${max_mbps} variance=${variance_pct}%"

    local ok=true
    (( $(echo "$mean_mbps < $MIN_SUSTAINED_MBPS" | bc -l) )) \
        && { fail "${label}: mean ${mean_mbps}Mbps below ${MIN_SUSTAINED_MBPS}Mbps"; ok=false; }
    (( $(echo "$variance_pct > $MAX_VARIANCE_PCT" | bc -l) )) \
        && { warn "${label}: high variance ${variance_pct}% (threshold=${MAX_VARIANCE_PCT}%) — unstable link"; }

    $ok && pass "${label}: sustained ${mean_mbps}Mbps ±${variance_pct}%"
}

# 1. Sustained uplink
run_sustained "sustained-uplink   (${SUSTAINED_DURATION}s)"

# 2. Sustained downlink (reverse)
run_sustained "sustained-downlink (${SUSTAINED_DURATION}s)" "-R"

# 3. Simultaneous bidirectional (bidir) — if supported
if iperf3 --help 2>&1 | grep -q -- '--bidir'; then
    run_sustained "sustained-bidir    (${SUSTAINED_DURATION}s)" "--bidir -P 2"
fi

info "CSV report saved: ${REPORT_FILE}"
print_summary "04-sustained-bandwidth"
