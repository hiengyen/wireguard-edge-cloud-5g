#!/bin/bash

# Auto-install WireGuard


set -euo pipefail
exec > /var/log/user-data.log 2>&1

echo "=== Starting WireGuard installation ==="

# Update and install WireGuard
dnf update -y
dnf install -y wireguard-tools qrencode

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
Address = ${cidrhost(wireguard_network, 1)}/24
ListenPort = ${wireguard_port}
PrivateKey = $SERVER_PRIVATE_KEY
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $MAIN_IFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $MAIN_IFACE -j MASQUERADE

# ===== Peer 1 (sample client) =====
[Peer]
PublicKey  = $CLIENT1_PUBLIC
PresharedKey = $CLIENT1_PSK
AllowedIPs = ${cidrhost(wireguard_network, 2)}/32
EOF

chmod 600 /etc/wireguard/wg0.conf

# Get server public IP
SERVER_PUBLIC_IP=$(curl -s https://checkip.amazonaws.com || curl -s https://api.ipify.org)
SERVER_PUBLIC_KEY=$(cat server_public.key)

# Create client1 config for import
cat > /etc/wireguard/client1.conf << EOF
[Interface]
PrivateKey = $CLIENT1_PRIVATE
Address    = ${cidrhost(wireguard_network, 2)}/32
DNS        = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey    = $SERVER_PUBLIC_KEY
PresharedKey = $CLIENT1_PSK
Endpoint     = $SERVER_PUBLIC_IP:${wireguard_port}
AllowedIPs   = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

# Display client1 QR code in log
echo ""
echo "=== QR Code for Client 1 (view at /var/log/user-data.log) ==="
qrencode -t ansiutf8 < /etc/wireguard/client1.conf

# Start WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# ===== Fetch API Token from Secrets Manager (IMDSv2) =====
echo "=== Fetching API token from Secrets Manager ==="

# Step 1: Get IMDSv2 session token
IMDS_SESSION=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60")

# Step 2: Detect current region from IMDS
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_SESSION" \
  http://169.254.169.254/latest/meta-data/placement/region)

# Step 3: Fetch secret value from Secrets Manager
API_TOKEN=$(aws secretsmanager get-secret-value \
  --region "$REGION" \
  --secret-id "${secret_id}" \
  --query SecretString \
  --output text)

# Step 4: Write to root-only file — never in env or user_data
echo "$API_TOKEN" > /etc/wireguard/.api_token
chmod 600 /etc/wireguard/.api_token
unset API_TOKEN

echo "API token stored securely at /etc/wireguard/.api_token"

# ===== Install WireGuard API (For Client Registration) =====
echo "=== Installing Registration API ==="

cat > /opt/wg-api.py << 'EOF'
import json
import subprocess
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

# Token is read from a root-only file — never hardcoded or in environment
with open('/etc/wireguard/.api_token', 'r') as _f:
    TOKEN = _f.read().strip()

class RegistrationHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/register':
            auth_header = self.headers.get('Authorization')
            if auth_header != f"Bearer {TOKEN}":
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b"Unauthorized")
                return

            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)

            try:
                data = json.loads(post_data)
                pubkey = data.get('pubkey')
                ip = data.get('ip')
                
                if not pubkey or not ip:
                    raise ValueError("Missing pubkey or ip")

                # Configure Wireguard
                subprocess.run(["wg", "set", "wg0", "peer", pubkey, "allowed-ips", ip], check=True)
                subprocess.run(["wg-quick", "save", "wg0"], check=True)

                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"Registered successfully")

            except Exception as e:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(str(e).encode())
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server_address = ('', ${wg_api_port})
    httpd = HTTPServer(server_address, RegistrationHandler)
    print("Starting API Server...")
    httpd.serve_forever()
EOF

cat > /etc/systemd/system/wg-api.service << 'EOF'
[Unit]
Description=WireGuard Registration API
After=network.target wg-quick@wg0.service

[Service]
ExecStart=/usr/bin/python3 /opt/wg-api.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wg-api --now


echo "=== Installation complete ==="
echo "Endpoint: $SERVER_PUBLIC_IP:${wireguard_port}"
echo "API Endpoint: http://$SERVER_PUBLIC_IP:${wg_api_port}/register"
echo "Config client1: /etc/wireguard/client1.conf"
echo "View QR: sudo qrencode -t ansiutf8 < /etc/wireguard/client1.conf"
