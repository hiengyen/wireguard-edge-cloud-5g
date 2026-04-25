#!/bin/bash
set -euo pipefail

find_qmi_device() {
  local path
  for path in /dev/cdc-wdm*; do
    [[ -c "$path" ]] || continue
    printf '%s\n' "$path"
    return 0
  done
  return 1
}

find_wwan_interface() {
  local path
  for path in /sys/class/net/ww*; do
    [[ -e "$path" ]] || continue
    basename "$path"
    return 0
  done
  return 1
}

DEVICE="$(find_qmi_device || true)"
INTERFACE="$(find_wwan_interface || true)"

echo "[INFO] Stopping QMI session..."
if [[ -n "${DEVICE:-}" ]]; then
  qmicli -d "${DEVICE}" --wds-stop-network=0 --client-no-release-cid || true
else
  echo "[INFO] No QMI device detected during shutdown."
fi

if [[ -n "${INTERFACE:-}" ]]; then
  ip link set "${INTERFACE}" down || true
else
  echo "[INFO] No WWAN interface detected during shutdown."
fi

echo "[INFO] WWAN disconnected."
