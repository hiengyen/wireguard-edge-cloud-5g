#!/bin/bash
# ==============================================================
# Install PeerSight Agent for WireGuard Monitoring
# Run this on both Cloud Gateway and Edge Nodes
# ==============================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] This script must be run as root. Please use sudo."
    exit 1
fi

PEERSIGHT_API_URL="${PEERSIGHT_API_URL:-}"
PEERSIGHT_HOST_ID="${PEERSIGHT_HOST_ID:-}"
PEERSIGHT_TOKEN="${PEERSIGHT_TOKEN:-}"
PEERSIGHT_LOOP_INTERVAL="${PEERSIGHT_LOOP_INTERVAL:-15}"
PEERSIGHT_READ_ONLY="${PEERSIGHT_READ_ONLY:-false}"
PEERSIGHT_REDACT_SECRETS="${PEERSIGHT_REDACT_SECRETS:-true}"
# Ensure wireguard-tools (wg command) is installed
if ! command -v wg &> /dev/null; then
    echo "[ERROR] 'wg' command not found. Please install wireguard-tools manually."
    exit 1
fi

DETECTED_WG=$(command -v wg)
PEERSIGHT_WG_BINARY="${PEERSIGHT_WG_BINARY:-$DETECTED_WG}"
PEERSIGHT_CONFIG_DIR="${PEERSIGHT_CONFIG_DIR:-/etc/wireguard}"

if [[ -z "$PEERSIGHT_API_URL" || -z "$PEERSIGHT_HOST_ID" || -z "$PEERSIGHT_TOKEN" ]]; then
    echo "[ERROR] Missing required variables. Please provide PEERSIGHT_API_URL, PEERSIGHT_HOST_ID, and PEERSIGHT_TOKEN."
    exit 1
fi

if [[ ! -f /usr/local/bin/peersight-agent ]]; then
    echo "[ERROR] /usr/local/bin/peersight-agent not found. Please compile/copy it first."
    exit 1
fi

echo "=== Installing PeerSight Agent ==="

mkdir -p /etc/peersight

cat > /etc/peersight/agent.env << EOF
PEERSIGHT_API_URL=${PEERSIGHT_API_URL}
PEERSIGHT_HOST_ID=${PEERSIGHT_HOST_ID}
PEERSIGHT_TOKEN=${PEERSIGHT_TOKEN}
PEERSIGHT_LOOP_INTERVAL=${PEERSIGHT_LOOP_INTERVAL}
PEERSIGHT_READ_ONLY=${PEERSIGHT_READ_ONLY}
PEERSIGHT_REDACT_SECRETS=${PEERSIGHT_REDACT_SECRETS}
PEERSIGHT_WG_BINARY=${PEERSIGHT_WG_BINARY}
PEERSIGHT_CONFIG_DIR=${PEERSIGHT_CONFIG_DIR}
EOF

chmod 600 /etc/peersight/agent.env

cat > /etc/systemd/system/peersight-agent.service << 'EOF'
[Unit]
Description=PeerSight WireGuard Agent
After=network.target wg-quick@wg0.service
Requires=wg-quick@wg0.service

[Service]
Type=simple
User=root
WorkingDirectory=/etc/peersight
EnvironmentFile=/etc/peersight/agent.env
ExecStart=/usr/local/bin/peersight-agent
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now peersight-agent.service

echo "=== PeerSight Agent installed and running ==="
