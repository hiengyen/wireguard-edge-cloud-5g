#!/bin/bash

set -euo pipefail

echo "======================================"
echo "   5G QMI Network Initialization"
echo "======================================"

# 1. Automatically detect network interface starting with 'ww'
INTERFACE=$(ls /sys/class/net | grep '^ww' | head -n 1)

if [[ -z "${INTERFACE:-}" ]]; then
    echo "[ERROR] No network interface starting with 'ww' was found."
    exit 1
else
    echo "[INFO] Detected interface: ${INTERFACE}"
fi

# 2. Define device and APN configuration
DEVICE="/dev/cdc-wdm0"
APN="internet"

# 3. Ensure script is executed as root
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] This script must be run as root. Please use sudo."
    exit 1
fi

# 4. Enable Raw-IP mode (required on some systems such as Armbian)
RAW_IP_PATH="/sys/class/net/${INTERFACE}/qmi/raw_ip"

if [[ -f "$RAW_IP_PATH" ]]; then
    echo "[INFO] Enabling Raw-IP mode on ${INTERFACE}..."
    echo "Y" > "$RAW_IP_PATH"
else
    echo "[WARNING] Raw-IP configuration file not found at ${RAW_IP_PATH}"
fi

# 5. Bring the interface up
echo "[INFO] Bringing interface ${INTERFACE} up..."
ip link set "${INTERFACE}" up

# 6. Start QMI data session
echo "[INFO] Starting QMI data session on device ${DEVICE}..."
RESULT=$(qmicli -d "${DEVICE}" \
    --wds-start-network="apn=${APN},ip-type=4" \
    --client-no-release-cid)

if [[ $? -eq 0 ]]; then
    echo "[SUCCESS] QMI data session established successfully."
    echo "$RESULT" | grep -i "CID" || true
else
    echo "[ERROR] Failed to start QMI data session."
    exit 1
fi

# 7. Request IP address via DHCP
echo "[INFO] Requesting IP address via DHCP..."
udhcpc -i "${INTERFACE}"

echo "======================================"
echo "   Setup Complete - Testing Connectivity"
echo "======================================"

ping -c 3 8.8.8.8

echo "[DONE] Network initialization process completed."

