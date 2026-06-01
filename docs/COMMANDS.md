# Common Commands | Các Lệnh Thông Dụng

🇬🇧 [English](#-english) | 🇻🇳 [Tiếng Việt](#-tiếng-việt)

---

## 🇬🇧 English

This file groups the commands most commonly used while deploying and operating `wireguard-edge-cloud-5g`.

Current VPN topology: `Client-to-Site (Edge-to-Cloud)`.
The cloud node is the WireGuard server/gateway and each edge node joins as a client.

## Environment

```bash
cp .env.example .env
set -a && . ./.env && set +a
```

## Terraform Cloud Provisioning

```bash
cd cloud/terraform/ec2
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output public_ip
terraform output wireguard_endpoint
```

## Cloud Access

```bash
ssh -i <your-key.pem> ec2-user@<EC2_PUBLIC_IP>
```

## Edge WWAN

Native install:

```bash
cd edge/5g-wwan
sudo -E bash install.sh
sudo systemctl status wwan.service
sudo systemctl status wwan-monitor.service
```

Docker mode:

```bash
cd edge/5g-wwan/docker
sudo docker compose up -d
```

## WireGuard Client Join (Edge -> Cloud)

```bash
set -a && . ./.env && set +a
sudo -E bash edge/vpn/setup-wg-client.sh
```

Manual peer registration on the cloud node:

```bash
sudo wg set wg0 peer <client-public-key> allowed-ips 10.8.0.3/32
sudo wg-quick save wg0
sudo wg show
```

Remove the local WireGuard client setup from the edge node:

```bash
sudo -E bash edge/vpn/uninstall-wg-client.sh
```

Remove the local key pair too:

```bash
sudo -E REMOVE_WG_KEYS=true bash edge/vpn/uninstall-wg-client.sh
```

## Monitoring Stack

Start monitoring on the cloud node:

```bash
cd cloud/monitoring
sudo docker compose --env-file ../../.env up -d
sudo docker ps
curl http://127.0.0.1:9090/-/healthy
curl http://127.0.0.1:3100/ready
curl http://127.0.0.1:3000/api/health
```

Or use the wrapper script (handles `ALLOW_MONITORING_OVER_WIREGUARD` and validates `GRAFANA_ADMIN_PASSWORD` automatically):

```bash
sudo -E bash cloud/monitoring/setup-monitoring.sh
```

Grafana loads Prometheus and Loki from `cloud/monitoring/grafana/provisioning/datasources/datasources.yml`.

Expose Grafana, Prometheus, and Loki through WireGuard only:

```bash
# In .env: set ALLOW_MONITORING_OVER_WIREGUARD=true
sudo -E bash shared/scripts/hardening.sh
cd cloud/monitoring
sudo docker compose --env-file ../../.env down
sudo docker compose --env-file ../../.env up -d
```

Or with the wrapper (sets `MONITORING_BIND_ADDRESS=10.8.0.1` automatically from `ALLOW_MONITORING_OVER_WIREGUARD`):

```bash
sudo -E bash cloud/monitoring/setup-monitoring.sh down
sudo -E bash cloud/monitoring/setup-monitoring.sh
```

## SSH Tunnels For Web UI

Grafana, Prometheus, Loki, and Node Exporter:

```bash
# If MONITORING_BIND_ADDRESS is 10.8.0.1, change 127.0.0.1 below to 10.8.0.1
ssh -i <your-key.pem> \
  -L 3000:127.0.0.1:3000 \
  -L 9090:127.0.0.1:9090 \
  -L 3100:127.0.0.1:3100 \
  -L 9100:127.0.0.1:9100 \
  ec2-user@<EC2_PUBLIC_IP>
```

Open locally:
- `http://127.0.0.1:3000`
- `http://127.0.0.1:9090`
- `http://127.0.0.1:3100/ready`
- `http://127.0.0.1:9100/metrics`

## Edge Alloy

Install Alloy on the edge node after WireGuard can reach the cloud overlay address:
the default `ALLOY_LOKI_URL` expects cloud Loki to be reachable at `10.8.0.1:3100`.

```bash
set -a && . ./.env && set +a
sudo -E bash edge/observability/alloy/install-alloy.sh
sudo systemctl status alloy --no-pager
sudo journalctl -u alloy --no-pager
```

`install-alloy.sh` sets `CUSTOM_ARGS="--server.http.listen-addr=0.0.0.0:12345"` so the UI is
reachable over WireGuard. Override the listen address if needed:

```bash
sudo -E ALLOY_HTTP_LISTEN_ADDR=0.0.0.0:12345 bash edge/observability/alloy/install-alloy.sh
```

Override the Loki push endpoint if the cloud overlay IP or port is different:

```bash
sudo -E ALLOY_LOKI_URL=http://10.8.0.1:3100/loki/api/v1/push bash edge/observability/alloy/install-alloy.sh
```

Access the Alloy UI from your laptop via SSH tunnel through EC2:

```bash
# One-time: open port on edge UFW
sudo ufw allow in on wg0 to any port 12345 proto tcp

# On laptop
ssh -i <your-key.pem> -N -L 12345:10.8.0.2:12345 ec2-user@<EC2_PUBLIC_IP>
# Open: http://127.0.0.1:12345
```

Uninstall local Alloy service/config:

```bash
sudo -E bash edge/observability/alloy/uninstall-alloy.sh
```

## Node Exporter

Install:

```bash
sudo -E bash shared/scripts/install-node-exporter.sh
```

Install with a specific version:

```bash
sudo -E NODE_EXPORTER_VERSION=1.11.1 bash shared/scripts/install-node-exporter.sh
```

Verify:

```bash
sudo systemctl status node_exporter --no-pager
ss -lntp | grep 9100
curl http://127.0.0.1:9100/metrics | head
```

Scrape edge metrics from the cloud node:

```bash
curl http://10.8.0.3:9100/metrics | head
```

## Hardening

Default:

```bash
sudo -E bash shared/scripts/hardening.sh
```

With custom WireGuard port:

```bash
sudo -E WIREGUARD_PORT=51821 bash shared/scripts/hardening.sh
```

With monitoring access over WireGuard:

```bash
sudo -E ALLOW_MONITORING_OVER_WIREGUARD=true WIREGUARD_NETWORK=10.8.0.0/24 bash shared/scripts/hardening.sh
```

With custom extra edge TCP ports:

```bash
sudo -E EDGE_EXTRA_TCP_PORTS='443 5201' bash shared/scripts/hardening.sh
```

## File Transfer Tests

Create a sample dataset:

```bash
mkdir -p ~/dataset/sample-set
fallocate -l 1G ~/dataset/sample-set/blob-1g.bin
for i in $(seq 1 100); do
  head -c 1048576 /dev/urandom > ~/dataset/sample-set/file-${i}.bin
done
du -sh ~/dataset/sample-set
```

Rsync over WireGuard:

```bash
rsync -avhP --partial --append-verify \
  ~/dataset/sample-set/ \
  ec2-user@10.8.0.1:/home/ec2-user/dataset/sample-set/
```

Quick SCP test:

```bash
echo "wireguard test $(date -Iseconds)" > /tmp/wg-test.txt
scp /tmp/wg-test.txt ec2-user@10.8.0.1:/tmp/
ssh ec2-user@10.8.0.1 'cat /tmp/wg-test.txt'
```

## Benchmark Suite

Run all non-destructive suites:

```bash
bash benchmark/run_all.sh
```

Run specific suites:

```bash
bash benchmark/run_all.sh --suite 01,02      # connectivity + bandwidth
bash benchmark/run_all.sh --suite 03         # services health
bash benchmark/run_all.sh --suite 05         # end-to-end full stack
```

Run a single script:

```bash
bash benchmark/01-connectivity/test_ping_latency.sh
bash benchmark/02-bandwidth/test_iperf3_tcp.sh
bash benchmark/03-services/test_prometheus.sh
bash benchmark/05-e2e/test_full_stack.sh
```

Override thresholds or targets inline:

```bash
IPERF3_DURATION=30 WG_SERVER_IP=10.8.0.1 bash benchmark/run_all.sh 02
set -a && . .env && set +a && bash benchmark/run_all.sh 03
```

Enable destructive tests (WWAN reconnect, failover):

```bash
sudo -E bash benchmark/run_all.sh --allow-destructive
```

iperf3 server (start on cloud gateway before running suite 02 or 04):

```bash
iperf3 -s -D
```

## Troubleshooting

Cloud:

```bash
sudo journalctl -u wg-quick@wg0 -f
sudo wg show
sudo systemctl status docker --no-pager
sudo docker ps
sudo systemctl status node_exporter --no-pager
curl http://127.0.0.1:9100/metrics | head
curl http://127.0.0.1:3100/ready
```

Edge:

```bash
sudo journalctl -u wwan.service -u wwan-monitor.service -f
sudo journalctl -u alloy -f
sudo wg show
ip addr
```

## VPN Security Verification

Run automated security validation tests on the Edge node:

```bash
# Run the complete verification suite (Eavesdropping, MITM, Replay)
sudo -E bash shared/scripts/verify-vpn-security.sh

# Run only packet sniffing / encryption verification
sudo -E bash shared/scripts/verify-vpn-security.sh --eavesdropping

# Run only man-in-the-middle / gateway impersonation test
sudo -E bash shared/scripts/verify-vpn-security.sh --mitm

# Run only TAI64N anti-replay protection test
sudo -E bash shared/scripts/verify-vpn-security.sh --replay
```

---

## 🇻🇳 Tiếng Việt

Tài liệu này tổng hợp các câu lệnh được sử dụng phổ biến nhất trong quá trình triển khai và vận hành hệ thống `wireguard-edge-cloud-5g`.

Kiến trúc VPN hiện tại: `Client-to-Site (Edge-to-Cloud)`.
Trong đó, Cloud Node đóng vai trò là WireGuard server/gateway và mỗi Edge Node đóng vai trò là một client kết nối vào.

## Biến Môi Trường

```bash
cp .env.example .env
set -a && . ./.env && set +a
```

## Khởi Tạo Hạ Tầng Cloud Qua Terraform

```bash
cd cloud/terraform/ec2
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output public_ip
terraform output wireguard_endpoint
```

## Truy Cập Cloud Node

```bash
ssh -i <your-key.pem> ec2-user@<EC2_PUBLIC_IP>
```

## Kết Nối Edge WWAN

Cài đặt trực tiếp trên hệ điều hành (Native):

```bash
cd edge/5g-wwan
sudo -E bash install.sh
sudo systemctl status wwan.service
sudo systemctl status wwan-monitor.service
```

Chạy qua Docker container:

```bash
cd edge/5g-wwan/docker
sudo docker compose up -d
```

## Thiết Lập WireGuard Client Gia Nhập Mạng (Edge -> Cloud)

```bash
set -a && . ./.env && set +a
sudo -E bash edge/vpn/setup-wg-client.sh
```

Đăng ký peer thủ công trên máy chủ Cloud:

```bash
sudo wg set wg0 peer <client-public-key> allowed-ips 10.8.0.3/32
sudo wg-quick save wg0
sudo wg show
```

Gỡ bỏ cấu hình WireGuard client cục bộ trên Edge Node:

```bash
sudo -E bash edge/vpn/uninstall-wg-client.sh
```

Gỡ bỏ hoàn toàn cả cặp khóa mật mã local:

```bash
sudo -E REMOVE_WG_KEYS=true bash edge/vpn/uninstall-wg-client.sh
```

## Cụm Giám Sát (Monitoring Stack)

Khởi chạy cụm giám sát trên Cloud Node:

```bash
cd cloud/monitoring
sudo docker compose --env-file ../../.env up -d
sudo docker ps
curl http://127.0.0.1:9090/-/healthy
curl http://127.0.0.1:3100/ready
curl http://127.0.0.1:3000/api/health
```

Hoặc sử dụng script wrapper để tự động kiểm tra tham số `ALLOW_MONITORING_OVER_WIREGUARD` và xác thực mật khẩu `GRAFANA_ADMIN_PASSWORD`:

```bash
sudo -E bash cloud/monitoring/setup-monitoring.sh
```

Grafana tự động cấu hình nguồn dữ liệu Prometheus và Loki từ tệp `cloud/monitoring/grafana/provisioning/datasources/datasources.yml`.

Chỉ cho phép truy cập Grafana, Prometheus và Loki qua đường hầm bảo mật WireGuard:

```bash
# Trong file .env đặt: ALLOW_MONITORING_OVER_WIREGUARD=true
sudo -E bash shared/scripts/hardening.sh
cd cloud/monitoring
sudo docker compose --env-file ../../.env down
sudo docker compose --env-file ../../.env up -d
```

Hoặc dùng script wrapper (tự động cấu hình `MONITORING_BIND_ADDRESS=10.8.0.1` dựa trên giá trị của `ALLOW_MONITORING_OVER_WIREGUARD`):

```bash
sudo -E bash cloud/monitoring/setup-monitoring.sh down
sudo -E bash cloud/monitoring/setup-monitoring.sh
```

## Thiết Lập SSH Tunnel Để Truy Cập Web UI

Grafana, Prometheus, Loki và Node Exporter:

```bash
# Nếu cấu hình MONITORING_BIND_ADDRESS là 10.8.0.1, hãy đổi địa chỉ 127.0.0.1 ở dưới thành 10.8.0.1
ssh -i <your-key.pem> \
  -L 3000:127.0.0.1:3000 \
  -L 9090:127.0.0.1:9090 \
  -L 3100:127.0.0.1:3100 \
  -L 9100:127.0.0.1:9100 \
  ec2-user@<EC2_PUBLIC_IP>
```

Truy cập cục bộ trên trình duyệt máy tính của bạn:
- `http://127.0.0.1:3000`
- `http://127.0.0.1:9090`
- `http://127.0.0.1:3100/ready`
- `http://127.0.0.1:9100/metrics`

## Cài Đặt Grafana Alloy Trên Edge

Khởi chạy Alloy trên Edge Node sau khi kết nối VPN WireGuard đã thông suốt tới địa chỉ IP ảo Cloud Server. Cấu hình mặc định của `ALLOY_LOKI_URL` giả định Loki trên cloud đang lắng nghe tại địa chỉ `10.8.0.1:3100`.

```bash
set -a && . ./.env && set +a
sudo -E bash edge/observability/alloy/install-alloy.sh
sudo systemctl status alloy --no-pager
sudo journalctl -u alloy --no-pager
```

Script `install-alloy.sh` mặc định đặt tham số khởi chạy `CUSTOM_ARGS="--server.http.listen-addr=0.0.0.0:12345"` để giao diện UI có thể truy cập được qua VPN. Bạn có thể ghi đè địa chỉ IP lắng nghe nếu cần:

```bash
sudo -E ALLOY_HTTP_LISTEN_ADDR=0.0.0.0:12345 bash edge/observability/alloy/install-alloy.sh
```

Ghi đè địa chỉ đích Loki push log nếu IP overlay của cloud hoặc cổng Loki của bạn có sự thay đổi:

```bash
sudo -E ALLOY_LOKI_URL=http://10.8.0.1:3100/loki/api/v1/push bash edge/observability/alloy/install-alloy.sh
```

Truy cập giao diện quản trị Web Alloy UI từ laptop cá nhân qua SSH tunnel thông qua Cloud Gateway:

```bash
# Mở cổng trên tường lửa UFW tại Edge Node (chỉ cần làm một lần)
sudo ufw allow in on wg0 to any port 12345 proto tcp

# Trên máy tính cá nhân của bạn:
ssh -i <your-key.pem> -N -L 12345:10.8.0.2:12345 ec2-user@<EC2_PUBLIC_IP>
# Mở trình duyệt truy cập: http://127.0.0.1:12345
```

Gỡ bỏ hoàn toàn cấu hình và dịch vụ Alloy cục bộ trên Edge Node:

```bash
sudo -E bash edge/observability/alloy/uninstall-alloy.sh
```

## Cài Đặt Node Exporter

Cài đặt mặc định:

```bash
sudo -E bash shared/scripts/install-node-exporter.sh
```

Cài đặt chỉ định phiên bản cụ thể:

```bash
sudo -E NODE_EXPORTER_VERSION=1.11.1 bash shared/scripts/install-node-exporter.sh
```

Xác thực trạng thái hoạt động:

```bash
sudo systemctl status node_exporter --no-pager
ss -lntp | grep 9100
curl http://127.0.0.1:9100/metrics | head
```

Truy vấn metrics của Edge Node từ máy chủ Cloud:

```bash
curl http://10.8.0.3:9100/metrics | head
```

## Làm Cứng Hệ Thống (Hardening)

Cài đặt mặc định:

```bash
sudo -E bash shared/scripts/hardening.sh
```

Sử dụng cổng kết nối WireGuard tùy chỉnh:

```bash
sudo -E WIREGUARD_PORT=51821 bash shared/scripts/hardening.sh
```

Cho phép truy cập cụm giám sát thông qua đường hầm WireGuard:

```bash
sudo -E ALLOW_MONITORING_OVER_WIREGUARD=true WIREGUARD_NETWORK=10.8.0.0/24 bash shared/scripts/hardening.sh
```

Cấu hình thêm các cổng TCP bổ sung cần mở tại Edge Node:

```bash
sudo -E EDGE_EXTRA_TCP_PORTS='443 5201' bash shared/scripts/hardening.sh
```

## Thử Nghiệm Truyền Tải File

Tạo bộ dữ liệu mẫu (sample dataset):

```bash
mkdir -p ~/dataset/sample-set
fallocate -l 1G ~/dataset/sample-set/blob-1g.bin
for i in $(seq 1 100); do
  head -c 1048576 /dev/urandom > ~/dataset/sample-set/file-${i}.bin
done
du -sh ~/dataset/sample-set
```

Đồng bộ qua thư mục Rsync qua mạng ảo WireGuard:

```bash
rsync -avhP --partial --append-verify \
  ~/dataset/sample-set/ \
  ec2-user@10.8.0.1:/home/ec2-user/dataset/sample-set/
```

Kiểm tra nhanh bằng lệnh SCP:

```bash
echo "wireguard test $(date -Iseconds)" > /tmp/wg-test.txt
scp /tmp/wg-test.txt ec2-user@10.8.0.1:/tmp/
ssh ec2-user@10.8.0.1 'cat /tmp/wg-test.txt'
```

## Bộ Kịch Bản Đánh Giá Hiệu Năng (Benchmark Suite)

Khởi chạy toàn bộ các kịch bản đo đạc không phá hủy (non-destructive):

```bash
bash benchmark/run_all.sh
```

Khởi chạy các nhóm suite cụ thể:

```bash
bash benchmark/run_all.sh --suite 01,02      # Liên thông kết nối + Băng thông tcp
bash benchmark/run_all.sh --suite 03         # Trạng thái sức khỏe dịch vụ
bash benchmark/run_all.sh --suite 05         # Đo đạc E2E toàn bộ stack
```

Khởi chạy một file kịch bản đo đạc đơn lẻ:

```bash
bash benchmark/01-connectivity/test_ping_latency.sh
bash benchmark/02-bandwidth/test_iperf3_tcp.sh
bash benchmark/03-services/test_prometheus.sh
bash benchmark/05-e2e/test_full_stack.sh
```

Ghi đè cấu hình ngưỡng hoặc mục tiêu đo trực tiếp trên câu lệnh:

```bash
IPERF3_DURATION=30 WG_SERVER_IP=10.8.0.1 bash benchmark/run_all.sh 02
set -a && . .env && set +a && bash benchmark/run_all.sh 03
```

Kích hoạt cả các kịch bản đo đạc phá hủy (destructive - ví dụ: ngắt kết nối di động, failover):

```bash
sudo -E bash benchmark/run_all.sh --allow-destructive
```

Chạy iperf3 server ở chế độ daemon (khởi chạy trên Cloud Server trước khi chạy suite 02 hoặc 04):

```bash
iperf3 -s -D
```

## Xử Lý Sự Cố (Troubleshooting)

Tại máy chủ Cloud:

```bash
sudo journalctl -u wg-quick@wg0 -f
sudo wg show
sudo systemctl status docker --no-pager
sudo docker ps
sudo systemctl status node_exporter --no-pager
curl http://127.0.0.1:9100/metrics | head
curl http://127.0.0.1:3100/ready
```

Tại thiết bị biên Edge Node:

```bash
sudo journalctl -u wwan.service -u wwan-monitor.service -f
sudo journalctl -u alloy -f
sudo wg show
ip addr
```

## Kiểm Thử Bảo Mật VPN (VPN Security Verification)

Khởi chạy các kiểm thử tự động xác thực độ an toàn và bảo mật của VPN ngay trên Edge Node:

```bash
# Chạy toàn bộ các kịch bản kiểm thử bảo mật (Eavesdropping, MITM, Replay)
sudo -E bash shared/scripts/verify-vpn-security.sh

# Chỉ chạy kiểm thử phát hiện nghe lén / xác thực mã hóa gói tin
sudo -E bash shared/scripts/verify-vpn-security.sh --eavesdropping

# Chỉ chạy kiểm thử chống giả mạo gateway / tấn công giả mạo (MITM)
sudo -E bash shared/scripts/verify-vpn-security.sh --mitm

# Chỉ chạy kiểm thử cơ chế chặn tấn công phát lại (TAI64N anti-replay)
sudo -E bash shared/scripts/verify-vpn-security.sh --replay
```
