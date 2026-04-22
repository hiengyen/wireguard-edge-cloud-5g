#!/bin/bash
# ==============================================================
# OS Hardening Script
# Supported targets:
# - Armbian / Debian-based edge nodes
# - Amazon Linux 2023 x86_64 cloud nodes
# ==============================================================

set -euo pipefail

WIREGUARD_PORT="${WIREGUARD_PORT:-51820}"
SSHD_CONFIG="/etc/ssh/sshd_config"
FAIL2BAN_JAIL="/etc/fail2ban/jail.d/sshd.local"
OS_FAMILY=""
FIREWALL_NAME=""

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

  # shellcheck disable=SC1091
  source /etc/os-release

  case "${ID:-}" in
    amzn)
      if [[ "${VERSION_ID:-}" != "2023" ]]; then
        error "Unsupported Amazon Linux version: ${VERSION_ID:-unknown}. Expected Amazon Linux 2023."
        exit 1
      fi
      OS_FAMILY="amzn2023"
      FIREWALL_NAME="firewalld"
      ;;
    armbian|debian|ubuntu)
      OS_FAMILY="debian"
      FIREWALL_NAME="ufw"
      ;;
    *)
      if [[ " ${ID_LIKE:-} " == *" debian "* ]]; then
        OS_FAMILY="debian"
        FIREWALL_NAME="ufw"
      else
        error "Unsupported OS: ${PRETTY_NAME:-unknown}."
        exit 1
      fi
      ;;
  esac

  log "Detected OS: ${PRETTY_NAME:-unknown}"
}

install_packages() {
  log "Installing firewall and Fail2Ban packages..."

  case "$OS_FAMILY" in
    debian)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -yqq
      apt-get install -y ufw fail2ban
      ;;
    amzn2023)
      dnf install -y firewalld fail2ban
      ;;
  esac
}

set_sshd_option() {
  local key="$1"
  local value="$2"

  if grep -Eq "^[#[:space:]]*${key}[[:space:]]+" "$SSHD_CONFIG"; then
    sed -i -E "s|^[#[:space:]]*${key}[[:space:]]+.*|${key} ${value}|" "$SSHD_CONFIG"
  else
    printf '%s %s\n' "$key" "$value" >> "$SSHD_CONFIG"
  fi
}

restart_ssh_service() {
  systemctl restart ssh 2>/dev/null || systemctl restart sshd
}

configure_ssh() {
  log "Hardening SSH configuration..."

  if [[ ! -f "${SSHD_CONFIG}.bak" ]]; then
    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"
  fi

  set_sshd_option "PasswordAuthentication" "no"
  set_sshd_option "PermitRootLogin" "no"
  set_sshd_option "KbdInteractiveAuthentication" "no"
  set_sshd_option "ChallengeResponseAuthentication" "no"
  set_sshd_option "PubkeyAuthentication" "yes"

  restart_ssh_service
}

configure_firewall_debian() {
  log "Configuring UFW firewall..."

  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp
  ufw allow "${WIREGUARD_PORT}/udp"
  ufw --force enable
}

configure_firewall_amzn2023() {
  log "Configuring firewalld..."

  systemctl enable --now firewalld
  firewall-cmd --permanent --add-service=ssh
  firewall-cmd --permanent --add-port="${WIREGUARD_PORT}/udp"
  firewall-cmd --reload
}

configure_firewall() {
  case "$OS_FAMILY" in
    debian)
      configure_firewall_debian
      ;;
    amzn2023)
      configure_firewall_amzn2023
      ;;
  esac
}

write_fail2ban_jail() {
  mkdir -p /etc/fail2ban/jail.d

  if [[ -f /var/log/auth.log ]]; then
    cat >"$FAIL2BAN_JAIL" <<'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
findtime = 600
bantime = 3600
EOF
  else
    cat >"$FAIL2BAN_JAIL" <<'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
backend = systemd
maxretry = 3
findtime = 600
bantime = 3600
EOF
  fi
}

configure_fail2ban() {
  log "Configuring Fail2Ban..."
  write_fail2ban_jail
  systemctl enable fail2ban
  systemctl restart fail2ban
}

print_summary() {
  echo "=== System Hardening Complete ==="
  echo "- OS Family: ${OS_FAMILY}"
  echo "- SSH Root Login: Disabled"
  echo "- SSH Password Auth: Disabled"
  echo "- Firewall: ${FIREWALL_NAME} enabled (SSH & WireGuard allowed)"
  echo "- WireGuard Port: ${WIREGUARD_PORT}/udp"
  echo "- Fail2Ban: Enabled for SSH"
}

require_root

echo "=== Starting System Hardening ==="
detect_os
install_packages
configure_ssh
configure_firewall
configure_fail2ban
print_summary
