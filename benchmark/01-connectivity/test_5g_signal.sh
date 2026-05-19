#!/usr/bin/env bash
# Test 01-C: 5G modem signal quality and connection state
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

section "01-C  5G Signal Quality"
detect_wwan
require_cmd qmicli ip

MIN_RSRP="${MIN_RSRP:--110}"    # dBm: acceptable LTE/5G RSRP (good = > -80)
MIN_RSRQ="${MIN_RSRQ:--20}"     # dB:  acceptable LTE/5G RSRQ (good = > -10)

# 1. WWAN interface detection
if [[ -z "$WWAN_INTERFACE" ]]; then
    fail "No WWAN interface found (expected ww*) — is the modem connected?"
    print_summary "01-5g-signal"; exit 1
fi
pass "WWAN interface found: ${WWAN_INTERFACE}"

# 2. Interface is UP and has IP
if ip addr show "$WWAN_INTERFACE" | grep -q 'inet '; then
    wwan_ip=$(ip addr show "$WWAN_INTERFACE" | awk '/inet /{print $2}')
    pass "WWAN interface has IP: ${wwan_ip}"
else
    fail "WWAN interface ${WWAN_INTERFACE} has no IP — QMI session may not be active"
fi

# 3. QMI device
QMI_DEVICE="${QMI_DEVICE:-}"
if [[ -z "$QMI_DEVICE" ]]; then
    QMI_DEVICE=$(ls /dev/cdc-wdm* 2>/dev/null | head -1)
fi

if [[ -z "$QMI_DEVICE" ]]; then
    warn "QMI device /dev/cdc-wdm* not found — skipping signal quality checks"
    info "Signal checks require qmicli and a Quectel modem in QMI mode"
else
    pass "QMI device: ${QMI_DEVICE}"

    # 4. Network registration state
    log "Checking network registration"
    reg_info=$(sudo qmicli -d "$QMI_DEVICE" --nas-get-serving-system 2>/dev/null || true)
    if [[ -n "$reg_info" ]]; then
        reg_state=$(echo "$reg_info" | grep -i 'Registration state' | awk -F"'" '{print $2}')
        network=$(echo  "$reg_info" | grep -i 'Description'         | awk -F"'" '{print $2}')
        rat=$(echo      "$reg_info" | grep -i 'Radio interface'      | awk -F"'" '{print $2}' | head -1)

        info "Operator: ${network:-unknown}  RAT: ${rat:-unknown}  State: ${reg_state:-unknown}"
        if [[ "${reg_state,,}" == "registered" ]]; then
            pass "Network registration: registered (${rat:-?})"
        else
            fail "Network registration: ${reg_state} (expected 'registered')"
        fi
    else
        warn "Could not query serving system — check QMI permissions (may need sudo)"
    fi

    # 5. Signal strength (LTE/5G RSRP/RSRQ)
    log "Querying signal strength"
    sig_info=$(sudo qmicli -d "$QMI_DEVICE" --nas-get-signal-info 2>/dev/null || true)
    if [[ -n "$sig_info" ]]; then
        echo "$sig_info" | sed 's/^/    /'

        rsrp=$(echo "$sig_info" | grep -i 'RSRP' | grep -oE '\-?[0-9]+' | head -1)
        rsrq=$(echo "$sig_info" | grep -i 'RSRQ' | grep -oE '\-?[0-9]+' | head -1)
        snr=$(echo  "$sig_info" | grep -i 'SNR'  | grep -oE '\-?[0-9]+' | head -1)

        if [[ -n "$rsrp" ]]; then
            (( rsrp >= MIN_RSRP )) && pass "RSRP=${rsrp}dBm (threshold=${MIN_RSRP}dBm)" \
                                    || warn "RSRP=${rsrp}dBm is below threshold ${MIN_RSRP}dBm — weak signal"
        fi
        if [[ -n "$rsrq" ]]; then
            (( rsrq >= MIN_RSRQ )) && pass "RSRQ=${rsrq}dB (threshold=${MIN_RSRQ}dB)" \
                                    || warn "RSRQ=${rsrq}dB is below threshold ${MIN_RSRQ}dB"
        fi
        [[ -n "$snr"  ]] && info "SNR=${snr}dB"
    else
        warn "Could not query signal info from QMI device"
    fi

    # 6. Data connection stats
    log "Querying data session stats"
    ds_info=$(sudo qmicli -d "$QMI_DEVICE" --wds-get-packet-statistics 2>/dev/null || true)
    if [[ -n "$ds_info" ]]; then
        tx=$(echo "$ds_info" | grep -i 'TX bytes' | grep -oE '[0-9]+')
        rx=$(echo "$ds_info" | grep -i 'RX bytes' | grep -oE '[0-9]+')
        info "Data session: TX=${tx:-?}B RX=${rx:-?}B"
        (( ${tx:-0} > 0 || ${rx:-0} > 0 )) && pass "Data session is active (bytes flowing)" \
                                              || warn "No bytes counted in data session"
    fi
fi

# 7. DNS resolution via 5G uplink
log "Testing DNS resolution via 5G"
if ping -c 1 -W 3 google.com &>/dev/null; then
    pass "DNS resolution working"
else
    fail "DNS resolution failed over 5G uplink"
fi

print_summary "01-5g-signal"
