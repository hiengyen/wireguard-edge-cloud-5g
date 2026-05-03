#!/bin/bash
# ==============================================================
# Remove the local Grafana Alloy service/configuration from edge.
# By default this keeps the installed package and removes local config.
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

REMOVE_ALLOY_PACKAGE="${REMOVE_ALLOY_PACKAGE:-false}"
REMOVE_ALLOY_CONFIG="${REMOVE_ALLOY_CONFIG:-true}"

if [[ $EUID -ne 0 ]]; then
  error "Run as root"
  exit 1
fi

header "Grafana Alloy Uninstall"

if systemctl list-unit-files | grep -q '^alloy\.service'; then
  log "Stopping Alloy if active..."
  systemctl stop alloy.service 2>/dev/null || true

  log "Disabling Alloy at boot..."
  systemctl disable alloy.service 2>/dev/null || true
else
  warn "alloy.service is not installed."
fi

if [[ "$REMOVE_ALLOY_CONFIG" == "true" ]]; then
  for file in /etc/alloy/config.alloy /etc/default/alloy /etc/sysconfig/alloy; do
    if [[ -f "$file" ]]; then
      log "Removing $file..."
      rm -f "$file"
    fi
  done
else
  warn "Keeping Alloy config. Set REMOVE_ALLOY_CONFIG=true to remove it."
fi

if [[ "$REMOVE_ALLOY_PACKAGE" == "true" ]]; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get remove -y alloy
  elif command -v dnf >/dev/null 2>&1; then
    dnf remove -y alloy
  else
    warn "Unsupported package manager; skipping package removal."
  fi
else
  warn "Keeping Alloy package. Set REMOVE_ALLOY_PACKAGE=true to uninstall it."
fi

systemctl daemon-reload
log "Grafana Alloy uninstall complete."
