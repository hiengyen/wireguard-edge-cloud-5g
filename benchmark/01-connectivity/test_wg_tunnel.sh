#!/usr/bin/env bash
# Test 01-B: WireGuard tunnel health and handshake verification
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

section "01-B  WireGuard Tunnel Health"

MAX_HANDSHAKE_AGE="${MAX_HANDSHAKE_AGE:-180}"   # seconds; PersistentKeepalive=25s so fresh handshakes expected

# 1. Check WireGuard interface exists and is UP
log "Checking WireGuard interface: ${WG_INTERFACE}"
if ip link show "$WG_INTERFACE" &>/dev/null; then
    state=$(ip link show "$WG_INTERFACE" | grep -oE 'state [A-Z]+' | awk '{print $2}')
    pass "Interface ${WG_INTERFACE} exists (state=${state})"
else
    fail "Interface ${WG_INTERFACE} not found — WireGuard may not be running"
    print_summary "01-wg-tunnel"; exit 1
fi

# 2. Check wg-tools are present
if ! command -v wg &>/dev/null; then
    fail "'wg' command not found — install wireguard-tools"
    print_summary "01-wg-tunnel"; exit 1
fi

# 3. Peer count
peer_count=$(sudo wg show "$WG_INTERFACE" peers 2>/dev/null | wc -l)
if (( peer_count > 0 )); then
    pass "Peers configured: ${peer_count}"
else
    fail "No peers found in ${WG_INTERFACE} — run setup-wg-client.sh first"
    print_summary "01-wg-tunnel"; exit 1
fi

# 4. Latest handshake age
log "Checking latest handshake timestamp for all peers"
while IFS= read -r peer; do
    [[ -z "$peer" ]] && continue
    hs=$(sudo wg show "$WG_INTERFACE" latest-handshakes 2>/dev/null | grep "$peer" | awk '{print $2}')
    if [[ -z "$hs" || "$hs" == "0" ]]; then
        fail "Peer ${peer:0:16}…: no handshake yet"
        continue
    fi
    now=$(date +%s)
    age=$(( now - hs ))
    if (( age <= MAX_HANDSHAKE_AGE )); then
        pass "Peer ${peer:0:16}…: last handshake ${age}s ago (OK)"
    else
        fail "Peer ${peer:0:16}…: last handshake ${age}s ago (stale, threshold=${MAX_HANDSHAKE_AGE}s)"
    fi
done < <(sudo wg show "$WG_INTERFACE" peers 2>/dev/null)

# 5. Transfer counters (non-zero = traffic is flowing)
log "Checking transfer byte counters"
transfer_line=$(sudo wg show "$WG_INTERFACE" transfer 2>/dev/null | head -1)
if [[ -n "$transfer_line" ]]; then
    rx=$(echo "$transfer_line" | awk '{print $2}')
    tx=$(echo "$transfer_line" | awk '{print $3}')
    if (( rx > 0 && tx > 0 )); then
        pass "Traffic flowing: RX=${rx}B TX=${tx}B"
    elif (( rx > 0 || tx > 0 )); then
        warn "One-way traffic only: RX=${rx}B TX=${tx}B"
    else
        warn "No traffic counted yet on ${WG_INTERFACE}"
    fi
fi

# 6. Allowed-IPs coverage
log "Checking allowed-IPs configuration"
allowed=$(sudo wg show "$WG_INTERFACE" allowed-ips 2>/dev/null)
if echo "$allowed" | grep -qE '^[A-Za-z0-9+/=]+ +[0-9./,]+$'; then
    pass "Allowed-IPs entries present"
else
    warn "Could not parse allowed-IPs — verify manually: sudo wg show ${WG_INTERFACE}"
fi

# 7. Endpoint reachability via overlay
log "Verifying overlay IP reachability: ${WG_SERVER_IP}"
if ping -c 3 -W 3 "$WG_SERVER_IP" &>/dev/null; then
    pass "Overlay IP ${WG_SERVER_IP} is reachable"
else
    fail "Overlay IP ${WG_SERVER_IP} unreachable — tunnel may be down"
fi

# 8. Show full wg status for info
log "Current WireGuard status:"
sudo wg show "$WG_INTERFACE" 2>/dev/null | sed 's/^/    /'

print_summary "01-wg-tunnel"
