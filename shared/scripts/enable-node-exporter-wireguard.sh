#!/bin/bash
# ==============================================================
# Expose an existing Node Exporter service over the WireGuard
# interface so cloud Prometheus can scrape edge nodes at 10.8.0.x:9100.
# Run on the Edge Node.
# ==============================================================

set -euo pipefail

NODE_EXPORTER_LISTEN_ADDRESS="${NODE_EXPORTER_LISTEN_ADDRESS:-:9100}"
NODE_EXPORTER_PORT="${NODE_EXPORTER_PORT:-9100}"
WIREGUARD_INTERFACE="${WIREGUARD_INTERFACE:-wg0}"
WIREGUARD_NETWORK="${WIREGUARD_NETWORK:-10.8.0.0/24}"
SERVICE_FILE="/etc/systemd/system/node_exporter.service"

log() {
  echo "[INFO] $*"
}

error() {
  echo "[ERROR] $*" >&2
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root. Please use sudo -E."
    exit 1
  fi
}

ensure_node_exporter_binary() {
  if [[ ! -x /usr/local/bin/node_exporter ]]; then
    error "/usr/local/bin/node_exporter not found. Run shared/scripts/install-node-exporter.sh first."
    exit 1
  fi
}

write_service() {
  log "Writing node_exporter systemd service with listen address ${NODE_EXPORTER_LISTEN_ADDRESS}"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=${NODE_EXPORTER_LISTEN_ADDRESS}

[Install]
WantedBy=multi-user.target
EOF
}

ensure_user() {
  if ! id node_exporter &>/dev/null; then
    useradd -rs /bin/false node_exporter
  fi
}

open_firewall() {
  if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    log "Allowing ${NODE_EXPORTER_PORT}/tcp on ${WIREGUARD_INTERFACE} via UFW"
    ufw allow in on "${WIREGUARD_INTERFACE}" to any port "${NODE_EXPORTER_PORT}" proto tcp
  elif command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
    log "Allowing ${NODE_EXPORTER_PORT}/tcp from ${WIREGUARD_NETWORK} via firewalld"
    firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"${WIREGUARD_NETWORK}\" port protocol=\"tcp\" port=\"${NODE_EXPORTER_PORT}\" accept"
    firewall-cmd --reload
  else
    log "No active UFW/firewalld detected; skipping firewall update"
  fi
}

restart_service() {
  systemctl daemon-reload
  systemctl enable --now node_exporter
  systemctl restart node_exporter
}

verify() {
  log "Verifying local Node Exporter endpoint"
  if curl -sf --max-time 5 "http://127.0.0.1:${NODE_EXPORTER_PORT}/metrics" >/dev/null; then
    log "Local scrape OK: http://127.0.0.1:${NODE_EXPORTER_PORT}/metrics"
  else
    error "Local scrape failed. Check: systemctl status node_exporter --no-pager"
    exit 1
  fi

  if ip link show "${WIREGUARD_INTERFACE}" &>/dev/null; then
    local wg_ip
    wg_ip=$(ip -o -4 addr show "${WIREGUARD_INTERFACE}" | awk '{print $4}' | cut -d/ -f1 | head -1)
    if [[ -n "${wg_ip}" ]]; then
      log "Edge WireGuard scrape URL should be: http://${wg_ip}:${NODE_EXPORTER_PORT}/metrics"
    fi
  fi
}

require_root
ensure_node_exporter_binary
ensure_user
write_service
open_firewall
restart_service
verify

log "Node Exporter is ready for Prometheus scrape over WireGuard."
