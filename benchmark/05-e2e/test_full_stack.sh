#!/usr/bin/env bash
# Test 05-A: Full end-to-end stack validation
# Validates the complete data path: 5G → WireGuard → Monitoring → Grafana
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

section "05-A  Full Stack End-to-End Test"
require_cmd curl ping

# ─── Phase 1: Physical connectivity ──────────────────────────────────────────
log "[Phase 1] Physical & network connectivity"
detect_wwan

if [[ -n "$WWAN_INTERFACE" ]]; then
    if ip addr show "$WWAN_INTERFACE" | grep -q 'inet '; then
        wwan_ip=$(ip addr show "$WWAN_INTERFACE" | awk '/inet /{print $2}')
        pass "P1: 5G WWAN connected (${WWAN_INTERFACE} = ${wwan_ip})"
    else
        fail "P1: 5G WWAN interface has no IP — check modem connection"
    fi
else
    warn "P1: No WWAN interface detected — skipping 5G checks"
fi

# ─── Phase 2: WireGuard overlay ───────────────────────────────────────────────
log "[Phase 2] WireGuard overlay"

if ip link show "$WG_INTERFACE" &>/dev/null; then
    pass "P2: WireGuard interface ${WG_INTERFACE} exists"
else
    fail "P2: WireGuard interface ${WG_INTERFACE} not found"
    print_summary "05-full-stack"; exit 1
fi

if ping -c 3 -W 3 "$WG_SERVER_IP" &>/dev/null; then
    rtt=$(ping -c 3 -W 3 "$WG_SERVER_IP" 2>/dev/null | grep -oE 'avg.*ms' | grep -oE '[0-9]+\.[0-9]+' | head -2 | tail -1)
    pass "P2: Overlay reachable → ${WG_SERVER_IP} (avg RTT=${rtt}ms)"
else
    fail "P2: Cannot reach WireGuard server ${WG_SERVER_IP}"
    print_summary "05-full-stack"; exit 1
fi

# Handshake freshness
hs=$(sudo wg show "$WG_INTERFACE" latest-handshakes 2>/dev/null | awk 'NR==1{print $2}')
if [[ -n "$hs" && "$hs" != "0" ]]; then
    age=$(( $(date +%s) - hs ))
    (( age <= 180 )) && pass "P2: WireGuard handshake fresh (${age}s ago)" \
                      || warn "P2: Handshake stale (${age}s ago)"
fi

# ─── Phase 3: Monitoring services ─────────────────────────────────────────────
log "[Phase 3] Monitoring services"

check_service() {
    local name="$1" url="$2" auth="${3:-}"
    local args=(-sf --max-time "$HTTP_TIMEOUT")
    [[ -n "$auth" ]] && args+=(-u "$auth")
    if curl "${args[@]}" "$url" &>/dev/null; then
        pass "P3: ${name} is UP"
    else
        fail "P3: ${name} is DOWN at ${url}"
    fi
}

check_service "Prometheus"      "${PROMETHEUS_URL}/-/healthy"
check_service "Loki"            "${LOKI_URL}/ready"
check_service "Grafana"         "${GRAFANA_URL}/api/health"        "admin:${GRAFANA_ADMIN_PASSWORD}"
check_service "Node-Exporter (cloud)" "${NODE_EXPORTER_CLOUD}/metrics"
check_service "Node-Exporter (edge)"  "${NODE_EXPORTER_EDGE}/metrics"

# ─── Phase 4: Metrics pipeline ─────────────────────────────────────────────────
log "[Phase 4] Metrics pipeline (Prometheus → edge scrape)"

edge_up=$(curl -sf --max-time "$HTTP_TIMEOUT" \
    "${PROMETHEUS_URL}/api/v1/query?query=up{job%3D%22edge-node%22}" 2>/dev/null | \
    python3 -c "
import sys, json
d = json.load(sys.stdin)
results = d.get('data',{}).get('result',[])
print(results[0]['value'][1] if results else '?')
" 2>/dev/null || echo "?")

if [[ "$edge_up" == "1" ]]; then
    pass "P4: Edge node scrape target is UP in Prometheus"
elif [[ "$edge_up" == "0" ]]; then
    fail "P4: Edge node scrape target is DOWN in Prometheus (check prometheus.yml endpoint)"
else
    warn "P4: Edge node scrape target not found in Prometheus — update prometheus.yml with correct IP"
fi

# ─── Phase 5: Log pipeline ─────────────────────────────────────────────────────
log "[Phase 5] Log pipeline (edge → Alloy → Loki)"

log_label=$(python3 -c "import urllib.parse; print(urllib.parse.quote('{job=\"edge-journal\"}'))" 2>/dev/null || echo "")
if [[ -n "$log_label" ]]; then
    log_result=$(curl -sf --max-time "$HTTP_TIMEOUT" \
        "${LOKI_URL}/loki/api/v1/query?query=${log_label}&limit=1" 2>/dev/null | \
        python3 -c "
import sys, json
d = json.load(sys.stdin)
print(len(d.get('data',{}).get('result',[])))
" 2>/dev/null || echo "0")

    (( log_result > 0 )) \
        && pass "P5: edge-journal logs present in Loki" \
        || warn "P5: No edge-journal logs in Loki — check Grafana Alloy on edge node"
fi

# ─── Phase 6: Bandwidth baseline ───────────────────────────────────────────────
log "[Phase 6] Quick bandwidth baseline"

if command -v iperf3 &>/dev/null && iperf3 -c "$IPERF3_SERVER" -p "$IPERF3_PORT" -t 1 -J &>/dev/null; then
    mbps=$(iperf3 -c "$IPERF3_SERVER" -p "$IPERF3_PORT" -t 5 -J 2>/dev/null | \
        python3 -c "
import sys, json
d = json.load(sys.stdin)
bps = d.get('end',{}).get('sum_received',{}).get('bits_per_second', 0)
print(f'{bps/1e6:.1f}')
" 2>/dev/null || echo "0")
    info "P6: WireGuard bandwidth = ${mbps} Mbps"
    (( $(echo "$mbps > 1" | bc -l) )) && pass "P6: Bandwidth OK (${mbps} Mbps)" \
                                        || warn "P6: Low bandwidth (${mbps} Mbps)"
else
    info "P6: iperf3 not available or server not running — skipping bandwidth check"
fi

# ─── Phase 7: SSH over WireGuard overlay ───────────────────────────────────────
log "[Phase 7] SSH connectivity over overlay"
SSH_USER="${SSH_USER:-ec2-user}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa}"

if [[ -f "$SSH_KEY" ]]; then
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=5 "${SSH_USER}@${WG_SERVER_IP}" "echo ok" &>/dev/null; then
        pass "P7: SSH to cloud gateway over WireGuard overlay: OK"
    else
        warn "P7: SSH to ${WG_SERVER_IP} failed — check SSH key and port"
    fi
else
    info "P7: SSH key not found at ${SSH_KEY} — skipping SSH test"
fi

print_summary "05-full-stack"
