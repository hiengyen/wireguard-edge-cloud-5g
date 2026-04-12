#!/bin/bash
DEVICE="/dev/cdc-wdm0"
INTERFACE=$(ls /sys/class/net | grep '^ww' | head -n 1)

echo "[INFO] Stopping QMI session..."
qmicli -d "${DEVICE}" --wds-stop-network=0 --client-no-release-cid || true
ip link set "${INTERFACE}" down || true
echo "[INFO] WWAN disconnected."
