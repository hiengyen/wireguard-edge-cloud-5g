#!/bin/bash
# ==============================================================
# WireGuard Client Uninstall Script - Edge
# Removes the local wg0 client configuration from the edge node.
# ==============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }
header() { echo -e "\n${CYAN}===== $* =====${NC}"; }

WG_INTERFACE="${WIREGUARD_INTERFACE:-wg0}"
WG_CONFIG="/etc/wireguard/${WG_INTERFACE}.conf"
WG_KEYS_DIR="/etc/wireguard/keys"
REMOVE_KEYS="${REMOVE_WG_KEYS:-false}"

if [[ $EUID -ne 0 ]]; then
  error "Run as root"
  exit 1
fi

header "WireGuard Client Uninstall"

bring_interface_down() {
  if ! command -v ip >/dev/null 2>&1; then
    warn "'ip' command not found. Skipping direct interface removal."
    return
  fi

  if ip link show "${WG_INTERFACE}" >/dev/null 2>&1; then
    log "Removing live interface ${WG_INTERFACE}..."
    ip link delete dev "${WG_INTERFACE}" 2>/dev/null || true
  else
    warn "Interface ${WG_INTERFACE} is not present."
  fi
}

if systemctl list-unit-files | grep -q "^wg-quick@${WG_INTERFACE}\.service"; then
  log "Stopping wg-quick@${WG_INTERFACE} if it is active..."
  systemctl stop "wg-quick@${WG_INTERFACE}" 2>/dev/null || true

  log "Disabling wg-quick@${WG_INTERFACE} at boot..."
  systemctl disable "wg-quick@${WG_INTERFACE}" 2>/dev/null || true
else
  warn "wg-quick@${WG_INTERFACE}.service is not installed."
fi

bring_interface_down

if [[ -f "${WG_CONFIG}" ]]; then
  log "Removing client config ${WG_CONFIG}..."
  rm -f "${WG_CONFIG}"
else
  warn "Client config ${WG_CONFIG} does not exist."
fi

if [[ "${REMOVE_KEYS}" == "true" ]]; then
  if [[ -d "${WG_KEYS_DIR}" ]]; then
    log "Removing key directory ${WG_KEYS_DIR}..."
    rm -rf "${WG_KEYS_DIR}"
  else
    warn "Key directory ${WG_KEYS_DIR} does not exist."
  fi
else
  warn "Keeping ${WG_KEYS_DIR}. Set REMOVE_WG_KEYS=true to remove local client keys."
fi

if [[ -d /etc/wireguard ]] && [[ -z "$(find /etc/wireguard -mindepth 1 -maxdepth 1 2>/dev/null)" ]]; then
  log "/etc/wireguard is empty after cleanup."
fi

echo
warn "This script only removes the local edge client setup."
warn "If the peer was added on the cloud server, remove it there separately."
warn "Example on the cloud: sudo wg set ${WG_INTERFACE} peer <client-public-key> remove && sudo wg-quick save ${WG_INTERFACE}"

log "WireGuard client uninstall complete."
