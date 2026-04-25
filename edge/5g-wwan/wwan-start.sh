#!/bin/bash

set -Eeuo pipefail

APN="${WWAN_APN:-internet}"
DEVICE_WAIT_TIMEOUT="${WWAN_DEVICE_WAIT_TIMEOUT:-45}"
QMI_START_RETRIES="${WWAN_QMI_START_RETRIES:-3}"
QMI_START_RETRY_DELAY="${WWAN_QMI_START_RETRY_DELAY:-5}"
DHCP_RETRIES="${WWAN_DHCP_RETRIES:-3}"
DHCP_RETRY_DELAY="${WWAN_DHCP_RETRY_DELAY:-5}"
CONNECTIVITY_TARGET="${WWAN_CONNECTIVITY_TARGET:-8.8.8.8}"

log_info() {
    echo "[INFO] $*"
}

log_warning() {
    echo "[WARNING] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_success() {
    echo "[SUCCESS] $*"
}

fail() {
    log_error "$*"
    exit 1
}

trap 'rc=$?; log_error "WWAN startup failed at line ${BASH_LINENO[0]} with exit code ${rc}."; exit "${rc}"' ERR

find_wwan_interface() {
    local path
    for path in /sys/class/net/ww*; do
        [[ -e "$path" ]] || continue
        basename "$path"
        return 0
    done
    return 1
}

find_qmi_device() {
    local path
    for path in /dev/cdc-wdm*; do
        [[ -c "$path" ]] || continue
        printf '%s\n' "$path"
        return 0
    done
    return 1
}

wait_for_resource() {
    local description="$1"
    local timeout="$2"
    local finder="$3"
    local value=""
    local attempt

    for ((attempt = 1; attempt <= timeout; attempt++)); do
        if value="$("$finder")"; then
            printf '%s\n' "$value"
            return 0
        fi

        if (( attempt == 1 || attempt % 5 == 0 )); then
            log_info "Waiting for ${description} (${attempt}/${timeout})..." >&2
        fi
        sleep 1
    done

    return 1
}

bring_interface_up() {
    local attempt

    for ((attempt = 1; attempt <= QMI_START_RETRIES; attempt++)); do
        if ip link set "$INTERFACE" up; then
            return 0
        fi

        log_warning "Failed to bring ${INTERFACE} up (attempt ${attempt}/${QMI_START_RETRIES})."
        if (( attempt < QMI_START_RETRIES )); then
            sleep "$QMI_START_RETRY_DELAY"
        fi
    done

    return 1
}

start_qmi_session() {
    local attempt
    local output=""
    local rc=0

    for ((attempt = 1; attempt <= QMI_START_RETRIES; attempt++)); do
        if output=$(qmicli -d "$DEVICE" \
            --wds-start-network="apn=${APN},ip-type=4" \
            --client-no-release-cid 2>&1); then
            QMI_RESULT="$output"
            return 0
        fi

        rc=$?
        log_warning "QMI start attempt ${attempt}/${QMI_START_RETRIES} failed (exit ${rc})."
        while IFS= read -r line; do
            [[ -n "$line" ]] && log_warning "qmicli: ${line}"
        done <<< "$output"

        if (( attempt < QMI_START_RETRIES )); then
            sleep "$QMI_START_RETRY_DELAY"
        fi
    done

    return 1
}

request_dhcp_lease() {
    local attempt

    for ((attempt = 1; attempt <= DHCP_RETRIES; attempt++)); do
        if udhcpc -n -t 5 -T 3 -i "$INTERFACE"; then
            return 0
        fi

        log_warning "DHCP attempt ${attempt}/${DHCP_RETRIES} failed on ${INTERFACE}."
        if (( attempt < DHCP_RETRIES )); then
            sleep "$DHCP_RETRY_DELAY"
        fi
    done

    return 1
}

get_ipv4_addr() {
    ip -4 -o addr show dev "$INTERFACE" scope global 2>/dev/null | awk '{print $4; exit}' || true
}

echo "======================================"
echo "   5G QMI Network Initialization"
echo "======================================"

if [[ $EUID -ne 0 ]]; then
    fail "This script must be run as root. Please use sudo."
fi

INTERFACE=$(wait_for_resource "WWAN interface (ww*)" "$DEVICE_WAIT_TIMEOUT" find_wwan_interface) \
    || fail "No WWAN network interface (ww*) found after ${DEVICE_WAIT_TIMEOUT}s."
log_info "Detected interface: ${INTERFACE}"

DEVICE=$(wait_for_resource "QMI device (/dev/cdc-wdm*)" "$DEVICE_WAIT_TIMEOUT" find_qmi_device) \
    || fail "No QMI device (/dev/cdc-wdm*) found after ${DEVICE_WAIT_TIMEOUT}s."
log_info "Detected QMI device: ${DEVICE}"

RAW_IP_PATH="/sys/class/net/${INTERFACE}/qmi/raw_ip"
if [[ -f "$RAW_IP_PATH" ]]; then
    log_info "Enabling Raw-IP mode on ${INTERFACE}..."
    if ! printf 'Y' > "$RAW_IP_PATH"; then
        log_warning "Unable to set Raw-IP mode at ${RAW_IP_PATH}. Continuing."
    fi
else
    log_warning "Raw-IP configuration file not found at ${RAW_IP_PATH}"
fi

log_info "Bringing interface ${INTERFACE} up..."
bring_interface_up || fail "Unable to bring interface ${INTERFACE} up."

log_info "Starting QMI data session on device ${DEVICE}..."
QMI_RESULT=""
start_qmi_session || fail "Unable to establish QMI data session after ${QMI_START_RETRIES} attempts."
log_success "QMI data session established successfully."
echo "$QMI_RESULT" | grep -i "CID" || true

log_info "Requesting IP address via DHCP..."
request_dhcp_lease || fail "Unable to obtain DHCP lease on ${INTERFACE}."

IPV4_ADDR="$(get_ipv4_addr)"
if [[ -n "$IPV4_ADDR" ]]; then
    log_success "Assigned IPv4 address: ${IPV4_ADDR}"
else
    log_warning "DHCP completed but no IPv4 address is visible on ${INTERFACE} yet."
fi

echo "======================================"
echo "   Setup Complete - Testing Connectivity"
echo "======================================"

if ping -c 3 -W 5 "$CONNECTIVITY_TARGET" >/dev/null 2>&1; then
    log_success "Connectivity check to ${CONNECTIVITY_TARGET} passed."
else
    log_warning "Connectivity check to ${CONNECTIVITY_TARGET} failed. The monitor service can retry recovery."
fi

echo "[DONE] Network initialization process completed."
