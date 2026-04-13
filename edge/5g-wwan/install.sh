#!/bin/bash
# ==============================================================
# WWAN 5G Service Installer
# Installs scripts to /usr/local/bin and sets up systemd services
# ==============================================================

set -euo pipefail

# 1. Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] This script must be run as root. Please use sudo."
    exit 1
fi

echo "=== Installing 5G WWAN Services ==="

# 2. Install required dependencies
echo "[INFO] Installing required dependencies (libqmi-utils, udhcpc)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -yqq
apt-get install -yq libqmi-utils udhcpc iproute2 iputils-ping

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# 3. Check if required files exist
REQUIRED_FILES=("wwan-start.sh" "wwan-stop.sh" "wwan-monitor.sh" "wwan.service" "wwan-monitor.service")
for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$SCRIPT_DIR/$file" ]]; then
        echo "[ERROR] Critical file missing: $file"
        exit 1
    fi
done

# 4. Copy scripts to /usr/local/bin
echo "[INFO] Copying executable scripts to /usr/local/bin..."
cp "$SCRIPT_DIR"/wwan-start.sh /usr/local/bin/
cp "$SCRIPT_DIR"/wwan-stop.sh /usr/local/bin/
cp "$SCRIPT_DIR"/wwan-monitor.sh /usr/local/bin/

# Make them executable
chmod +x /usr/local/bin/wwan-start.sh
chmod +x /usr/local/bin/wwan-stop.sh
chmod +x /usr/local/bin/wwan-monitor.sh

# 5. Install systemd services
echo "[INFO] Installing systemd services..."
cp "$SCRIPT_DIR"/wwan.service /etc/systemd/system/
cp "$SCRIPT_DIR"/wwan-monitor.service /etc/systemd/system/

# Fix permissions on unit files
chmod 644 /etc/systemd/system/wwan.service
chmod 644 /etc/systemd/system/wwan-monitor.service

# 6. Reload daemon and enable services
echo "[INFO] Reloading systemd daemon..."
systemctl daemon-reload

echo "[INFO] Enabling services to start on boot..."
systemctl enable wwan.service
systemctl enable wwan-monitor.service

# 7. Ask user if they want to start the services immediately
echo ""
read -p "Do you want to start the 5G connection now? [y/N]: " START_NOW
if [[ "$START_NOW" =~ ^[Yy]$ ]]; then
    echo "[INFO] Starting wwan.service..."
    systemctl start wwan.service
    echo "[INFO] Starting wwan-monitor.service..."
    systemctl start wwan-monitor.service
    echo "[SUCCESS] Services started. Use 'systemctl status wwan' to check."
else
    echo "[INFO] Installation complete. Services will start automatically "
    echo "       on the next system boot, or you can start them manually with:"
    echo "       sudo systemctl start wwan.service"
fi

echo "======================================"
echo "   Installation Completed Successfully"
echo "======================================"
