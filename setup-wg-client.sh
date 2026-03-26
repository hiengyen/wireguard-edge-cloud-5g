#!/bin/bash
# ==============================================================
# WireGuard Client Setup Script - 5G WWAN
# Auto detect: ww*
# ==============================================================

set -euo pipefail

# ---------- Log colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }
header() { echo -e "\n${CYAN}===== $* =====${NC}"; }

# ---------- Configuration ----------
WG_INTERFACE="wg0"
WG_PORT=51820

WG_CONFIG="/etc/wireguard/${WG_INTERFACE}.conf"
WG_KEYS_DIR="/etc/wireguard/keys"

UPLINK_PATTERN="ww*"

ROUTE_TABLE="51820"
FWMARK="0x30"

# ---------- Check root ----------
if [[ $EUID -ne 0 ]]; then
  error "Run as root"
  exit 1
fi

# ---------- Find 5G uplink ----------
find_5g_uplink() {
  header "Scanning 5G interface (${UPLINK_PATTERN})" >&2

  for dev in /sys/class/net/${UPLINK_PATTERN}; do
    [[ -e "$dev" ]] || continue

    iface=$(basename "$dev")
    state=$(cat "$dev/operstate" 2>/dev/null || echo "unknown")

    log "Found: $iface [$state]" >&2 

    # WWAN thường state UNKNOWN -> vẫn hợp lệ
    if [[ "$state" == "up" || "$state" == "unknown" ]]; then
      # check có IP chưa
      if ip -4 addr show "$iface" | grep -q inet; then
        log "Using $iface (has IP)" >&2
        echo "$iface"
        return
      fi
    fi
  done

  error "No active 5G interface found" >&2
  exit 1
}

# ---------- Install wireguard ----------
install_wireguard() {
  header "Install WireGuard"

  if command -v wg &>/dev/null; then
    log "WireGuard already installed"
    return
  fi

  if command -v apt-get &>/dev/null; then
    apt-get update -qq
    apt-get install -y wireguard wireguard-tools
  elif command -v dnf &>/dev/null; then
    dnf install -y wireguard-tools
  elif command -v yum &>/dev/null; then
    yum install -y epel-release
    yum install -y wireguard-tools
  else
    error "Unsupported distro"
    exit 1
  fi
}

# ---------- Generate keys ----------
generate_keys() {
  header "Generate keys"

  mkdir -p "$WG_KEYS_DIR"
  chmod 700 "$WG_KEYS_DIR"

  PRIV="${WG_KEYS_DIR}/privatekey"
  PUB="${WG_KEYS_DIR}/publickey"

  if [[ ! -f "$PRIV" ]]; then
    wg genkey | tee "$PRIV" | wg pubkey > "$PUB"
    chmod 600 "$PRIV"
  fi

  PRIVATE_KEY=$(cat "$PRIV")
  PUBLIC_KEY=$(cat "$PUB")
}

# ---------- Prompt server ----------
prompt_server() {
  header "Server info"

  read -rp "Server endpoint: " WG_SERVER_ENDPOINT
  read -rp "Server port [51820]: " WG_SERVER_PORT
  WG_SERVER_PORT=${WG_SERVER_PORT:-51820}

  read -rp "Server public key: " WG_SERVER_PUBKEY
  read -rp "Client IP (10.0.0.2/24): " WG_CLIENT_IP
  WG_CLIENT_IP=${WG_CLIENT_IP:-10.0.0.2/24}
  
}

# ---------- Write config ----------
write_config() {
  uplink="$1"

  header "Writing config"

cat > "$WG_CONFIG" <<EOF
[Interface]
PrivateKey = ${PRIVATE_KEY}
Address = ${WG_CLIENT_IP}
ListenPort = ${WG_PORT}
MTU = 1280


[Peer]
PublicKey = ${WG_SERVER_PUBKEY}
Endpoint = ${WG_SERVER_ENDPOINT}:${WG_SERVER_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

  chmod 600 "$WG_CONFIG"

  log "Config written to $WG_CONFIG"
}

# ---------- Enable ----------
enable_wg() {
  header "Enable WireGuard"

  systemctl enable wg-quick@${WG_INTERFACE} 2>/dev/null || true
  systemctl restart wg-quick@${WG_INTERFACE}

  wg show ${WG_INTERFACE}
}

# ---------- Summary ----------
summary() {
  header "SUMMARY"

  echo "Interface : $WG_INTERFACE"
  echo "Port      : $WG_PORT"
  echo "Uplink    : $UPLINK"
  echo ""
  echo "Client public key:"
  echo "$PUBLIC_KEY"
}

# ==========================================================
# MAIN
# ==========================================================

header "WireGuard 5G Client (port ${WG_PORT})"

UPLINK=$(find_5g_uplink)

install_wireguard
generate_keys
prompt_server
write_config "$UPLINK"
enable_wg
summary
