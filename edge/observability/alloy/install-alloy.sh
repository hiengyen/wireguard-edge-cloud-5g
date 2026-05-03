#!/bin/bash
# ==============================================================
# Install Grafana Alloy on the edge node and forward journald logs
# to the cloud Loki endpoint over the WireGuard overlay.
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

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
ALLOY_CONFIG_SRC="${ALLOY_CONFIG_SRC:-${SCRIPT_DIR}/config.alloy}"
ALLOY_CONFIG_DST="${ALLOY_CONFIG_DST:-/etc/alloy/config.alloy}"
ALLOY_LOKI_URL="${ALLOY_LOKI_URL:-http://10.8.0.1:3100/loki/api/v1/push}"
PKG_MANAGER=""
ALLOY_ENV_FILE=""

require_root() {
  if [[ $EUID -ne 0 ]]; then
    error "Run as root"
    exit 1
  fi
}

require_file() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    error "Required file not found: $file"
    exit 1
  fi
}

detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"
    ALLOY_ENV_FILE="/etc/default/alloy"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
    ALLOY_ENV_FILE="/etc/sysconfig/alloy"
  else
    error "Unsupported distro. Expected apt-get or dnf."
    exit 1
  fi
}

install_alloy_debian() {
  export DEBIAN_FRONTEND=noninteractive

  apt-get update -yqq
  apt-get install -yq ca-certificates wget

  mkdir -p /etc/apt/keyrings
  wget -q -O /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg-full.key
  chmod 644 /etc/apt/keyrings/grafana.asc

  echo "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main" \
    > /etc/apt/sources.list.d/grafana.list

  apt-get update -yqq
  apt-get install -yq alloy
}

install_alloy_dnf() {
  local gpg_key

  dnf install -y ca-certificates wget

  gpg_key=$(mktemp)
  wget -q -O "$gpg_key" https://rpm.grafana.com/gpg.key
  rpm --import "$gpg_key"
  rm -f "$gpg_key"

  mkdir -p /etc/yum.repos.d
  cat > /etc/yum.repos.d/grafana.repo <<'EOF'
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

  dnf install -y alloy
}

install_alloy() {
  if command -v alloy >/dev/null 2>&1; then
    log "Alloy already installed"
    return
  fi

  header "Installing Grafana Alloy"

  case "$PKG_MANAGER" in
    apt)
      install_alloy_debian
      ;;
    dnf)
      install_alloy_dnf
      ;;
  esac
}

configure_journal_permissions() {
  local group

  if ! id alloy >/dev/null 2>&1; then
    warn "alloy user not found; package installation may have failed."
    return
  fi

  for group in adm systemd-journal; do
    if getent group "$group" >/dev/null 2>&1; then
      usermod -aG "$group" alloy
    fi
  done
}

escape_env_value() {
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//&/\\&}"
  value="${value//|/\\|}"
  printf '%s' "$value"
}

set_env_var() {
  local file="$1"
  local key="$2"
  local value

  value=$(escape_env_value "$3")

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if grep -Eq "^${key}=" "$file"; then
    sed -i -E "s|^${key}=.*|${key}=\"${value}\"|" "$file"
  else
    printf '%s="%s"\n' "$key" "$value" >> "$file"
  fi
}

configure_alloy() {
  header "Configuring Alloy"

  mkdir -p "$(dirname "$ALLOY_CONFIG_DST")"
  install -m 0644 "$ALLOY_CONFIG_SRC" "$ALLOY_CONFIG_DST"

  set_env_var "$ALLOY_ENV_FILE" "CONFIG_FILE" "$ALLOY_CONFIG_DST"
  set_env_var "$ALLOY_ENV_FILE" "ALLOY_LOKI_URL" "$ALLOY_LOKI_URL"

  if command -v alloy >/dev/null 2>&1 && alloy help validate >/dev/null 2>&1; then
    ALLOY_LOKI_URL="$ALLOY_LOKI_URL" alloy validate "$ALLOY_CONFIG_DST"
  fi
}

enable_alloy() {
  header "Starting Alloy"

  systemctl daemon-reload
  systemctl enable alloy.service
  systemctl restart alloy.service
  systemctl status alloy.service --no-pager
}

print_summary() {
  echo
  log "Alloy is configured."
  echo "Config : $ALLOY_CONFIG_DST"
  echo "Env    : $ALLOY_ENV_FILE"
  echo "Loki   : $ALLOY_LOKI_URL"
  echo
  echo "Useful checks:"
  echo "  sudo systemctl status alloy --no-pager"
  echo "  sudo journalctl -u alloy --no-pager"
}

require_root
require_file "$ALLOY_CONFIG_SRC"
detect_package_manager
install_alloy
configure_journal_permissions
configure_alloy
enable_alloy
print_summary
