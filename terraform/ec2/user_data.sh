#!/bin/bash
###############################################################
# User Data Script — Cài đặt WireGuard tự động trên Ubuntu 22.04
###############################################################

set -euo pipefail
exec > /var/log/user-data.log 2>&1

echo "=== Bắt đầu cài đặt WireGuard ==="

# Update và cài WireGuard
apt-get update -y
apt-get install -y wireguard wireguard-tools qrencode

# Kích hoạt IP forwarding
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
sysctl -p

# Tạo thư mục cấu hình
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

# Sinh server key pair
cd /etc/wireguard
wg genkey | tee server_private.key | wg pubkey > server_public.key
chmod 600 server_private.key
SERVER_PRIVATE_KEY=$(cat server_private.key)

# Phát hiện interface mạng chính
MAIN_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)

# Sinh client key pair mẫu (peer 1)
wg genkey | tee client1_private.key | wg pubkey > client1_public.key
chmod 600 client1_private.key
CLIENT1_PRIVATE=$(cat client1_private.key)
CLIENT1_PUBLIC=$(cat client1_public.key)
wg genpsk > client1_psk.key
CLIENT1_PSK=$(cat client1_psk.key)

# Viết cấu hình server
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = ${wireguard_network%.*}.1/24
ListenPort = ${wireguard_port}
PrivateKey = $SERVER_PRIVATE_KEY
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $MAIN_IFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $MAIN_IFACE -j MASQUERADE

# ===== Peer 1 (client mẫu) =====
[Peer]
PublicKey  = $CLIENT1_PUBLIC
PresharedKey = $CLIENT1_PSK
AllowedIPs = ${wireguard_network%.*}.2/32
EOF

chmod 600 /etc/wireguard/wg0.conf

# Lấy public IP của server
SERVER_PUBLIC_IP=$(curl -s https://checkip.amazonaws.com || curl -s https://api.ipify.org)
SERVER_PUBLIC_KEY=$(cat server_public.key)

# Tạo cấu hình client1 để import
cat > /etc/wireguard/client1.conf << EOF
[Interface]
PrivateKey = $CLIENT1_PRIVATE
Address    = ${wireguard_network%.*}.2/32
DNS        = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey    = $SERVER_PUBLIC_KEY
PresharedKey = $CLIENT1_PSK
Endpoint     = $SERVER_PUBLIC_IP:${wireguard_port}
AllowedIPs   = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

# Hiển thị QR code client1 vào log
echo ""
echo "=== QR Code cho Client 1 (xem tại /var/log/user-data.log) ==="
qrencode -t ansiutf8 < /etc/wireguard/client1.conf

# Khởi động WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

echo "=== Cài đặt hoàn tất ==="
echo "Endpoint: $SERVER_PUBLIC_IP:${wireguard_port}"
echo "Config client1: /etc/wireguard/client1.conf"
echo "Xem QR: sudo qrencode -t ansiutf8 < /etc/wireguard/client1.conf"
