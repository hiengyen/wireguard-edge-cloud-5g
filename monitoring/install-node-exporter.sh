#!/bin/bash
# ==============================================================
# Install Node Exporter for Prometheus Monitoring
# Run this on both Cloud Gateway and Edge Node
# ==============================================================

set -euo pipefail

# 1. Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] This script must be run as root. Please use sudo."
    exit 1
fi

VERSION="1.8.2"
ARCH=$(uname -m)

if [[ "$ARCH" == "x86_64" ]]; then
    TAR_FILE="node_exporter-${VERSION}.linux-amd64.tar.gz"
    DIR_NAME="node_exporter-${VERSION}.linux-amd64"
elif [[ "$ARCH" == "aarch64" ]]; then
    TAR_FILE="node_exporter-${VERSION}.linux-arm64.tar.gz"
    DIR_NAME="node_exporter-${VERSION}.linux-arm64"
else
    echo "[ERROR] Unsupported architecture: $ARCH"
    exit 1
fi

echo "=== Installing Node Exporter ($ARCH) ==="

# 2. Create user for Node Exporter
if ! id "node_exporter" &>/dev/null; then
    useradd -rs /bin/false node_exporter
fi

# 3. Download and extract
cd /tmp
wget -q "https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/${TAR_FILE}"
tar xvfz "${TAR_FILE}"
mv "${DIR_NAME}/node_exporter" /usr/local/bin/

chown node_exporter:node_exporter /usr/local/bin/node_exporter
rm -rf "${TAR_FILE}" "${DIR_NAME}"

# 4. Create systemd service
cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

# 5. Enable and start service
systemctl daemon-reload
systemctl enable --now node_exporter

echo "=== Node Exporter installed and running on port 9100 ==="
