#!/bin/bash

# Auto-install WireGuard


set -euo pipefail
exec > /var/log/user-data.log 2>&1

WIREGUARD_NETWORK_CIDR="${wireguard_network}"
WIREGUARD_SERVER_CIDR="${cidrhost(wireguard_network, 1)}/${split("/", wireguard_network)[1]}"
WIREGUARD_SAMPLE_CLIENT_CIDR="${cidrhost(wireguard_network, 2)}/32"
DOCKER_CLI_PLUGIN_DIR="/usr/local/lib/docker/cli-plugins"

install_docker_compose_plugin() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    return 0
  fi

  if dnf -q list available docker-compose-plugin >/dev/null 2>&1; then
    dnf install -y docker-compose-plugin
  else
    mkdir -p "$${DOCKER_CLI_PLUGIN_DIR}"
    curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)" \
      -o "$${DOCKER_CLI_PLUGIN_DIR}/docker-compose"
    chmod +x "$${DOCKER_CLI_PLUGIN_DIR}/docker-compose"
  fi
}

echo "=== Starting WireGuard installation ==="

# Update and install base tooling, Docker, and WireGuard dependencies
dnf update -y
dnf install -y \
  awscli \
  docker \
  git \
  iperf3 \
  iptables \
  nginx \
  openssl \
  python3 \
  qrencode \
  rsync \
  tmux \
  vim \
  wget \
  wireguard-tools 

systemctl enable --now docker
usermod -aG docker ec2-user || true
install_docker_compose_plugin

# Enable IP forwarding
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
sysctl -p

# Create config directory
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

# Generate server key pair
cd /etc/wireguard
wg genkey | tee server_private.key | wg pubkey > server_public.key
chmod 600 server_private.key
SERVER_PRIVATE_KEY=$(cat server_private.key)

# Detect main network interface
MAIN_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)

# Generate sample client key pair (peer 1)
wg genkey | tee client1_private.key | wg pubkey > client1_public.key
chmod 600 client1_private.key
CLIENT1_PRIVATE=$(cat client1_private.key)
CLIENT1_PUBLIC=$(cat client1_public.key)
wg genpsk > client1_psk.key
CLIENT1_PSK=$(cat client1_psk.key)

# Write server config
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = $${WIREGUARD_SERVER_CIDR}
ListenPort = ${wireguard_port}
PrivateKey = $SERVER_PRIVATE_KEY
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $MAIN_IFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $MAIN_IFACE -j MASQUERADE

# ===== Peer 1 (sample client) =====
[Peer]
PublicKey  = $CLIENT1_PUBLIC
PresharedKey = $CLIENT1_PSK
AllowedIPs = $${WIREGUARD_SAMPLE_CLIENT_CIDR}
EOF

chmod 600 /etc/wireguard/wg0.conf

# Get server public IP
SERVER_PUBLIC_IP=$(curl -s https://checkip.amazonaws.com || curl -s https://api.ipify.org)
SERVER_PUBLIC_KEY=$(cat server_public.key)

# Create client1 config for import
cat > /etc/wireguard/client1.conf << EOF
[Interface]
PrivateKey = $CLIENT1_PRIVATE
Address    = $${WIREGUARD_SAMPLE_CLIENT_CIDR}
DNS        = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey    = $SERVER_PUBLIC_KEY
PresharedKey = $CLIENT1_PSK
Endpoint     = $SERVER_PUBLIC_IP:${wireguard_port}
AllowedIPs   = $${WIREGUARD_NETWORK_CIDR}
PersistentKeepalive = 25
EOF

# Display client1 QR code in log
echo ""
echo "=== QR Code for Client 1 (view at /var/log/user-data.log) ==="
qrencode -t ansiutf8 < /etc/wireguard/client1.conf

# Start WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

echo "=== Installation complete ==="
echo "Endpoint: $SERVER_PUBLIC_IP:${wireguard_port}"
echo "Config client1: /etc/wireguard/client1.conf"
echo "View QR: sudo qrencode -t ansiutf8 < /etc/wireguard/client1.conf"
