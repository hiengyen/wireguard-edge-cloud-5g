#!/usr/bin/env bash
# Test 05-B: Failover scenario — monitoring continuity during WireGuard reconnect
# Measures whether Prometheus/Loki gap fills correctly after link recovery
# Requires: iperf3 running in background + monitoring stack reachable
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

section "05-B  Failover & Recovery Scenario"
detect_wwan

MAX_MONITORING_GAP_S="${MAX_MONITORING_GAP_S:-120}"  # max acceptable monitoring gap
DISRUPTION_S="${DISRUPTION_S:-15}"                   # seconds to keep overlay down

if [[ $EUID -ne 0 ]]; then
    fail "This test requires root (sudo $0)"
    exit 1
fi

# ─── Pre-condition: everything must be up ─────────────────────────────────────
log "Verifying pre-conditions"

all_ok=true
ping -c 2 -W 3 "$WG_SERVER_IP" &>/dev/null || { fail "WireGuard overlay not reachable — cannot run failover test"; all_ok=false; }
curl -sf --max-time 5 "${PROMETHEUS_URL}/-/healthy" &>/dev/null || { fail "Prometheus not reachable"; all_ok=false; }
curl -sf --max-time 5 "${LOKI_URL}/ready"          &>/dev/null || { fail "Loki not reachable"; all_ok=false; }

if ! $all_ok; then
    print_summary "05-failover"; exit 1
fi
pass "Pre-conditions met"

# ─── Step 1: Record baseline metric timestamp ─────────────────────────────────
log "Recording Prometheus baseline"
t_before=$(date +%s)
up_before=$(curl -sf --max-time 5 "${PROMETHEUS_URL}/api/v1/query?query=up" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('data',{}).get('result',[])))" 2>/dev/null || echo "0")
info "Prometheus series before disruption: ${up_before}"

# ─── Step 2: Disrupt the WireGuard overlay ────────────────────────────────────
t_disrupt=$(date +%s)
log "Disrupting WireGuard overlay for ${DISRUPTION_S}s"
wg_pub_key=$(sudo wg show "$WG_INTERFACE" peers | head -1)
if [[ -n "$wg_pub_key" ]]; then
    sudo wg set "$WG_INTERFACE" peer "$wg_pub_key" remove 2>/dev/null || true
    pass "WireGuard peer removed (simulating disconnection)"
else
    # Fallback: take down wg interface
    ip link set "$WG_INTERFACE" down
    warn "Fell back to taking ${WG_INTERFACE} down (no peer found)"
fi

# Verify overlay is down
if ! ping -c 1 -W 2 "$WG_SERVER_IP" &>/dev/null; then
    pass "Overlay confirmed DOWN"
else
    warn "Overlay still reachable — disruption may not have worked"
fi

# Wait during disruption
log "Waiting ${DISRUPTION_S}s during disruption..."
sleep "$DISRUPTION_S"

# ─── Step 3: Restore WireGuard ────────────────────────────────────────────────
log "Restoring WireGuard connection"
if [[ -n "$wg_pub_key" ]]; then
    # Re-read config and add peer back
    sudo wg addconf "$WG_INTERFACE" <(sudo wg showconf "$WG_INTERFACE" 2>/dev/null) 2>/dev/null || true
    # Restart WireGuard fully
    sudo wg-quick down "$WG_INTERFACE" 2>/dev/null || true
    sleep 1
    sudo wg-quick up "$WG_INTERFACE" 2>/dev/null || { ip link set "$WG_INTERFACE" up; }
else
    ip link set "$WG_INTERFACE" up
fi

# ─── Step 4: Measure recovery time ────────────────────────────────────────────
log "Waiting for WireGuard overlay to recover..."
t_recovery_start=$(date +%s)
recovered=false
deadline=$(( t_recovery_start + 90 ))

while (( $(date +%s) < deadline )); do
    if ping -c 1 -W 2 "$WG_SERVER_IP" &>/dev/null; then
        t_recovery_end=$(date +%s)
        elapsed=$(( t_recovery_end - t_recovery_start ))
        pass "Overlay recovered in ${elapsed}s after restore"
        recovered=true
        break
    fi
    sleep 2
done

$recovered || fail "Overlay did not recover within 90s — manual intervention required"

# ─── Step 5: Check Prometheus continuity ──────────────────────────────────────
log "Checking Prometheus metrics continuity after recovery"
sleep 20  # allow one scrape cycle

up_after=$(curl -sf --max-time 10 "${PROMETHEUS_URL}/api/v1/query?query=up" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('data',{}).get('result',[])))" 2>/dev/null || echo "0")

if (( up_after >= up_before )); then
    pass "Prometheus series restored: ${up_after} (was ${up_before} before)"
else
    warn "Prometheus series after recovery: ${up_after} < before: ${up_before}"
fi

# ─── Step 6: Check expected scrape gap ────────────────────────────────────────
t_now=$(date +%s)
gap_s=$(( t_now - t_disrupt ))
info "Total disruption + recovery window: ${gap_s}s"
(( gap_s <= MAX_MONITORING_GAP_S )) \
    && pass "Monitoring gap within threshold (${gap_s}s <= ${MAX_MONITORING_GAP_S}s)" \
    || warn "Monitoring gap ${gap_s}s exceeds threshold ${MAX_MONITORING_GAP_S}s"

# ─── Step 7: Loki log continuity ──────────────────────────────────────────────
log "Checking Loki log stream resumed after recovery"
QUERY=$(python3 -c "import urllib.parse; print(urllib.parse.quote('{job=\"edge-journal\"}'))" 2>/dev/null || echo "")
if [[ -n "$QUERY" ]]; then
    recent_logs=$(curl -sf --max-time 10 \
        "${LOKI_URL}/loki/api/v1/query_range?query=${QUERY}&limit=5&start=$(( $(date +%s) - 120 ))&end=$(date +%s)" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(sum(len(s.get('values',[])) for s in d.get('data',{}).get('result',[])))" 2>/dev/null || echo "0")
    (( recent_logs > 0 )) \
        && pass "Loki: ${recent_logs} recent edge-journal log lines after recovery" \
        || warn "Loki: no recent edge-journal lines — Alloy may need time to resume"
fi

print_summary "05-failover"
