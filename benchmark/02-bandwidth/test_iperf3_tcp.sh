#!/usr/bin/env bash
# Test 02-A: TCP throughput over WireGuard using iperf3
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

section "02-A  TCP Bandwidth (iperf3)"
require_cmd iperf3 bc

MIN_TCP_MBPS="${MIN_TCP_MBPS:-5}"           # Minimum acceptable throughput Mbps
REPORT_FILE="${REPORT_DIR}/iperf3_tcp_$(date '+%Y%m%d_%H%M%S').json"
mkdir -p "$REPORT_DIR"

check_iperf3_server() {
    log "Checking iperf3 server at ${IPERF3_SERVER}:${IPERF3_PORT}"
    if ! iperf3 -c "$IPERF3_SERVER" -p "$IPERF3_PORT" -t 1 -J &>/dev/null; then
        fail "iperf3 server unreachable at ${IPERF3_SERVER}:${IPERF3_PORT}"
        info "Start iperf3 server on cloud with: iperf3 -s -D"
        print_summary "02-tcp-bandwidth"; exit 1
    fi
    pass "iperf3 server reachable"
}

run_tcp_test() {
    local label="$1" extra_flags="${2:-}"
    log "Running: ${label}"

    local result_json
    # shellcheck disable=SC2086
    result_json=$(iperf3 -c "$IPERF3_SERVER" -p "$IPERF3_PORT" \
        -t "$IPERF3_DURATION" \
        -P "$IPERF3_PARALLEL" \
        --json $extra_flags 2>/dev/null)

    if [[ -z "$result_json" ]]; then
        fail "${label}: iperf3 produced no output"
        return 1
    fi

    local mbps retransmits rtt
    mbps=$(echo "$result_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
bps = d.get('end',{}).get('sum_received',{}).get('bits_per_second', 0)
print(f'{bps/1e6:.2f}')
" 2>/dev/null || echo "0")

    retransmits=$(echo "$result_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('end',{}).get('sum_sent',{}).get('retransmits', 0))
" 2>/dev/null || echo "?")

    rtt=$(echo "$result_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('end',{}).get('streams',[{}])[0].get('sender',{}).get('mean_rtt',0))
" 2>/dev/null || echo "?")

    info "${label}: ${mbps} Mbps  retransmits=${retransmits}  mean_rtt=${rtt}μs"

    local ok=true
    (( $(echo "$mbps < $MIN_TCP_MBPS" | bc -l) )) && { fail "${label}: ${mbps} Mbps below threshold ${MIN_TCP_MBPS} Mbps"; ok=false; }
    (( ${retransmits:-0} > 100 ))                  && { warn "${label}: high retransmits=${retransmits}"; }

    $ok && pass "${label}: ${mbps} Mbps (threshold=${MIN_TCP_MBPS} Mbps)"

    # Append to report
    echo "=== ${label} ===" >> "${REPORT_FILE%.json}.txt"
    echo "$result_json" | python3 -m json.tool >> "${REPORT_FILE%.json}.txt" 2>/dev/null || true
}

# ─── Tests ────────────────────────────────────────────────────────────────────
check_iperf3_server

# 1. Default: uplink (edge → cloud), parallel streams
run_tcp_test "TCP-uplink   (${IPERF3_PARALLEL}P × ${IPERF3_DURATION}s)"

# 2. Downlink (cloud → edge), reverse mode
run_tcp_test "TCP-downlink (reverse, ${IPERF3_PARALLEL}P × ${IPERF3_DURATION}s)" "-R"

# 3. Single-stream (no parallel) — measures raw overhead
run_tcp_test "TCP-single-stream (1P × ${IPERF3_DURATION}s)" "-P 1"

# 4. Larger window size — tests buffer performance
run_tcp_test "TCP-window-512K" "-P 1 -w 512K"

# 5. Bidirectional (requires iperf3 ≥ 3.7)
if iperf3 --help 2>&1 | grep -q -- '--bidir'; then
    run_tcp_test "TCP-bidirectional" "--bidir -P 2"
else
    info "Skipping bidirectional test (iperf3 < 3.7)"
fi

print_summary "02-tcp-bandwidth"
