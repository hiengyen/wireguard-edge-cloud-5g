#!/bin/bash
while true; do
  if ! ping -c 2 -W 3 8.8.8.8 &>/dev/null; then
    echo "Connection lost! Restarting wwan.service..."
    systemctl restart wwan.service
    sleep 30 
  fi
  sleep 15
done
