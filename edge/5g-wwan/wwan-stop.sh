#!/bin/bash
set -euo pipefail

DEVICE=$(find /dev -maxdepth 1 -name "cdc-wdm*" | head -n 1)
INTERFACE=$(ls /sys/class/net | grep '^ww' | head -n 1)

echo "[INFO] Stopping QMI session..."
if [[ -n "${DEVICE:-}" ]]; then
  qmicli -d "${DEVICE}" --wds-stop-network=0 --client-no-release-cid || true
fi

if [[ -n "${INTERFACE:-}" ]]; then
  ip link set "${INTERFACE}" down || true
fi

echo "[INFO] WWAN disconnected."
