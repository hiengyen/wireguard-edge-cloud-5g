#!/bin/bash
# ==============================================================
# OS Hardening Script (Ubuntu/Debian)
# ==============================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] This script must be run as root. Please use sudo."
  exit 1
fi

echo "=== Starting System Hardening ==="

# 1. Update and install required packages (UFW, Fail2Ban)
echo "[INFO] Installing UFW and Fail2Ban..."
apt-get update -yqq
apt-get install -y ufw fail2ban

# 2. Configure SSHD (/etc/ssh/sshd_config)
echo "[INFO] Hardening SSH Configuration..."
SSHD_CONFIG="/etc/ssh/sshd_config"
# Backup original config
cp $SSHD_CONFIG "${SSHD_CONFIG}.bak"

# Disable password authentication
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' $SSHD_CONFIG
# Disable root login
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' $SSHD_CONFIG

# Restart SSH service
systemctl restart ssh || systemctl restart sshd

# 3. Configure UFW Firewall
echo "[INFO] Configuring UFW Firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# Allow SSH
ufw allow ssh

# Allow Wireguard (UDP 64203 as per terraform variable default)
echo "[INFO] Allowing WireGuard Port 64203 (UDP)..."
ufw allow 64203/udp

# Note: In a production environment with monitoring, you might also want to
# conditionally block port 9100 from everywhere EXCEPT the WireGuard tunnel interface (wg0)
# Example: ufw allow in on wg0 to any port 9100

# Enable UFW
echo "y" | ufw enable

# 4. Configure Fail2Ban
echo "[INFO] Configuring Fail2Ban..."
cat >/etc/fail2ban/jail.local <<'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

systemctl enable fail2ban
systemctl restart fail2ban

echo "=== System Hardening Complete ==="
echo "- SSH Root Login: Disabled"
echo "- SSH Password Auth: Disabled"
echo "- UFW Firewall: Enabled (SSH & WireGuard allowed)"
echo "- Fail2Ban: Enabled for SSH"
