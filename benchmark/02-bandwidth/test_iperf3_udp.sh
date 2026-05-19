#!/usr/bin/env bash
# Test 02-B: UDP throughput, jitter, and packet loss over WireGuard using iperf3
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

section "02-B  UDP Bandwidth & Jitter (iperf3)"
require_cmd iperf3 bc

MAX_JITTER_MS="${MAX_JITTER_MS:-10}"          # max acceptable UDP jitter
MAX_LOSS_PCT="${MAX_LOSS_PCT:-2}"             # max acceptable UDP packet loss %
MIN_UDP_MBPS="${MIN_UDP_MBPS:-2}"            # min acceptable UDP throughput

run_udp_test() {
    local label="$1" bitrate="$2" extra_flags="${3:-}"
    log "Running: ${label} at target ${bitrate}"

    local result_json
    # shellcheck disable=SC2086
    result_json=$(iperf3 -c "$IPERF3_SERVER" -p "$IPERF3_PORT" \
        -u -b "$bitrate" \
        -t "$IPERF3_DURATION" \
        --json $extra_flags 2>/dev/null)

    if [[ -z "$result_json" ]]; then
        fail "${label}: no output from iperf3"
        return 1
    fi

    # Check for iperf3 error response
    local iperf_err
    iperf_err=$(echo "$result_json" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('error', ''))" 2>/dev/null || true)
    if [[ -n "$iperf_err" ]]; then
        fail "${label}: iperf3 error: $iperf_err"
        return 1
    fi

    local mbps jitter loss_pct packets_lost packets_total
    mbps=$(echo "$result_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
bps = d.get('end',{}).get('sum',{}).get('bits_per_second', 0)
print(f'{bps/1e6:.2f}')
" 2>/dev/null || echo "0")

    jitter=$(echo "$result_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f\"{d.get('end',{}).get('sum',{}).get('jitter_ms', 0):.3f}\")
" 2>/dev/null || echo "?")

    loss_pct=$(echo "$result_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f\"{d.get('end',{}).get('sum',{}).get('lost_percent', 0):.2f}\")
" 2>/dev/null || echo "?")

    packets_lost=$(echo "$result_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('end',{}).get('sum',{}).get('lost_packets', 0))
" 2>/dev/null || echo "?")

    info "${label}: ${mbps} Mbps  jitter=${jitter}ms  loss=${loss_pct}%  lost_pkts=${packets_lost}"

    local ok=true
    if (( $(echo "$mbps < $MIN_UDP_MBPS"   | bc -l) )); then fail "${label}: ${mbps} Mbps below min ${MIN_UDP_MBPS} Mbps"; ok=false; fi
    if (( $(echo "$jitter > $MAX_JITTER_MS"| bc -l) )); then warn "${label}: jitter ${jitter}ms exceeds ${MAX_JITTER_MS}ms"; fi
    if (( $(echo "$loss_pct > $MAX_LOSS_PCT"| bc -l) )); then fail "${label}: loss ${loss_pct}% exceeds ${MAX_LOSS_PCT}%"; ok=false; fi

    $ok && pass "${label}: ${mbps} Mbps jitter=${jitter}ms loss=${loss_pct}%" || true
}

# Check server
log "Verifying iperf3 server at ${IPERF3_SERVER}:${IPERF3_PORT}"
if ! iperf3 -c "$IPERF3_SERVER" -p "$IPERF3_PORT" -u -b 1M -t 1 -J &>/dev/null; then
    # Could be busy from previous run, try once more
    sleep 2
    if ! iperf3 -c "$IPERF3_SERVER" -p "$IPERF3_PORT" -u -b 1M -t 1 -J &>/dev/null; then
        fail "iperf3 UDP server unreachable — ensure server is running: iperf3 -s -D"
        print_summary "02-udp-bandwidth"; exit 1
    fi
fi
pass "iperf3 server reachable (UDP)"
sleep 2 # Wait for server to be ready for the first real test

# ─── Tests at increasing bitrates ─────────────────────────────────────────────
run_udp_test "UDP-1Mbps   (uplink)"  "1M"
run_udp_test "UDP-5Mbps   (uplink)"  "5M"
run_udp_test "UDP-10Mbps  (uplink)"  "10M"
run_udp_test "UDP-20Mbps  (uplink)"  "20M"
run_udp_test "UDP-50Mbps  (uplink)"  "50M"    # Stress test — may show loss on 5G

# Downlink (cloud → edge)
run_udp_test "UDP-10Mbps  (downlink)" "10M" "-R"
run_udp_test "UDP-20Mbps  (downlink)" "20M" "-R"

# Small packet size (VoIP simulation: 160B payload at 64kbps)
run_udp_test "UDP-VoIP    (64kbps, 160B pkt)" "64K" "-l 160"

# Large MTU packets (close to WireGuard MTU 1420)
run_udp_test "UDP-large-pkt (5Mbps, 1300B)" "5M" "-l 1300"

print_summary "02-udp-bandwidth"
