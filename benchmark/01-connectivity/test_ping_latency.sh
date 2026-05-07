#!/usr/bin/env bash
# Test 01-A: ICMP ping latency over WireGuard overlay and 5G uplink
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

section "01-A  Ping Latency Tests"
detect_wwan

# ─── Thresholds ────────────────────────────────────────────────────────────────
MAX_RTT_MS="${MAX_RTT_MS:-150}"        # max acceptable avg RTT (ms) over WireGuard
MAX_LOSS_PCT="${MAX_LOSS_PCT:-5}"      # max acceptable packet loss (%)
MAX_JITTER_MS="${MAX_JITTER_MS:-30}"   # max acceptable jitter (ms)

run_ping() {
    local label="$1" host="$2" count="${3:-$PING_COUNT}" interval="${4:-$PING_INTERVAL}"
    local raw
    if ! raw=$(ping -c "$count" -i "$interval" "$host" 2>&1); then
        fail "${label}: host unreachable (${host})"
        return 1
    fi

    # Parse: min/avg/max/mdev from summary line
    local stats; stats=$(echo "$raw" | grep -E 'min/avg/max' | awk -F'/' '{print $4, $5, $6, $7}')
    local min avg max mdev
    read -r min avg max mdev <<< "$stats"

    # Packet loss
    local loss; loss=$(echo "$raw" | grep -oE '[0-9]+(\.[0-9]+)? ?% packet loss' | grep -oE '[0-9]+(\.[0-9]+)?')

    info "${label} → ${host}  min=${min}ms avg=${avg}ms max=${max}ms jitter=${mdev}ms loss=${loss}%"

    local ok=true
    (( $(echo "$avg > $MAX_RTT_MS"   | bc -l) )) && { warn "${label}: avg RTT ${avg}ms exceeds threshold ${MAX_RTT_MS}ms"; ok=false; }
    (( $(echo "$loss > $MAX_LOSS_PCT" | bc -l) )) && { fail "${label}: packet loss ${loss}% exceeds threshold ${MAX_LOSS_PCT}%"; ok=false; }
    (( $(echo "$mdev > $MAX_JITTER_MS"| bc -l) )) && { warn "${label}: jitter ${mdev}ms exceeds threshold ${MAX_JITTER_MS}ms"; ok=false; }

    $ok && pass "${label}: RTT=${avg}ms loss=${loss}% jitter=${mdev}ms"
}

# 1. Ping WireGuard gateway (overlay hop)
log "Pinging WireGuard gateway: ${WG_SERVER_IP}"
run_ping "WG-overlay → cloud-gateway" "$WG_SERVER_IP"

# 2. Ping internet via 5G uplink (raw 5G latency, bypasses VPN)
log "Pinging Google DNS via 5G uplink: 8.8.8.8"
run_ping "5G-uplink → 8.8.8.8" "8.8.8.8" 10 0.5

# 3. Ping internet via WireGuard (VPN + NAT overhead)
if [[ -n "${WG_ALLOWED_INTERNET:-}" ]]; then
    log "Pinging 8.8.8.8 through WireGuard (AllowedIPs=0.0.0.0/0)"
    run_ping "WG-tunnel → internet" "8.8.8.8" 10 0.5
else
    info "Skipping internet-via-WireGuard test (set WG_ALLOWED_INTERNET=1 to enable)"
fi

# 4. Large packet ping to detect MTU issues (WireGuard default MTU 1420)
log "Large packet ping to detect MTU fragmentation"
if ping -c 5 -s 1300 -M do "$WG_SERVER_IP" &>/dev/null; then
    pass "MTU-1300: no fragmentation over WireGuard tunnel"
else
    warn "MTU-1300: fragmentation or drop detected — check WireGuard MTU setting"
fi

# 5. WWAN interface latency baseline (if 5G is up)
if [[ -n "$WWAN_INTERFACE" ]]; then
    local_gw=$(ip route show dev "$WWAN_INTERFACE" 2>/dev/null | awk '/default/{print $3; exit}')
    if [[ -n "$local_gw" ]]; then
        log "Pinging 5G local gateway: ${local_gw}"
        run_ping "5G-local-gateway" "$local_gw" 5 0.2
    fi
else
    warn "WWAN interface not found — skipping 5G local gateway ping"
fi

print_summary "01-ping-latency"
