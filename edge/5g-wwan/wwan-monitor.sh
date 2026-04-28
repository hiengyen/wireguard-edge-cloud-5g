#!/bin/bash
# ==========================================================
# WWAN Monitor & Watchdog 
# Features: Multi-target verify, Strike System, Hardware Reset, VPN Revive
# ==========================================================

TARGETS=("8.8.8.8" "1.1.1.1" "8.8.4.4")
MAX_STRIKES=1               # Consecutive ping failures needed to trigger software restart
HARD_RESET_LIMIT=3          # Consecutive soft-restart failures needed to trigger hardware reset

strike_count=0
software_restart_count=0
WG_SERVICE="wg-quick@wg0.service"

# Connection Check: Return true (0) if AT LEAST ONE target responds
check_connection() {
  for target in "${TARGETS[@]}"; do
    if ping -c 1 -W 2 "$target" &>/dev/null; then
      return 0
    fi
  done
  return 1
}

# Check if WWAN interface exists
find_wwan_interface() {
  for path in /sys/class/net/ww*; do
    [[ -e "$path" ]] && basename "$path" && return 0
  done
  return 1
}

# Check if QMI device exists
find_qmi_device() {
  for path in /dev/cdc-wdm*; do
    [[ -c "$path" ]] && echo "$path" && return 0
  done
  return 1
}

wait_for_device() {
  echo "[INFO] Entering wait loop for WWAN device/interface..."
  while true; do
    if find_wwan_interface >/dev/null && find_qmi_device >/dev/null; then
      echo "[INFO] WWAN device and interface detected!"
      return 0
    fi
    sleep 5
  done
}

echo "[INFO] Watchdog active. Targets: ${TARGETS[*]}"

while true; do
  # 1. Check if hardware is present
  if ! find_wwan_interface >/dev/null || ! find_qmi_device >/dev/null; then
    echo "[ERROR] WWAN hardware missing (interface or /dev/cdc-wdm* not found)."
    wait_for_device
    echo "[ACTION] Hardware restored. Restarting wwan.service immediately..."
    systemctl restart wwan.service
    sleep 30
    strike_count=0
    continue
  fi

  # 2. Check connection
  if check_connection; then
    # SCENARIO: NETWORK IS UP
    
    # If the network was previously down (reached max strikes) and is now restored, revive VPN
    if [[ $strike_count -ge $MAX_STRIKES ]]; then
      echo "[INFO] Network restored successfully."
      echo "[ACTION] Reviving WireGuard VPN tunnel ($WG_SERVICE)..."
      systemctl restart "$WG_SERVICE" 2>/dev/null || true
    fi
    
    # Clear bad records
    strike_count=0
    software_restart_count=0
  else
    # SCENARIO: NETWORK IS DOWN
    strike_count=$((strike_count + 1))
    echo "[WARN] Ping failed (Strike $strike_count/$MAX_STRIKES)."

    # If the network fails consecutively for MAX_STRIKES times
    if [[ $strike_count -ge $MAX_STRIKES ]]; then
      software_restart_count=$((software_restart_count + 1))
      echo "[ERROR] Network confirmed disconnected."

      # If software restarts have failed repeatedly -> USB module firmware might be frozen!
      if [[ $software_restart_count -ge $HARD_RESET_LIMIT ]]; then
        echo "[CRITICAL] Software restarts failed $HARD_RESET_LIMIT times."
        MODEM_DEV=$(find_qmi_device)
        
        if [[ -n "$MODEM_DEV" ]]; then
          echo "[ACTION] Triggering HARDWARE RESET on Quectel Modem ($MODEM_DEV)!"
          
          # Stop the software service to release the /dev interface bindings
          systemctl stop wwan.service
          
          # Send the raw command: Force the hardware firmware to reboot
          qmicli -d "$MODEM_DEV" --dms-set-operating-mode=reset || true
          
          echo "[INFO] Cooling down 40s to wait for USB enumeration..."
          sleep 40
        else
          echo "[ERROR] Quectel device not found for hard reset."
        fi
        
        # Reset the counter to give software restarts another chance
        software_restart_count=0
      fi

      echo "[ACTION] Restarting wwan.service via Software..."
      systemctl restart wwan.service
      
      echo "[INFO] Waiting 30s to allow IP assignment and negotiation..."
      sleep 30
    fi
  fi
  sleep 5
done
