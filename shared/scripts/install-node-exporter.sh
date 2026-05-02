#!/bin/bash
# ==============================================================
# Install Node Exporter for Prometheus Monitoring
# Run this on both Cloud Gateway and Edge Node
# Supported targets: Amazon Linux 2023 x86_64 and Armbian aarch64
# ==============================================================

set -euo pipefail

# 1. Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] This script must be run as root. Please use sudo."
    exit 1
fi

VERSION="${NODE_EXPORTER_VERSION:-1.11.1}"
BASE_URL="https://github.com/prometheus/node_exporter/releases/download/v${VERSION}"
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

SHA_FILE="sha256sums.txt"

echo "=== Installing Node Exporter ($ARCH) ==="

# 2. Create user for Node Exporter
if ! id "node_exporter" &>/dev/null; then
    useradd -rs /bin/false node_exporter
fi

# 3. Download and extract
cd /tmp
wget -q "${BASE_URL}/${TAR_FILE}"
wget -q "${BASE_URL}/${SHA_FILE}"
grep " ${TAR_FILE}\$" "${SHA_FILE}" | sha256sum -c -
tar xvfz "${TAR_FILE}"
mv "${DIR_NAME}/node_exporter" /usr/local/bin/

chown node_exporter:node_exporter /usr/local/bin/node_exporter
rm -rf "${TAR_FILE}" "${DIR_NAME}" "${SHA_FILE}"

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
