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
    mkdir -p "${DOCKER_CLI_PLUGIN_DIR}"
    curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)" \
      -o "${DOCKER_CLI_PLUGIN_DIR}/docker-compose"
    chmod +x "${DOCKER_CLI_PLUGIN_DIR}/docker-compose"
  fi
}

echo "=== Starting WireGuard installation ==="

# Update and install base tooling, Docker, and WireGuard dependencies
dnf update -y
dnf install -y \
  awscli \
  curl \
  docker \
  git \
  iperf3 \
  iptables \
  nginx \
  openssl \
  python3 \
  qrencode \
  rsync \
  stow \
  tmux \
  vim \
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
import ipaddress
import logging
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn

# Token is read from a root-only file — never hardcoded or in environment
with open('/etc/wireguard/.api_token', 'r') as _f:
    TOKEN = _f.read().strip()

WG_NETWORK = ipaddress.ip_network('${wireguard_network}', strict=False)
MAX_CONTENT_LENGTH = 4096

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s'
)

def validate_pubkey(pubkey: str) -> None:
    if len(pubkey) > 128:
        raise ValueError("pubkey too long")
    subprocess.run(["wg", "pubkey"], input=pubkey + "\n", text=True, capture_output=True, check=True)

def validate_ip(ip_value: str) -> str:
    interface = ipaddress.ip_interface(ip_value)
    if interface.network.prefixlen != 32:
        raise ValueError("Client addresses must use /32")
    if interface.ip not in WG_NETWORK:
        raise ValueError("Client IP is outside the WireGuard network")
    return str(interface)

class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True

class RegistrationHandler(BaseHTTPRequestHandler):
    server_version = "wg-api/1.0"

    def log_message(self, fmt, *args):
        logging.info("%s - %s", self.client_address[0], fmt % args)

    def _write(self, status: int, payload: str):
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(payload.encode())

    def do_POST(self):
        if self.path == '/register':
            auth_header = self.headers.get('Authorization')
            if auth_header != f"Bearer {TOKEN}":
                self._write(401, "Unauthorized")
                return

            content_length = int(self.headers.get('Content-Length', 0))
            if content_length <= 0 or content_length > MAX_CONTENT_LENGTH:
                self._write(413, "Invalid request size")
                return

            post_data = self.rfile.read(content_length)

            try:
                data = json.loads(post_data)
                pubkey = data.get('pubkey')
                ip = data.get('ip')
                
                if not pubkey or not ip:
                    raise ValueError("Missing pubkey or ip")

                validate_pubkey(pubkey)
                normalized_ip = validate_ip(ip)

                current_dump = subprocess.run(
                    ["wg", "show", "wg0", "dump"],
                    text=True,
                    capture_output=True,
                    check=True
                ).stdout.splitlines()[1:]

                for line in current_dump:
                    fields = line.split('\t')
                    if len(fields) < 4:
                        continue
                    existing_pubkey = fields[0]
                    existing_allowed_ips = fields[3]
                    if existing_pubkey == pubkey and existing_allowed_ips == normalized_ip:
                        self._write(200, "Peer already registered")
                        return
                    if existing_pubkey != pubkey and normalized_ip in [item.strip() for item in existing_allowed_ips.split(',') if item.strip()]:
                        raise ValueError("Client IP already assigned to another peer")

                # Configure WireGuard
                subprocess.run(["wg", "set", "wg0", "peer", pubkey, "allowed-ips", normalized_ip], check=True)
                subprocess.run(["wg-quick", "save", "wg0"], check=True)

                self._write(200, "Registered successfully")

            except Exception as e:
                logging.exception("Registration failed")
                self._write(400, str(e))
        else:
            self._write(404, "Not found")

if __name__ == '__main__':
    server_address = ('127.0.0.1', ${wg_api_port})
    httpd = ThreadedHTTPServer(server_address, RegistrationHandler)
    print("Starting API Server on 127.0.0.1...")
    httpd.serve_forever()
EOF

cat > /etc/systemd/system/wg-api.service << 'EOF'
[Unit]
Description=WireGuard Registration API
After=network-online.target wg-quick@wg0.service
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 /opt/wg-api.py
Restart=always
RestartSec=5
User=root
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/etc/wireguard

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wg-api --now

if [[ "${enable_registration_api}" == "true" ]]; then
  echo "=== Configuring TLS reverse proxy for Registration API ==="

  mkdir -p /etc/nginx/tls
  chmod 700 /etc/nginx/tls

  openssl req -x509 -nodes -newkey rsa:4096 \
    -keyout /etc/nginx/tls/wg-api.key \
    -out /etc/nginx/tls/wg-api.crt \
    -days 365 \
    -subj "/CN=${registration_api_host}"

  chmod 600 /etc/nginx/tls/wg-api.key
  chmod 644 /etc/nginx/tls/wg-api.crt

  cat > /etc/nginx/conf.d/wg-api.conf << EOF
server {
    listen ${registration_api_tls_port} ssl http2;
    server_name ${registration_api_host};

    ssl_certificate     /etc/nginx/tls/wg-api.crt;
    ssl_certificate_key /etc/nginx/tls/wg-api.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    add_header Strict-Transport-Security "max-age=31536000" always;

    location = /register {
        proxy_pass http://127.0.0.1:${wg_api_port};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    location / {
        return 404;
    }
}
EOF

  nginx -t
  systemctl enable nginx --now
fi


echo "=== Installation complete ==="
echo "Endpoint: $SERVER_PUBLIC_IP:${wireguard_port}"
if [[ "${enable_registration_api}" == "true" ]]; then
  echo "API Endpoint: https://${registration_api_host}:${registration_api_tls_port}/register"
  echo "TLS Note: bootstrap uses a self-signed certificate; replace it with a trusted certificate before production use."
else
  echo "API Endpoint: disabled"
fi
echo "Config client1: /etc/wireguard/client1.conf"
echo "View QR: sudo qrencode -t ansiutf8 < /etc/wireguard/client1.conf"
