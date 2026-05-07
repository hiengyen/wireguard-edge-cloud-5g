#!/usr/bin/env bash
# Test 04-C: WWAN reconnect and WireGuard tunnel recovery time
# Simulates 5G link instability by bouncing the WWAN interface
# WARNING: requires root — will briefly interrupt connectivity
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

section "04-C  WWAN Reconnect & Tunnel Recovery"
detect_wwan

if [[ $EUID -ne 0 ]]; then
    fail "This test requires root privileges (sudo $0)"
    exit 1
fi

if [[ -z "$WWAN_INTERFACE" ]]; then
    fail "No WWAN interface found — is the modem connected?"
    print_summary "04-wwan-reconnect"; exit 1
fi

MAX_RECONNECT_S="${MAX_RECONNECT_S:-30}"     # max seconds to re-establish WWAN
MAX_WG_RECOVERY_S="${MAX_WG_RECOVERY_S:-60}" # max seconds for WireGuard handshake after reconnect
TRIALS="${TRIALS:-3}"                        # number of reconnect trials

ping_ok() { ping -c 1 -W 2 "$WG_SERVER_IP" &>/dev/null; }

wait_for_wwan() {
    local deadline=$(( $(date +%s) + $1 ))
    while (( $(date +%s) < deadline )); do
        if ip addr show "$WWAN_INTERFACE" 2>/dev/null | grep -q 'inet '; then
            return 0
        fi
        sleep 1
    done
    return 1
}

wait_for_ping() {
    local host="$1" timeout="$2"
    local deadline=$(( $(date +%s) + timeout ))
    while (( $(date +%s) < deadline )); do
        ping -c 1 -W 2 "$host" &>/dev/null && return 0
        sleep 1
    done
    return 1
}

log "WWAN interface: ${WWAN_INTERFACE}"
log "WireGuard server: ${WG_SERVER_IP}"
log "Running ${TRIALS} reconnect trials"

RECONNECT_TIMES=()
WG_RECOVERY_TIMES=()

for trial in $(seq 1 "$TRIALS"); do
    log "─── Trial ${trial}/${TRIALS} ───"

    # Verify connectivity before disruption
    if ! ping_ok; then
        warn "WireGuard overlay not reachable before disruption — skipping trial ${trial}"
        continue
    fi
    pass "Trial ${trial}: Pre-condition OK (ping to ${WG_SERVER_IP} works)"

    # Note WireGuard TX bytes before
    wg_tx_before=$(sudo wg show "$WG_INTERFACE" transfer 2>/dev/null | awk 'NR==1{print $3}')

    # Disrupt: bring WWAN interface down
    t0=$(date +%s)
    log "Taking down ${WWAN_INTERFACE}..."
    ip link set "$WWAN_INTERFACE" down

    sleep 3  # ensure it's fully down

    # Restore: bring WWAN back up
    log "Bringing ${WWAN_INTERFACE} back up..."
    ip link set "$WWAN_INTERFACE" up

    # Restart WWAN service to re-trigger QMI session + DHCP
    if systemctl is-active --quiet wwan.service 2>/dev/null; then
        systemctl restart wwan.service
    fi

    # Measure time to regain WWAN IP
    t_wwan_start=$(date +%s)
    if wait_for_wwan "$MAX_RECONNECT_S"; then
        t_wwan_end=$(date +%s)
        wwan_elapsed=$(( t_wwan_end - t_wwan_start ))
        RECONNECT_TIMES+=("$wwan_elapsed")
        wwan_ip=$(ip addr show "$WWAN_INTERFACE" | awk '/inet /{print $2}')
        pass "Trial ${trial}: WWAN IP restored in ${wwan_elapsed}s (${wwan_ip})"
    else
        fail "Trial ${trial}: WWAN failed to get IP within ${MAX_RECONNECT_S}s"
        RECONNECT_TIMES+=(999)
        continue
    fi

    # Measure time to WireGuard overlay recovery
    t_wg_start=$(date +%s)
    if wait_for_ping "$WG_SERVER_IP" "$MAX_WG_RECOVERY_S"; then
        t_wg_end=$(date +%s)
        wg_elapsed=$(( t_wg_end - t_wg_start ))
        WG_RECOVERY_TIMES+=("$wg_elapsed")
        pass "Trial ${trial}: WireGuard overlay recovered in ${wg_elapsed}s after WWAN up"
    else
        fail "Trial ${trial}: WireGuard overlay did not recover within ${MAX_WG_RECOVERY_S}s"
        WG_RECOVERY_TIMES+=(999)
    fi

    # Check handshake freshness
    hs=$(sudo wg show "$WG_INTERFACE" latest-handshakes 2>/dev/null | awk 'NR==1{print $2}')
    now=$(date +%s)
    if [[ -n "$hs" && "$hs" != "0" ]]; then
        hs_age=$(( now - hs ))
        info "Trial ${trial}: handshake age after recovery = ${hs_age}s"
    fi

    sleep 5  # stabilize before next trial
done

# ─── Summary statistics ────────────────────────────────────────────────────────
if (( ${#RECONNECT_TIMES[@]} > 0 )); then
    mean_wwan=$(printf '%s\n' "${RECONNECT_TIMES[@]}" | awk '{s+=$1}END{printf "%.0f", s/NR}')
    max_wwan=$(printf '%s\n' "${RECONNECT_TIMES[@]}" | sort -n | tail -1)
    info "WWAN reconnect: mean=${mean_wwan}s max=${max_wwan}s (threshold=${MAX_RECONNECT_S}s)"
    (( max_wwan <= MAX_RECONNECT_S )) && pass "WWAN reconnect time acceptable (max=${max_wwan}s)" \
                                      || warn "WWAN reconnect exceeded threshold (max=${max_wwan}s)"
fi

if (( ${#WG_RECOVERY_TIMES[@]} > 0 )); then
    mean_wg=$(printf '%s\n' "${WG_RECOVERY_TIMES[@]}" | awk '{s+=$1}END{printf "%.0f", s/NR}')
    max_wg=$(printf '%s\n' "${WG_RECOVERY_TIMES[@]}" | sort -n | tail -1)
    info "WireGuard recovery: mean=${mean_wg}s max=${max_wg}s (threshold=${MAX_WG_RECOVERY_S}s)"
    (( max_wg <= MAX_WG_RECOVERY_S )) && pass "WireGuard recovery acceptable (max=${max_wg}s)" \
                                       || fail "WireGuard recovery exceeded threshold (max=${max_wg}s)"
fi

print_summary "04-wwan-reconnect"
