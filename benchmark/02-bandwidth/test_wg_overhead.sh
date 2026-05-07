#!/usr/bin/env bash
# Test 02-D: Measure WireGuard encryption overhead vs raw 5G throughput
# Compares iperf3 throughput: direct 5G (to cloud public IP) vs WireGuard overlay
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

section "02-D  WireGuard Encryption Overhead"
require_cmd iperf3 bc

DURATION="${IPERF3_DURATION:-10}"

if [[ -z "$CLOUD_PUBLIC_IP" ]]; then
    warn "CLOUD_PUBLIC_IP not set — skipping direct vs VPN comparison"
    info "Set: export CLOUD_PUBLIC_IP=<ec2-public-ip> to enable this test"
    print_summary "02-wg-overhead"; exit 0
fi

measure_mbps() {
    local host="$1" port="$2" label="$3"
    log "Measuring ${label}: iperf3 to ${host}:${port}"
    local result
    result=$(iperf3 -c "$host" -p "$port" -t "$DURATION" -J 2>/dev/null)
    if [[ -z "$result" ]]; then
        echo "0"
        return
    fi
    echo "$result" | python3 -c "
import sys, json
d = json.load(sys.stdin)
bps = d.get('end',{}).get('sum_received',{}).get('bits_per_second', 0)
print(f'{bps/1e6:.2f}')
" 2>/dev/null || echo "0"
}

# 1. Baseline: raw 5G throughput to cloud public IP
mbps_raw=$(measure_mbps "$CLOUD_PUBLIC_IP" "$IPERF3_PORT" "raw 5G (public IP)")
info "Raw 5G throughput:        ${mbps_raw} Mbps"

# 2. WireGuard overlay throughput (same EC2 instance, via wg0)
mbps_wg=$(measure_mbps "$WG_SERVER_IP" "$IPERF3_PORT" "WireGuard overlay")
info "WireGuard overlay:        ${mbps_wg} Mbps"

# 3. Calculate overhead
if (( $(echo "$mbps_raw > 0" | bc -l) )) && (( $(echo "$mbps_wg > 0" | bc -l) )); then
    overhead_pct=$(echo "scale=2; (($mbps_raw - $mbps_wg) / $mbps_raw) * 100" | bc)
    info "WireGuard overhead:       ${overhead_pct}%"

    # WireGuard adds ~60B header per packet; overhead should be < 5% at high bitrates
    (( $(echo "$overhead_pct < 15" | bc -l) )) \
        && pass "WireGuard overhead ${overhead_pct}% (acceptable < 15%)" \
        || warn "WireGuard overhead ${overhead_pct}% is high — check CPU, MTU, or AES-NI support"
fi

# 4. CPU usage during WireGuard transfer (proxy for encryption cost)
log "Measuring CPU during WireGuard transfer"
(iperf3 -c "$WG_SERVER_IP" -p "$IPERF3_PORT" -t "$DURATION" &>/dev/null) &
IPERF3_PID=$!
sleep 2
cpu_line=$(top -bn1 | grep -E '^%Cpu' | head -1)
wait $IPERF3_PID || true
info "CPU snapshot during transfer: ${cpu_line}"

# 5. Check for AES-NI hardware acceleration
if grep -q aes /proc/cpuinfo 2>/dev/null; then
    pass "AES-NI hardware acceleration: present"
else
    warn "AES-NI not detected — WireGuard uses ChaCha20 (still fast, but verify)"
fi

# 6. Check WireGuard uses NEON/ChaCha20 on ARM
if uname -m | grep -qE 'aarch64|armv'; then
    info "ARM architecture: WireGuard uses ChaCha20-Poly1305 (hardware-optimized on ARMv8)"
fi

print_summary "02-wg-overhead"
