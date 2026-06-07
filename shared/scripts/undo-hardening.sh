#!/bin/bash
# ==============================================================
# Undo OS Hardening Script
# Supported targets:
# - Armbian / Debian-based edge nodes
# - Amazon Linux 2023 x86_64 cloud nodes
# ==============================================================

set -euo pipefail

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_BAK="/etc/ssh/sshd_config.bak"
FAIL2BAN_JAIL="/etc/fail2ban/jail.d/sshd.local"
OS_FAMILY=""

log() {
  echo "[INFO] $*"
}

error() {
  echo "[ERROR] $*" >&2
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root. Please use sudo."
    exit 1
  fi
}

detect_os() {
  if [[ ! -r /etc/os-release ]]; then
    error "Cannot detect operating system: /etc/os-release not found."
    exit 1
  fi

  source /etc/os-release

  case "${ID:-}" in
    amzn)
      OS_FAMILY="amzn2023"
      ;;
    armbian|debian|ubuntu)
      OS_FAMILY="debian"
      ;;
    *)
      if [[ " ${ID_LIKE:-} " == *" debian "* ]]; then
        OS_FAMILY="debian"
      else
        error "Unsupported OS: ${PRETTY_NAME:-unknown}."
        exit 1
      fi
      ;;
  esac

  log "Detected OS: ${PRETTY_NAME:-unknown}"
}

restore_ssh() {
  log "Restoring SSH configurations..."
  if [[ -f "$SSHD_CONFIG_BAK" ]]; then
    mv -f "$SSHD_CONFIG_BAK" "$SSHD_CONFIG"
    log "Restored sshd_config from backup."
  else
    log "No backup sshd_config.bak found. Restoring standard SSH parameters..."
    # Set standard defaults back
    sed -i -E "s|^[#[:space:]]*PasswordAuthentication[[:space:]]+.*|PasswordAuthentication yes|" "$SSHD_CONFIG" || true
    sed -i -E "s|^[#[:space:]]*PermitRootLogin[[:space:]]+.*|PermitRootLogin yes|" "$SSHD_CONFIG" || true
    sed -i -E "s|^[#[:space:]]*PubkeyAuthentication[[:space:]]+.*|PubkeyAuthentication yes|" "$SSHD_CONFIG" || true
  fi

  # Restart SSH service
  systemctl restart ssh 2>/dev/null || systemctl restart sshd || true
  log "SSH service restarted."
}

remove_fail2ban() {
  log "Removing Fail2Ban config..."
  if [[ -f "$FAIL2BAN_JAIL" ]]; then
    rm -f "$FAIL2BAN_JAIL"
  fi
  
  if systemctl is-active --quiet fail2ban; then
    systemctl restart fail2ban || true
  fi
  
  # Optional: stop and disable fail2ban
  systemctl stop fail2ban 2>/dev/null || true
  systemctl disable fail2ban 2>/dev/null || true
  log "Fail2Ban configuration cleared and service disabled."
}

disable_firewall() {
  case "$OS_FAMILY" in
    debian)
      log "Disabling and resetting UFW firewall..."
      if command -v ufw >/dev/null 2>&1; then
        ufw --force disable || true
        ufw --force reset || true
      fi
      ;;
    amzn2023)
      log "Disabling and stopping firewalld..."
      if systemctl is-active --quiet firewalld 2>/dev/null || systemctl is-enabled --quiet firewalld 2>/dev/null; then
        systemctl stop firewalld || true
        systemctl disable firewalld || true
      fi
      ;;
  esac
}

require_root
echo "=== Starting Hardening Reversion ==="
detect_os
restore_ssh
remove_fail2ban
disable_firewall
echo "=== Hardening Reversion Complete ==="
