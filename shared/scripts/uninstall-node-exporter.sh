#!/bin/bash
# ==============================================================
# Uninstall Node Exporter
# Run this on both Cloud Gateway and Edge Node to completely remove Node Exporter.
# ==============================================================

set -euo pipefail

# 1. Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] This script must be run as root. Please use sudo."
    exit 1
fi

echo "=== Uninstalling Node Exporter ==="

# 2. Stop and disable systemd service
if systemctl list-unit-files | grep -q '^node_exporter\.service'; then
    echo "[INFO] Stopping node_exporter service..."
    systemctl stop node_exporter.service 2>/dev/null || true
    echo "[INFO] Disabling node_exporter service..."
    systemctl disable node_exporter.service 2>/dev/null || true
    echo "[INFO] Removing systemd service file..."
    rm -f /etc/systemd/system/node_exporter.service
    systemctl daemon-reload
else
    echo "[INFO] node_exporter.service is not installed."
fi

# 3. Remove binary
if [[ -f "/usr/local/bin/node_exporter" ]]; then
    echo "[INFO] Removing node_exporter binary..."
    rm -f /usr/local/bin/node_exporter
fi

# 4. Delete user if it exists
if id "node_exporter" &>/dev/null; then
    echo "[INFO] Deleting user node_exporter..."
    userdel node_exporter 2>/dev/null || true
fi

echo "======================================"
echo "  Node Exporter Uninstallation Done"
echo "======================================"
