#!/bin/bash
# ==============================================================
# WWAN 5G Service Uninstaller
# Removes scripts from /usr/local/bin and systemd services
# ==============================================================

set -euo pipefail

# 1. Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] This script must be run as root. Please use sudo."
    exit 1
fi

echo "=== Uninstalling 5G WWAN Services ==="

# 2. Stop services
echo "[INFO] Stopping services..."
systemctl stop wwan-monitor.service 2>/dev/null || true
systemctl stop wwan.service 2>/dev/null || true

# 3. Disable services
echo "[INFO] Disabling services..."
systemctl disable wwan-monitor.service 2>/dev/null || true
systemctl disable wwan.service 2>/dev/null || true

# 4. Remove systemd service files
echo "[INFO] Removing systemd configuration files..."
rm -f /etc/systemd/system/wwan.service
rm -f /etc/systemd/system/wwan-monitor.service

# 5. Reload daemon to clear service cache
echo "[INFO] Reloading systemd daemon..."
systemctl daemon-reload

# 6. Remove scripts from /usr/local/bin
echo "[INFO] Removing executable scripts..."
rm -f /usr/local/bin/wwan-start.sh
rm -f /usr/local/bin/wwan-stop.sh
rm -f /usr/local/bin/wwan-monitor.sh

echo "======================================"
echo "  Uninstallation Completed Successfully"
echo "======================================"
