# Deployment Guide | Hướng Dẫn Triển Khai

🇬🇧 [English](#-english) | 🇻🇳 [Tiếng Việt](#-tiếng-việt)

---

## 🇬🇧 English

This document describes the recommended deployment workflow for the `wireguard-edge-cloud-5g` project in a production-oriented setup.
For a compact command reference, see [COMMANDS.md](./COMMANDS.md).

The repository assumes:

- VPN topology: `Client-to-Site (Edge-to-Cloud)`
- Cloud EC2 node acts as the central WireGuard gateway/server
- Each edge node acts as a WireGuard client that dials out to the cloud public endpoint
- Traffic over WireGuard is split-tunnel by default: only the overlay subnet `10.8.0.0/24` is routed through the VPN unless `WIREGUARD_ALLOWED_IPS` is changed explicitly
- WireGuard overlay network: `10.8.0.0/24`
- WireGuard server interface: `10.8.0.1/24`
- Each edge node uses a unique `/32` client address, for example `10.8.0.2/32`
- Peer registration is done manually for maximum security.

---

## 1. Prerequisites

Prepare the following before deployment:

- An AWS account with permission to create EC2, IAM, EIP, Security Group, and Secrets Manager resources
- An existing AWS EC2 key pair for SSH access
- A public subnet and VPC where the EC2 instance will run
- Optionally, a DNS record for the Registration API, for example `vpn-api.example.com`
- An edge device with:
  - Linux
  - WireGuard support
  - Quectel-compatible WWAN/QMI stack if using the 5G automation scripts

Install locally:

- `terraform >= 1.9`
- `docker` and Docker Compose v2
- `bash`

---

## 2. Prepare Environment Variables

Create the deployment environment file:

```bash
cp .env.example .env
```

Load the variables into the current shell:

```bash
set -a && . ./.env && set +a
```

Update `.env` with your real values:

- `TF_VAR_admin_ssh_cidr`
- `TF_VAR_wireguard_port`
- `TF_VAR_wireguard_network`
- `TF_VAR_wireguard_client_cidr`
- `GRAFANA_ADMIN_PASSWORD`
- `PROMETHEUS_VERSION`
- `GRAFANA_VERSION`
- `LOKI_VERSION`
- `LOKI_PORT`
- `ALLOY_LOKI_URL`
- `ALLOY_HTTP_LISTEN_ADDR`
- `MONITORING_BIND_ADDRESS`
- `ALLOW_MONITORING_OVER_WIREGUARD`
- `WIREGUARD_PORT`
- `WIREGUARD_ALLOWED_IPS`

- `EDGE_EXTRA_TCP_PORTS`

Recommended base values:

- `TF_VAR_wireguard_network=10.8.0.0/24`
- `TF_VAR_wireguard_client_cidr=10.8.0.2/32`
- `TF_VAR_wireguard_port=51820`
- `WIREGUARD_PORT=51820`
- `WIREGUARD_ALLOWED_IPS=10.8.0.0/24`

- `MONITORING_BIND_ADDRESS=127.0.0.1`
- `LOKI_PORT=3100`
- `ALLOY_LOKI_URL=http://10.8.0.1:3100/loki/api/v1/push`
- `ALLOY_HTTP_LISTEN_ADDR=0.0.0.0:12345`
- `ALLOW_MONITORING_OVER_WIREGUARD=false`
- `EDGE_EXTRA_TCP_PORTS='443 5201'`
- `TF_VAR_admin_ssh_cidr='["<your-public-ip>/32"]'`

---

## 3. Configure Terraform Inputs

Review [cloud/terraform/ec2/terraform.tfvars.example](/home/hiengyen/CODE/wireguard-edge-cloud-5g/cloud/terraform/ec2/terraform.tfvars.example:1) and provide the required values either through:

- exported `TF_VAR_*` environment variables from `.env`
- or a local non-committed `terraform.tfvars`

Required infrastructure values:

- `vpc_id`
- `subnet_id`
- `key_name`
- optionally `instance_type`

Current repository default:

- `instance_type=t3.medium`
- Use a larger type if you expect Prometheus, Grafana, Docker, and WireGuard to run together under sustained load

---

## 4. Provision the Cloud Node

Run:

```bash
set -a && . ./.env && set +a
cd cloud/terraform/ec2
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

If you are increasing RAM on an existing deployment, review the plan carefully because changing `instance_type` updates the EC2 instance shape.

Capture the outputs:

- EC2 public IP
- WireGuard endpoint
- Security group ID

Useful commands:

```bash
terraform output public_ip
terraform output wireguard_endpoint
```

What Terraform sets up:

- Amazon Linux 2023 EC2 instance
- encrypted root volume
- Elastic IP
- IAM role for Secrets Manager access
- WireGuard server bootstrap
- Base operator packages on the cloud node: `curl`, `rsync`, `iperf3`, `git`, `tmux`, `stow`, `vim`, `wget`, `docker`, and Docker Compose v2

---

## 5. Verify the Cloud Node

SSH to the instance:

```bash
ssh -i <your-key.pem> ec2-user@<elastic-ip>
```

Check services:

```bash
sudo systemctl status wg-quick@wg0
```

Check WireGuard:

```bash
sudo wg show
sudo cat /etc/wireguard/wg0.conf
sudo cat /etc/wireguard/server_public.key
```

Check listeners:

```bash
sudo ss -lntp | grep 51820
```

Expected behavior:

- `wg0` is active

Important note:

- The bootstrap `user_data.sh` creates a sample peer using `10.8.0.2/32`
- If your first real edge node also uses `10.8.0.2/32`, remove or replace that sample peer before registering a different client key

---

## 6. Harden the Cloud Node

Before starting the monitoring stack, secure the cloud node and install the metrics exporter:

```bash
set -a && . ./.env && set +a
sudo -E bash shared/scripts/hardening.sh
sudo -E bash shared/scripts/install-node-exporter.sh
```

Verify Node Exporter on the cloud host:

```bash
sudo systemctl status node_exporter --no-pager
curl http://127.0.0.1:9100/metrics | head
```

---

## 7. Start Monitoring on the Cloud Node

On the cloud host:

```bash
cd cloud/monitoring
```

The monitoring stack includes a **Unified Edge & Cloud Dashboard** for a single-pane-of-glass operational view.

To start the stack:

```bash
# Use -E to preserve environment variables loaded from .env
sudo -E docker compose --env-file ../../.env up -d --force-recreate
```

Alternatively, use the wrapper script which automatically applies `ALLOW_MONITORING_OVER_WIREGUARD` and validates required variables:

```bash
sudo -E bash cloud/monitoring/setup-monitoring.sh
```

Verify:

```bash
sudo docker ps
curl http://127.0.0.1:9090/-/healthy
curl http://127.0.0.1:3100/ready
curl http://127.0.0.1:3000/api/health
```

Notes:

- Prometheus, Loki, and Grafana bind to `127.0.0.1` by default. To reach them through WireGuard instead of SSH tunneling, set `ALLOW_MONITORING_OVER_WIREGUARD=true` in `.env` before running `hardening.sh` and starting the stack. The wrapper script applies this automatically; with the direct `docker compose` command, export `MONITORING_BIND_ADDRESS=10.8.0.1` first.
- Grafana provisions the Prometheus and Loki data sources from `cloud/monitoring/grafana/provisioning/datasources/datasources.yml`.

To access the web UIs through SSH tunneling from your local machine:

> The addresses below assume `ALLOW_MONITORING_OVER_WIREGUARD=true` (`MONITORING_BIND_ADDRESS=10.8.0.1`).
> If your stack binds to `127.0.0.1` instead, replace `10.8.0.1` with `127.0.0.1` in the cloud `-L` flags.

```bash
# -N keeps the tunnel open without opening a shell
ssh -i <your-key.pem> -N \
  -L 3000:10.8.0.1:3000 \
  -L 9090:10.8.0.1:9090 \
  -L 3100:10.8.0.1:3100 \
  -L 9100:10.8.0.1:9100 \
  -L 12345:10.8.0.2:12345 \
  -L 4000:10.8.0.1:4000 \
  -L 5173:10.8.0.1:5173 \
  ec2-user@<elastic-ip>
```

Then open:

- Grafana: `http://127.0.0.1:3000`
- Prometheus: `http://127.0.0.1:9090`
- Loki readiness: `http://127.0.0.1:3100/ready`
- Node Exporter (cloud): `http://127.0.0.1:9100/metrics`
- Alloy UI (edge): `http://127.0.0.1:12345`
- PeerSight API: `http://127.0.0.1:4000/health`
- PeerSight UI: `http://127.0.0.1:5173`

> **Alloy UI prerequisite:** `install-alloy.sh` sets `CUSTOM_ARGS="--server.http.listen-addr=0.0.0.0:12345"` so
> the UI is reachable over WireGuard. Also open the port on the edge UFW (one-time):
> `sudo ufw allow in on wg0 to any port 12345 proto tcp`

---

## 8. Prepare the Edge Node

On the edge device:

```bash
set -a && . ./.env && set +a
cd edge/5g-wwan
sudo -E bash install.sh
```

If you use the Docker-based WWAN mode:

```bash
set -a && . ./.env && set +a
cd edge/5g-wwan/docker
sudo -E docker compose up -d
```

Check WWAN state:

```bash
ip addr
systemctl status wwan.service
systemctl status wwan-monitor.service
```

The edge installer also provisions:

- `curl`, `rsync`, `iperf3`, `git`, `tmux`, `stow`, `vim`, `wget`, `docker`, and Docker Compose v2
- `ufw` on apt-based edge systems, and on dnf-based edge systems when the package exists in the enabled repositories

---

## 9. Join the VPN Network

Requirements:

- You can SSH to the cloud node
- You have the cloud server public key from `/etc/wireguard/server_public.key`

Run the client setup on the edge node:

```bash
set -a && . ./.env && set +a
sudo -E bash edge/vpn/setup-wg-client.sh
```

Recommended answers:

- `Server endpoint IP/Domain`: the EC2 Elastic IP or public DNS name
- `Server port`: `51820`
- `Server public key`: output of `sudo cat /etc/wireguard/server_public.key`
- `Client IP`: a unique `/32`, for example `10.8.0.3/32` if `10.8.0.2/32` is already occupied by the bootstrap sample peer
- `Allowed IPs`: `10.8.0.0/24`

The client script will print the client public key. Add that peer manually on the cloud node:

```bash
sudo wg set wg0 peer <client-public-key> allowed-ips 10.8.0.3/32
sudo wg-quick save wg0
```

Verify from the cloud node:

```bash
sudo wg show
```

If you need to remove the local WireGuard client setup from the edge node later:

```bash
sudo -E bash edge/vpn/uninstall-wg-client.sh
```

To remove the local key pair too:

```bash
sudo -E REMOVE_WG_KEYS=true bash edge/vpn/uninstall-wg-client.sh
```

This only removes the local edge setup. Remove the peer on the cloud server separately if it was previously registered.

---

## 10. Harden the Edge Node

Now that the edge node is connected to the VPN, secure it and install Node Exporter:

```bash
set -a && . ./.env && set +a
sudo -E bash shared/scripts/hardening.sh
sudo -E bash shared/scripts/install-node-exporter.sh
```

If the edge node does not have an `authorized_keys` file yet, the script will **skip SSH hardening** and print a warning:

```
[WARN] No authorized_keys file found. Skipping SSH hardening (password login remains enabled).
[WARN] Run this script again after setting up SSH key authentication.
```

Firewall (UFW) and Fail2Ban are still configured normally. Password-based SSH login remains enabled until you complete the next step.

### 10.1. Set Up SSH Key Authentication and Re-Harden

To complete SSH hardening, set up key-based authentication first.

If you are already connected to the edge node via password-based SSH, keep that session open as a safety net throughout this process.

**On your local machine**, copy your public key to the edge node:

```bash
ssh-copy-id <user>@<edge-ip>
```

Or manually — get your public key on the local machine:

```bash
cat ~/.ssh/id_ed25519.pub
```

Then paste it on the edge node (in your existing SSH session):

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "ssh-ed25519 AAAA..." >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

If you do not have an SSH key pair yet, generate one first on your local machine:

```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
```

**Verify key-based login works** by opening a **new terminal** (keep the old session open):

```bash
ssh -o PasswordAuthentication=no <user>@<edge-ip>
```

Once key-based login is confirmed, re-run the hardening script to disable password authentication:

```bash
set -a && . ./.env && set +a
sudo -E bash shared/scripts/hardening.sh
```

Verify Node Exporter on the edge host:

```bash
sudo systemctl status node_exporter --no-pager
curl http://127.0.0.1:9100/metrics | head
```

---

## 11. Edge Log Forwarding with Alloy

Run Alloy on the edge node after the WireGuard tunnel can reach the cloud overlay address.
The default Alloy config reads journald and pushes logs to Loki at `http://10.8.0.1:3100/loki/api/v1/push`.
For this default endpoint to work, you must have started the cloud monitoring stack with `MONITORING_BIND_ADDRESS=10.8.0.1` and allowed monitoring over WireGuard in `hardening.sh`.

> [!WARNING]
> **Edge Time Synchronization Required!**  
> Since embedded ARM SBCs (like Orange Pi) do not have a hardware RTC battery, their clock can be completely wrong (e.g. out of sync by days) after a reboot or power loss. Loki automatically rejects logs that are too far behind the active ingestion window, and Grafana will hide them from current time queries.
>
> **Always verify and sync the Edge clock before running Alloy:**
>
> * **Option A: Automatic NTP Sync (Internet Access Required)**
>   ```bash
>   date
>   sudo timedatectl set-ntp true
>   sudo systemctl restart systemd-timesyncd
>   ```
>
> * **Option B: Manual Clock Sync**
>   ```bash
>   sudo date -s "2026-06-03 15:12:20"
>   ```
>
> * **Option C: GPS/GNSS Offline Time Synchronization (Quectel Module)**
>   If the Edge node has no internet connection for NTP, use the built-in GPS on the Quectel RM502Q-GL module:
>   1. Route and enable GNSS output via AT commands (sent to `/dev/ttyUSB2` or `/dev/ttyMHI2`):
>      ```bash
>      sudo sh -c 'echo -e "AT+QGPSCFG=\"outport\",\"usbnmea\"\r" > /dev/ttyUSB2'
>      sudo sh -c 'echo -e "AT+QGPS=1\r" > /dev/ttyUSB2'
>      ```
>   2. Verify NMEA data stream is active: `cat /dev/ttyUSB1` (or `/dev/ttyMHI1`).
>   3. Install `gpsd` and `ntpsec`: `sudo apt-get install gpsd gpsd-clients ntpsec -y`.
>   4. Configure `/etc/default/gpsd` to use your NMEA serial port (e.g. `DEVICES="/dev/ttyUSB1"`). Restart it: `sudo systemctl restart gpsd`.
>   5. Stop the default NTP client: `sudo systemctl disable --now systemd-timesyncd`.
>   6. Add the following reference clock to `/etc/ntpsec/ntp.conf`:
>      ```text
>      refclock shm unit 0 time1 0.125 refid GPS prefer
>      ```
>   7. Restart NTPsec: `sudo systemctl restart ntpsec`.

```bash
set -a && . ./.env && set +a
sudo -E bash edge/observability/alloy/install-alloy.sh
```

Override the push endpoint if your cloud WireGuard IP or Loki port differs:

```bash
sudo -E ALLOY_LOKI_URL=http://10.8.0.1:3100/loki/api/v1/push bash edge/observability/alloy/install-alloy.sh
```

Verify Alloy:

```bash
sudo systemctl status alloy --no-pager
sudo journalctl -u alloy --no-pager

# Confirm Alloy UI is listening on all interfaces
ss -lntp | grep 12345

# Quick local check
curl http://127.0.0.1:12345
```

### Accessing the Alloy Web UI

Alloy exposes a pipeline graph and component status UI on port `12345`.
`install-alloy.sh` configures `CUSTOM_ARGS="--server.http.listen-addr=0.0.0.0:12345"` so the UI
is reachable from the WireGuard overlay.

Before using the SSH tunnel, open the port on the edge UFW (one-time):

```bash
sudo ufw allow in on wg0 to any port 12345 proto tcp
```

Then from your local machine, add the Alloy line to the SSH tunnel:

```bash
ssh -i <your-key.pem> -N \
  -L 12345:10.8.0.2:12345 \
  ec2-user@<elastic-ip>
```

Open `http://127.0.0.1:12345` in a browser. The UI shows:

- **Graph** — live pipeline component graph
- **Components** — status of `loki.source.journal`, `loki.write.cloud`, etc.

In Grafana, open Explore and select the provisioned `Loki` data source.
A useful first query is:

```logql
{job="edge-journal"}
```

---

## 12. Validate End-to-End Connectivity

From the edge node:

```bash
sudo wg show
ping -c 3 10.8.0.1
ssh ec2-user@10.8.0.1
```

From the cloud node:

```bash
sudo wg show
ping -c 3 10.8.0.3
curl http://10.8.0.3:9100/metrics
```

Expected results:

- WireGuard handshake is present on both sides
- The cloud node reaches the edge node over the overlay address
- Prometheus can scrape Node Exporter from the edge node over the overlay network

---

## 13. Quick Troubleshooting

Useful checks on the cloud node:

```bash
sudo journalctl -u wg-quick@wg0 -f
sudo wg show
sudo systemctl status docker --no-pager
sudo docker ps
sudo systemctl status node_exporter --no-pager
curl http://127.0.0.1:9100/metrics | head
curl http://127.0.0.1:3100/ready
```

Useful checks on the edge node:

```bash
sudo journalctl -u wwan.service -u wwan-monitor.service -f
sudo journalctl -u alloy -f
sudo wg show
ip addr
```

Common causes of failure:

- Reusing `10.8.0.2/32` while the bootstrap sample peer still exists
- Starting Alloy before Loki is reachable at `ALLOY_LOKI_URL`
- Changing `ALLOW_MONITORING_OVER_WIREGUARD` in `.env` without restarting the Docker stack

### Loki not reachable on `10.8.0.1:3100`

**Symptom:** `curl http://10.8.0.1:3100/ready` fails but `curl http://127.0.0.1:3100/ready` succeeds.

**Cause:** The monitoring containers are still bound to `127.0.0.1` from a previous run. The new `MONITORING_BIND_ADDRESS` value only takes effect after the stack is restarted.

Check which address Loki is actually bound to:

```bash
sudo ss -lntp | grep 3100
```

Fix — restart the stack so Docker picks up the updated bind address:

```bash
cd cloud/monitoring
sudo -E docker compose --env-file ../../.env down
sudo -E docker compose --env-file ../../.env up -d --force-recreate
curl http://10.8.0.1:3100/ready
```

### Alloy crash loop — corrupted positions file

**Symptom:** `alloy.service` enters a crash loop (`Start request repeated too quickly`) with this error in the journal:

```
invalid yaml positions file [.../loki.source.journal.system/positions.yml]: yaml: control characters are not allowed
```

**Cause:** Alloy's journal read-position tracking file gets corrupted (contains binary/control characters) if the Edge node suffers a sudden power loss or ungraceful restart. Alloy cannot start until the file is removed; it will recreate it cleanly on the next start.

Fix on the edge node:

```bash
sudo rm -f /var/lib/alloy/data/loki.source.journal.system/positions.yml
sudo systemctl reset-failed alloy
sudo systemctl start alloy
sudo systemctl status alloy --no-pager
sudo journalctl -u alloy -n 20 --no-pager
```

After recovery, Alloy replays up to `max_age` (default `1h`) of journald entries and begins forwarding to Loki.

### Clearing "Ghost" Jobs in Grafana & Prometheus (No Data / N/A showing on Gauges)

If you change a `job_name` in `prometheus.yml` (e.g. from `cloud-gateway` to `cloud-node`), the old name will still appear in Grafana dropdowns for 15 days, causing "N/A" values if selected. To wipe the old data immediately:

```bash
cd cloud/monitoring
set -a && source ../../.env && set +a
sudo docker compose stop prometheus
sudo docker compose rm -f prometheus
sudo docker volume rm monitoring_prometheus_data
sudo docker compose up -d
```
*(Similarly, if a provisioned dashboard is stuck in Grafana, stop grafana, remove `monitoring_grafana_data` volume or delete `/var/lib/grafana/grafana.db`, and restart).*

### Testing SWAP and CPU Load via `stress-ng` on Edge Nodes

To verify the dashboard metrics spike correctly under heavy load, install and run `stress-ng`:

```bash
sudo apt update && sudo apt install stress-ng -y
# Spike CPU (100% on 4 cores for 60s)
stress-ng --cpu 4 --timeout 60s
# Spike RAM and Force SWAP (allocate 120% of RAM, respawn if OOM killed, for 300s)
stress-ng --vm 4 --vm-bytes 120% --vm-keep --oomable --timeout 300s
```

---

## 14. Security Verification and Resiliency Auditing

To prove the core security guarantees of the WireGuard VPN overlay (specifically its resistance to Eavesdropping, Man-in-the-Middle (MITM), and Replay attacks), you can run the automated security verification suite on the Edge Node:

```bash
# Run all automated security scenarios (requires root)
sudo -E bash shared/scripts/verify-vpn-security.sh
```

You can also target specific scenarios individually:

* **Eavesdropping Resistance Test**: Captures network packets on the physical underlay interface (e.g. `eth0` or `wwan0`) using `tcpdump` and confirms that all sensitive payloads transmitted over the `wg0` interface are fully encrypted (ChaCha20-Poly1305 high-entropy bytes).
  ```bash
  sudo -E bash shared/scripts/verify-vpn-security.sh --eavesdropping
  ```
* **MITM & Impersonation Test**: Temporarily overrides the server's public key with a fake rogue key to prove that the client immediately drops all handshakes and silently discards untrusted traffic.
  ```bash
  sudo -E bash shared/scripts/verify-vpn-security.sh --mitm
  ```
* **Replay Attack Test**: Captures a valid WireGuard Handshake Initiation packet and replays it after a delay to prove that the gateway's TAI64N anti-replay mechanism silently ignores the stale packet and keeps the active session uninterrupted.
  ```bash
  sudo -E bash shared/scripts/verify-vpn-security.sh --replay
  ```

For a comprehensive breakdown of the threat model, cryptography foundations, and manual reproduction steps, see the dedicated [VPN Security Verification Guide](./VPN_SECURITY_VERIFICATION.md).

---

## 🇻🇳 Tiếng Việt

Tài liệu này hướng dẫn quy trình triển khai khuyến nghị cho dự án `wireguard-edge-cloud-5g` trong môi trường thực tế (production).
Để tra cứu nhanh các lệnh thông dụng, xem [COMMANDS.md](./COMMANDS.md).

Giả định của kho lưu trữ (repository):

- Kiến trúc VPN: `Client-to-Site (Edge-to-Cloud)`
- Máy chủ đám mây AWS EC2 đóng vai trò là cổng kết nối/máy chủ WireGuard trung tâm (server)
- Mỗi thiết bị biên (edge node) đóng vai trò là một WireGuard client thực hiện gọi kết nối tới endpoint public của server trên đám mây
- Lưu lượng mạng qua WireGuard mặc định được chia luồng (split-tunnel): chỉ dải mạng ảo overlay `10.8.0.0/24` mới được định tuyến qua VPN trừ khi biến `WIREGUARD_ALLOWED_IPS` được thay đổi rõ ràng
- Dải mạng ảo WireGuard (overlay network): `10.8.0.0/24`
- Địa chỉ IP giao diện mạng của WireGuard server: `10.8.0.1/24`
- Mỗi edge node sử dụng một địa chỉ client `/32` duy nhất, ví dụ `10.8.0.2/32`
- Đăng ký node (peer registration) được thực hiện thủ công để đảm bảo tính bảo mật tối đa.

---

## 1. Điều Kiện Tiên Quyết

Chuẩn bị các thành phần sau trước khi triển khai:

- Một tài khoản AWS với đầy đủ quyền tạo các tài nguyên: EC2, IAM, EIP, Security Group và Secrets Manager.
- Một AWS EC2 key pair có sẵn để kết nối SSH.
- Một public subnet và VPC nơi máy ảo EC2 sẽ khởi chạy.
- Tùy chọn: Một bản ghi DNS trỏ đến API Đăng Ký, ví dụ: `vpn-api.example.com`.
- Một thiết bị biên (edge node) đáp ứng:
  - Hệ điều hành Linux.
  - Hỗ trợ giao diện mạng WireGuard.
  - Bộ phần mềm tương thích Quectel WWAN/QMI nếu sử dụng kịch bản tự động hóa mạng di động 5G.

Cài đặt sẵn trên máy quản trị local:

- Phiên bản `terraform >= 1.9`
- `docker` và Docker Compose phiên bản v2
- `bash` shell

---

## 2. Chuẩn Bị Biến Môi Trường

Tạo tệp cấu hình môi trường triển khai:

```bash
cp .env.example .env
```

Tải các biến môi trường vào shell hiện tại:

```bash
set -a && . ./.env && set +a
```

Cập nhật tệp `.env` với các thông tin thực tế của bạn:

- `TF_VAR_admin_ssh_cidr`
- `TF_VAR_wireguard_port`
- `TF_VAR_wireguard_network`
- `TF_VAR_wireguard_client_cidr`
- `GRAFANA_ADMIN_PASSWORD`
- `PROMETHEUS_VERSION`
- `GRAFANA_VERSION`
- `LOKI_VERSION`
- `LOKI_PORT`
- `ALLOY_LOKI_URL`
- `ALLOY_HTTP_LISTEN_ADDR`
- `MONITORING_BIND_ADDRESS`
- `ALLOW_MONITORING_OVER_WIREGUARD`
- `WIREGUARD_PORT`
- `WIREGUARD_ALLOWED_IPS`
- `EDGE_EXTRA_TCP_PORTS`

Giá trị cấu hình cơ sở khuyến nghị:

- `TF_VAR_wireguard_network=10.8.0.0/24`
- `TF_VAR_wireguard_client_cidr=10.8.0.2/32`
- `TF_VAR_wireguard_port=51820`
- `WIREGUARD_PORT=51820`
- `WIREGUARD_ALLOWED_IPS=10.8.0.0/24`
- `MONITORING_BIND_ADDRESS=127.0.0.1`
- `LOKI_PORT=3100`
- `ALLOY_LOKI_URL=http://10.8.0.1:3100/loki/api/v1/push`
- `ALLOY_HTTP_LISTEN_ADDR=0.0.0.0:12345`
- `ALLOW_MONITORING_OVER_WIREGUARD=false`
- `EDGE_EXTRA_TCP_PORTS='443 5201'`
- `TF_VAR_admin_ssh_cidr='["<your-public-ip>/32"]'`

---

## 3. Cấu Hoinh Đầu Vào Cho Terraform

Kiểm tra tệp mẫu [cloud/terraform/ec2/terraform.tfvars.example](/home/hiengyen/CODE/wireguard-edge-cloud-5g/cloud/terraform/ec2/terraform.tfvars.example:1) và cung cấp các giá trị yêu cầu thông qua:

- Biến môi trường xuất ra kiểu `TF_VAR_*` từ `.env`
- Hoặc một tệp cấu hình cục bộ `terraform.tfvars` (không commit lên git)

Các thông số hạ tầng bắt buộc:

- `vpc_id`
- `subnet_id`
- `key_name`
- Tùy chọn: `instance_type`

Mặc định hiện tại trong repository:

- `instance_type=t3.medium`
- Sử dụng loại cấu hình instance lớn hơn nếu bạn dự kiến Prometheus, Grafana, Docker và WireGuard sẽ cùng chạy đồng thời dưới mức tải cao liên tục.

---

## 4. Khởi Tạo Cloud Node

Khởi chạy các lệnh sau:

```bash
set -a && . ./.env && set +a
cd cloud/terraform/ec2
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Nếu bạn tăng dung lượng RAM trên một hệ thống đang chạy, hãy kiểm tra kỹ kết quả lệnh plan vì việc thay đổi `instance_type` sẽ cập nhật lại phần cứng máy ảo EC2.

Lấy thông tin đầu ra (outputs):

- IP Public của EC2 (Elastic IP)
- Cổng kết nối WireGuard Endpoint
- ID của Security Group

Các lệnh hữu ích:

```bash
terraform output public_ip
terraform output wireguard_endpoint
```

Các thành phần Terraform tự động thiết lập:

- Máy ảo EC2 chạy Amazon Linux 2023
- Phân vùng root được mã hóa
- Elastic IP cố định
- Vai trò IAM (IAM Role) cho phép truy cập Secrets Manager
- Kịch bản khởi tạo máy chủ WireGuard
- Các gói công cụ cơ sở cài sẵn cho quản trị viên trên Cloud Node: `curl`, `rsync`, `iperf3`, `git`, `tmux`, `stow`, `vim`, `wget`, `docker`, và Docker Compose v2

---

## 5. Xác Thực Trạng Thái Cloud Node

Kết nối SSH tới máy ảo:

```bash
ssh -i <your-key.pem> ec2-user@<elastic-ip>
```

Kiểm tra trạng thái dịch vụ:

```bash
sudo systemctl status wg-quick@wg0
```

Kiểm tra cấu hình WireGuard:

```bash
sudo wg show
sudo cat /etc/wireguard/wg0.conf
sudo cat /etc/wireguard/server_public.key
```

Kiểm tra các cổng mạng đang lắng nghe:

```bash
sudo ss -lntp | grep 51820
```

Kết quả mong đợi:

- Giao diện `wg0` hoạt động bình thường (`active`).

Lưu ý quan trọng:

- Script khởi động ban đầu `user_data.sh` sẽ tạo sẵn một peer mẫu sử dụng IP `10.8.0.2/32`.
- If thiết bị edge thực tế đầu tiên của bạn cũng dùng IP `10.8.0.2/32`, hãy xóa hoặc thay thế peer mẫu đó trước khi thực hiện đăng ký khóa (client public key) thực tế.

---

## 6. Làm Cứng Hệ Thống (Hardening) Cloud Node

Trước khi khởi động cụm giám sát (monitoring stack), hãy bảo mật máy chủ đám mây và cài đặt agent thu thập metric:

```bash
set -a && . ./.env && set +a
sudo -E bash shared/scripts/hardening.sh
sudo -E bash shared/scripts/install-node-exporter.sh
```

Kiểm tra trạng thái Node Exporter trên máy chủ cloud:

```bash
sudo systemctl status node_exporter --no-pager
curl http://127.0.0.1:9100/metrics | head
```

---

## 7. Kích Hoạt Giám Sát Trên Cloud Node

Thực hiện trên máy chủ đám mây:

```bash
cd cloud/monitoring
```

Cụm dịch vụ giám sát đi kèm sẵn **Dashboard Tổng Hợp (Unified Edge & Cloud)** để quản lý tập trung toàn bộ hệ thống trên một màn hình duy nhất.

Để khởi động cụm giám sát:

```bash
# Sử dụng flag -E để giữ lại các biến môi trường được tải từ tệp .env
sudo -E docker compose --env-file ../../.env up -d --force-recreate
```

Hoặc sử dụng script wrapper để tự động kiểm tra biến cấu hình và thiết lập quyền truy cập `ALLOW_MONITORING_OVER_WIREGUARD`:

```bash
sudo -E bash cloud/monitoring/setup-monitoring.sh
```

Xác thực hoạt động:

```bash
sudo docker ps
curl http://127.0.0.1:9090/-/healthy
curl http://127.0.0.1:3100/ready
curl http://127.0.0.1:3000/api/health
```

Lưu ý:

- Prometheus, Loki và Grafana mặc định chỉ lắng nghe địa chỉ cục bộ `127.0.0.1`. Để có thể truy cập qua đường hầm WireGuard thay vì thiết lập SSH tunnel, đặt biến `ALLOW_MONITORING_OVER_WIREGUARD=true` trong `.env` trước khi chạy `hardening.sh` và khởi động stack. Script wrapper sẽ tự động xử lý việc này; nếu dùng lệnh `docker compose` trực tiếp, bạn cần xuất biến `MONITORING_BIND_ADDRESS=10.8.0.1` trước.
- Grafana tự động cấu hình các nguồn dữ liệu Prometheus và Loki từ tệp `cloud/monitoring/grafana/provisioning/datasources/datasources.yml`.

Để truy cập giao diện quản trị Web thông qua SSH tunnel từ máy tính của bạn:

> Các địa chỉ SSH tunnel bên dưới giả định biến `ALLOW_MONITORING_OVER_WIREGUARD=true` (`MONITORING_BIND_ADDRESS=10.8.0.1`).
> Nếu cụm giám sát của bạn chỉ bind tới `127.0.0.1`, hãy thay thế địa chỉ `10.8.0.1` thành `127.0.0.1` trong các tham số `-L` của cloud.

```bash
# -N để giữ kết nối tunnel luôn mở mà không khởi chạy shell command
ssh -i <your-key.pem> -N \
  -L 3000:10.8.0.1:3000 \
  -L 9090:10.8.0.1:9090 \
  -L 3100:10.8.0.1:3100 \
  -L 9100:10.8.0.1:9100 \
  -L 12345:10.8.0.2:12345 \
  -L 4000:10.8.0.1:4000 \
  -L 5173:10.8.0.1:5173 \
  ec2-user@<elastic-ip>
```

Sau đó truy cập trên trình duyệt local:

- Grafana: `http://127.0.0.1:3000`
- Prometheus: `http://127.0.0.1:9090`
- Loki: `http://127.0.0.1:3100/ready`
- Node Exporter (Cloud): `http://127.0.0.1:9100/metrics`
- Alloy UI (Edge): `http://127.0.0.1:12345`
- PeerSight API: `http://127.0.0.1:4000/health`
- Giao diện PeerSight: `http://127.0.0.1:5173`

> **Điều kiện tiên quyết cho Alloy UI:** Script `install-alloy.sh` cấu hình tham số khởi chạy `CUSTOM_ARGS="--server.http.listen-addr=0.0.0.0:12345"` để
> giao diện UI có thể truy cập được thông qua đường hầm WireGuard. Hãy mở cổng này trên tường lửa (UFW) của Edge Node (chỉ cần làm một lần):
> `sudo ufw allow in on wg0 to any port 12345 proto tcp`

---

## 8. Cấu Hình Thiết Bị Biên (Edge Node)

Thực hiện trên thiết bị biên:

```bash
set -a && . ./.env && set +a
cd edge/5g-wwan
sudo -E bash install.sh
```

Nếu bạn chạy phân hệ mạng di động qua Docker Container:

```bash
set -a && . ./.env && set +a
cd edge/5g-wwan/docker
sudo -E docker compose up -d
```

Kiểm tra trạng thái kết nối mạng di động WWAN:

```bash
ip addr
systemctl status wwan.service
systemctl status wwan-monitor.service
```

Trình cài đặt ở thiết bị biên cũng sẽ tự động cài sẵn:

- Các gói công cụ hữu dụng: `curl`, `rsync`, `iperf3`, `git`, `tmux`, `stow`, `vim`, `wget`, `docker`, và Docker Compose v2
- Tường lửa `ufw` trên các hệ thống dùng apt-based và các hệ thống dùng dnf-based (khi gói tin có sẵn trong các repositories đã bật)

---

## 9. Gia Nhập Mạng VPN Mạng Ảo Overlay

Yêu cầu chuẩn bị:

- Bạn có quyền kết nối SSH tới Cloud Node.
- Có sẵn khóa công khai của server (Server Public Key) lấy từ `/etc/wireguard/server_public.key`.

Khởi chạy script cấu hình client trên Edge Node:

```bash
set -a && . ./.env && set +a
sudo -E bash edge/vpn/setup-wg-client.sh
```

Các tham số cấu hình khuyến nghị:

- `Server endpoint IP/Domain`: Nhập Elastic IP của EC2 hoặc tên miền DNS công khai của Cloud Server.
- `Server port`: Nhập `51820`.
- `Server public key`: Nhập kết quả của lệnh `sudo cat /etc/wireguard/server_public.key`.
- `Client IP`: Nhập một địa chỉ IP `/32` duy nhất, ví dụ `10.8.0.3/32` (nếu IP `10.8.0.2/32` đã bị chiếm dụng bởi peer mẫu ban đầu).
- `Allowed IPs`: Nhập `10.8.0.0/24`.

Script client sẽ tự động tạo cặp khóa và in ra khóa công khai của client (Client Public Key). Hãy đăng ký peer thủ công trên Cloud Node bằng lệnh sau:

```bash
sudo wg set wg0 peer <client-public-key> allowed-ips 10.8.0.3/32
sudo wg-quick save wg0
```

Xác thực trạng thái từ Cloud Node:

```bash
sudo wg show
```

Nếu bạn cần gỡ bỏ cấu hình WireGuard client cục bộ trên Edge Node sau này:

```bash
sudo -E bash edge/vpn/uninstall-wg-client.sh
```

Để xóa toàn bộ cặp khóa mã hóa local:

```bash
sudo -E REMOVE_WG_KEYS=true bash edge/vpn/uninstall-wg-client.sh
```

*Lưu ý: Lệnh này chỉ dọn dẹp cấu hình ở Edge local. Bạn cần thực hiện gỡ bỏ peer thủ công trên Cloud Server một cách độc lập nếu trước đó đã đăng ký.*

---

## 10. Làm Cứng Thiết Bị Biên (Edge Node)

Sau khi Edge Node đã kết nối thành công vào mạng ảo VPN, hãy bảo mật thiết bị biên và cài đặt Node Exporter:

```bash
set -a && . ./.env && set +a
sudo -E bash shared/scripts/hardening.sh
sudo -E bash shared/scripts/install-node-exporter.sh
```

Nếu Edge Node chưa có tệp cấu hình `authorized_keys`, script bảo mật sẽ **bỏ qua phần làm cứng cấu hình SSH** và in ra cảnh báo sau:

```
[WARN] No authorized_keys file found. Skipping SSH hardening (password login remains enabled).
[WARN] Run this script again after setting up SSH key authentication.
```

Tường lửa (UFW) và dịch vụ chống dò mật khẩu Fail2Ban vẫn được thiết lập bình thường. Chế độ đăng nhập SSH bằng mật khẩu vẫn duy trì cho tới khi bạn hoàn tất bước cấu hình SSH Key tiếp theo dưới đây.

### 10.1. Cấu Hình Xác Thực Qua SSH Key Và Làm Cứng Lại Hệ Thống

Để hoàn tất quy trình làm cứng SSH, trước tiên hãy thiết lập xác thực bằng khóa công khai.

*Hãy luôn duy trì phiên kết nối SSH hiện tại trên Edge Node để làm phương án dự phòng an toàn suốt quá trình thực hiện.*

**On your local machine (máy tính cá nhân của bạn)**, sao chép khóa công khai tới Edge Node:

```bash
ssh-copy-id <user>@<edge-ip>
```

Or manually (hoặc thực hiện thủ công) — lấy khóa công khai trên máy local của bạn:

```bash
cat ~/.ssh/id_ed25519.pub
```

Sau đó dán khóa này vào Edge Node (trong phiên kết nối SSH đang mở):

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "ssh-ed25519 AAAA..." >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Nếu bạn chưa có cặp khóa SSH, hãy tạo mới một cặp trên máy tính local của bạn:

```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
```

**Kiểm tra xem đăng nhập qua SSH Key hoạt động chưa** bằng cách mở một **cửa sổ terminal mới** (giữ nguyên kết nối cũ):

```bash
ssh -o PasswordAuthentication=no <user>@<edge-ip>
```

Khi đã xác nhận đăng nhập qua SSH Key hoạt động thành công, chạy lại script làm cứng hệ thống để vô hiệu hóa hoàn toàn phương thức đăng nhập bằng mật khẩu thông thường:

```bash
set -a && . ./.env && set +a
sudo -E bash shared/scripts/hardening.sh
```

Xác thực Node Exporter trên Edge:

```bash
sudo systemctl status node_exporter --no-pager
curl http://127.0.0.1:9100/metrics | head
```

---

## 11. Đẩy Log Tự Động Từ Edge Node Với Grafana Alloy

Khởi chạy dịch vụ Grafana Alloy trên Edge Node sau khi đường hầm VPN WireGuard đã được thiết lập thành công và có thể thông suốt tới địa chỉ IP mạng ảo Cloud Server.
Cấu hình mặc định của Alloy sẽ đọc log hệ thống từ `journald` và đẩy tự động về Loki tại địa chỉ: `http://10.8.0.1:3100/loki/api/v1/push`.
Để phân hệ này hoạt động, cụm dịch vụ giám sát trên đám mây phải được chạy với tham số `MONITORING_BIND_ADDRESS=10.8.0.1` và cho phép giám sát qua mạng ảo WireGuard trong lệnh làm cứng hệ thống.

> [!WARNING]
> **Yêu Cầu Đồng Bộ Giờ Hệ Thống Trên Thiết Bị Biên (Edge Node)!**  
> Vì các thiết bị nhúng chạy chip ARM (như Orange Pi) thường không tích hợp sẵn pin dự phòng RTC để lưu giờ phần cứng, thời gian của máy có thể bị sai lệch nghiêm trọng (lệch vài ngày đến vài tháng) sau khi mất điện đột ngột hoặc khởi động lại. Dịch vụ Loki sẽ tự động từ chối (reject) bất kỳ bản ghi log nào có mốc giờ quá lệch so với thời gian hiện tại của máy chủ, dẫn đến việc không hiển thị log trên màn hình Grafana.
>
> **Luôn xác thực và đồng bộ thời gian của Edge Node trước khi khởi chạy Alloy:**
>
> * **Cách A: Tự động đồng bộ NTP (Yêu cầu kết nối Internet)**
>   ```bash
>   date
>   sudo timedatectl set-ntp true
>   sudo systemctl restart systemd-timesyncd
>   ```
>
> * **Cách B: Đồng bộ thủ công bằng tay**
>   ```bash
>   sudo date -s "2026-06-03 15:12:20"
>   ```
>
> * **Cách C: Đồng bộ ngoại tuyến qua GPS/GNSS (Module Quectel)**
>   Nếu thiết bị Edge không có kết nối internet để chạy NTP, bạn có thể sử dụng GPS tích hợp trên module Quectel RM502Q-GL:
>   1. Định tuyến và kích hoạt GNSS qua lệnh AT (gửi tới cổng AT, thường là `/dev/ttyUSB2` hoặc `/dev/ttyMHI2`):
>      ```bash
>      sudo sh -c 'echo -e "AT+QGPSCFG=\"outport\",\"usbnmea\"\r" > /dev/ttyUSB2'
>      sudo sh -c 'echo -e "AT+QGPS=1\r" > /dev/ttyUSB2'
>      ```
>   2. Kiểm tra luồng dữ liệu NMEA hoạt động: `cat /dev/ttyUSB1` (hoặc `/dev/ttyMHI1`).
>   3. Cài đặt `gpsd` và `ntpsec`: `sudo apt-get install gpsd gpsd-clients ntpsec -y`.
>   4. Cấu hình `/etc/default/gpsd` sử dụng cổng NMEA (ví dụ: `DEVICES="/dev/ttyUSB1"`). Khởi động lại: `sudo systemctl restart gpsd`.
>   5. Tắt client NTP mặc định của hệ thống: `sudo systemctl disable --now systemd-timesyncd`.
>   6. Thêm cấu hình đồng hồ tham chiếu sau vào `/etc/ntpsec/ntp.conf`:
>      ```text
>      refclock shm unit 0 time1 0.125 refid GPS prefer
>      ```
>   7. Khởi động lại dịch vụ NTPsec: `sudo systemctl restart ntpsec`.

```bash
set -a && . ./.env && set +a
sudo -E bash edge/observability/alloy/install-alloy.sh
```

Ghi đè địa chỉ đích đẩy log nếu IP mạng ảo hoặc cổng Loki của bạn có sự thay đổi:

```bash
sudo -E ALLOY_LOKI_URL=http://10.8.0.1:3100/loki/api/v1/push bash edge/observability/alloy/install-alloy.sh
```

Xác thực trạng thái dịch vụ Alloy:

```bash
sudo systemctl status alloy --no-pager
sudo journalctl -u alloy --no-pager

# Xác nhận dịch vụ Alloy đang lắng nghe cổng 12345
ss -lntp | grep 12345

# Kiểm tra phản hồi nhanh cục bộ
curl http://127.0.0.1:12345
```

### Truy Cập Giao Diện Web Grafana Alloy UI

Alloy cung cấp một giao diện đồ thị luồng pipeline và trạng thái linh kiện (components) tại cổng `12345`.
Script `install-alloy.sh` tự động cấu hình tham số `CUSTOM_ARGS="--server.http.listen-addr=0.0.0.0:12345"` để bạn truy cập được giao diện này từ xa qua mạng ảo WireGuard.

Để kết nối thông suốt, mở cổng trên tường lửa UFW tại Edge Node:

```bash
sudo ufw allow in on wg0 to any port 12345 proto tcp
```

Sau đó, trên máy tính local của bạn, thêm dòng chuyển tiếp cổng Alloy vào lệnh tạo SSH tunnel:

```bash
ssh -i <your-key.pem> -N \
  -L 12345:10.8.0.2:12345 \
  ec2-user@<elastic-ip>
```

Truy cập `http://127.0.0.1:12345` trên trình duyệt máy tính của bạn. Giao diện hiển thị:

- **Graph** — Bản đồ đồ thị luồng xử lý log theo thời gian thực.
- **Components** — Trạng thái chi tiết của các module như `loki.source.journal`, `loki.write.cloud`,...

Tại Grafana, mở tab Explore và chọn nguồn dữ liệu (datasource) `Loki` đã được cấu hình sẵn.
Truy vấn log nhanh bằng câu lệnh LogQL:

```logql
{job="edge-journal"}
```

---

## 12. Xác Thực Kiểm Thử Kết Nối Hệ Thống Đầu Cuối

Thực hiện từ thiết bị biên (Edge Node):

```bash
sudo wg show
ping -c 3 10.8.0.1
ssh ec2-user@10.8.0.1
```

Thực hiện từ máy chủ đám mây (Cloud Node):

```bash
sudo wg show
ping -c 3 10.8.0.3
curl http://10.8.0.3:9100/metrics
```

Kết quả kỳ vọng:

- Trạng thái bắt tay WireGuard (Handshake) cập nhật mới trên cả 2 node.
- Cloud Node kết nối thông suốt tới Edge Node qua dải mạng ảo overlay.
- Prometheus trên máy chủ Cloud có thể cào metrics (scrape) từ Node Exporter chạy tại Edge Node qua mạng ảo.

---

## 13. Hướng Dẫn Gỡ Lỗi Nhanh (Troubleshooting)

Các lệnh kiểm tra hữu ích trên máy chủ đám mây (Cloud Node):

```bash
sudo journalctl -u wg-quick@wg0 -f
sudo wg show
sudo systemctl status docker --no-pager
sudo docker ps
sudo systemctl status node_exporter --no-pager
curl http://127.0.0.1:9100/metrics | head
curl http://127.0.0.1:3100/ready
```

Các lệnh kiểm tra hữu ích trên thiết bị biên (Edge Node):

```bash
sudo journalctl -u wwan.service -u wwan-monitor.service -f
sudo journalctl -u alloy -f
sudo wg show
ip addr
```

Các nguyên nhân gây lỗi phổ biến:

- Cố tình dùng IP trùng lặp `10.8.0.2/32` khi peer mẫu ban đầu vẫn còn tồn tại trên server.
- Khởi động dịch vụ đẩy log Alloy trước khi Loki trên Cloud sẵn sàng nhận dữ liệu tại địa chỉ `ALLOY_LOKI_URL`.
- Thay đổi cấu hình biến `ALLOW_MONITORING_OVER_WIREGUARD` trong `.env` nhưng quên chưa khởi động lại cụm container Docker.

### Loki không kết nối được tới Loki trên địa chỉ `10.8.0.1:3100`

**Triệu chứng:** Thử lệnh `curl http://10.8.0.1:3100/ready` thất bại nhưng `curl http://127.0.0.1:3100/ready` thành công.

**Nguyên nhân:** Các containers của cụm giám sát vẫn đang lắng nghe cục bộ trên `127.0.0.1` của các lần khởi chạy trước đó. Biến cấu hình `MONITORING_BIND_ADDRESS` mới chỉ có tác dụng sau khi cụm containers được tái khởi tạo hoàn toàn.

Kiểm tra địa chỉ thực tế Loki đang lắng nghe bằng lệnh:

```bash
sudo ss -lntp | grep 3100
```

Cách khắc phục — Restart cụm containers để Docker nhận cấu hình cổng bind mới:

```bash
cd cloud/monitoring
sudo -E docker compose --env-file ../../.env down
sudo -E docker compose --env-file ../../.env up -d --force-recreate
curl http://10.8.0.1:3100/ready
```

### Lỗi Alloy lặp vòng lặp crash (crash loop) do tệp positions bị lỗi

**Triệu chứng:** Dịch vụ `alloy.service` rơi vào vòng lặp lỗi khởi động liên tục (`Start request repeated too quickly`) đi kèm thông báo log lỗi sau:

```
invalid yaml positions file [.../loki.source.journal.system/positions.yml]: yaml: control characters are not allowed
```

**Nguyên nhân:** Tệp theo dõi tiến trình đọc log hệ thống (`positions.yml`) của Alloy bị lỗi định dạng nhị phân/kí tự điều khiển khi Edge Node bị mất điện đột ngột hoặc tắt máy không đúng quy trình an toàn. Alloy sẽ từ chối khởi chạy cho tới khi tệp này được xóa; nó sẽ tự sinh lại tệp mới hoàn toàn sạch sẽ khi khởi động lại thành công.

Cách khắc phục trên Edge Node:

```bash
sudo rm -f /var/lib/alloy/data/loki.source.journal.system/positions.yml
sudo systemctl reset-failed alloy
sudo systemctl start alloy
sudo systemctl status alloy --no-pager
sudo journalctl -u alloy -n 20 --no-pager
```

Sau khi khôi phục, Alloy sẽ quét lại tối đa `max_age` (mặc định là `1h`) các bản ghi log hệ thống cũ của `journald` và tiếp tục đẩy dữ liệu về Loki.

### Dọn Dẹp Dữ Liệu Rác (Ghost Jobs) hiển thị sai trên Gauges của Grafana & Prometheus

Nếu bạn thay đổi tên `job_name` trong file cấu hình `prometheus.yml` (ví dụ từ `cloud-gateway` thành `cloud-node`), tên cấu hình cũ vẫn sẽ tồn tại trong danh sách chọn của Grafana suốt 15 ngày, gây hiển thị lỗi "N/A" khi chọn. Để dọn dẹp các mốc dữ liệu cũ này ngay lập tức:

```bash
cd cloud/monitoring
set -a && source ../../.env && set +a
sudo docker compose stop prometheus
sudo docker compose rm -f prometheus
sudo docker volume rm monitoring_prometheus_data
sudo docker compose up -d
```
*(Tương tự, nếu một giao diện dashboard bị kẹt lỗi trên Grafana, hãy tắt grafana, xóa docker volume `monitoring_grafana_data` hoặc xóa file cơ sở dữ liệu `/var/lib/grafana/grafana.db` và khởi động lại cụm giám sát).*

### Thử Nghiệm Ép SWAP Và Tải CPU thông qua stress-ng trên Edge Nodes

Để kiểm tra xem dashboard giám sát có hiển thị đúng mức độ tải của hệ thống hay không, hãy cài đặt và chạy công cụ ép tải `stress-ng`:

```bash
sudo apt update && sudo apt install stress-ng -y
# Ép tải CPU (Tăng 100% tải trên cả 4 nhân trong vòng 60 giây)
stress-ng --cpu 4 --timeout 60s
# Ép dung lượng bộ nhớ RAM và ép sử dụng phân vùng SWAP (tạo bộ nhớ ảo tương đương 120% RAM vật lý, tự động hồi phục nếu bị OOM kill, chạy trong 300 giây)
stress-ng --vm 4 --vm-bytes 120% --vm-keep --oomable --timeout 300s
```

---

## 14. Kiểm Thử Bảo Mật Và Đánh Giá Khả Năng Chống Chịu (Security Verification)

Để xác thực các cam kết bảo mật lõi của đường hầm VPN overlay WireGuard (cụ thể là khả năng chống nghe lén dữ liệu, tấn công giả mạo Man-in-the-Middle (MITM), và tấn công phát lại (Replay attacks)), bạn có thể kích hoạt bộ kịch bản kiểm thử bảo mật tự động trên Edge Node:

```bash
# Thực hiện toàn bộ các kịch bản kiểm thử bảo mật tự động (yêu cầu quyền root)
sudo -E bash shared/scripts/verify-vpn-security.sh
```

Bạn cũng có thể chỉ định chạy kiểm thử một kịch bản bảo mật riêng lẻ:

* **Kiểm thử khả năng chống nghe lén (Eavesdropping Resistance)**: Bắt các gói tin di chuyển trên cổng vật lý vật lý dưới nền (ví dụ `eth0` hoặc `wwan0`) bằng công cụ `tcpdump` và kiểm tra để đảm bảo toàn bộ dữ liệu nhạy cảm truyền qua interface `wg0` đều được mã hóa hoàn toàn thành các ký tự Entropy ngẫu nhiên (sử dụng mật mã ChaCha20-Poly1305 độ bảo mật cao).
  ```bash
  sudo -E bash shared/scripts/verify-vpn-security.sh --eavesdropping
  ```
* **Kiểm thử khả năng chống giả mạo & MITM (MITM & Impersonation)**: Tạm thời ghi đè một khóa Public Key giả mạo của Server để chứng minh Client sẽ ngay lập tức từ chối và ngắt toàn bộ phiên kết nối bắt tay (handshake), đồng thời lặng lẽ hủy bỏ tất cả lưu lượng dữ liệu không đáng tin cậy.
  ```bash
  sudo -E bash shared/scripts/verify-vpn-security.sh --mitm
  ```
* **Kiểm thử khả năng chống tấn công phát lại (Replay Attack)**: Tiến hành bắt lại một gói tin Bắt Tay Khởi Tạo (Handshake Initiation) hợp lệ của WireGuard và phát lại (replay) gói tin đó sau một khoảng thời gian trễ để chứng tỏ cơ chế chặn tấn công phát lại TAI64N của Server sẽ âm thầm bỏ qua gói tin lỗi thời đó và giữ nguyên kết nối hoạt động hiện tại ổn định.
  ```bash
  sudo -E bash shared/scripts/verify-vpn-security.sh --replay
  ```

Để hiểu rõ chi tiết về mô hình đe dọa (threat model), nền tảng mã hóa học và hướng dẫn các bước tái lập thủ công bằng tay, xem tài liệu chi tiết tại [VPN Security Verification Guide](./VPN_SECURITY_VERIFICATION.md).
