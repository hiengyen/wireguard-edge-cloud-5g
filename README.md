# WireGuard Edge–Cloud 5G Secure Overlay

🇬🇧 [English](#-english) | 🇻🇳 [Tiếng Việt](#-tiếng-việt)

---

## 🇬🇧 English

Secure Edge–Cloud connectivity using **WireGuard VPN over 5G** for distributed systems.

This project demonstrates a lightweight, secure, and scalable networking architecture connecting **Edge devices and Cloud infrastructure** through a **5G private overlay network**, utilizing manual peer registration, infrastructure monitoring, and system hardening.

---

## 🚀 Overview

Modern distributed systems increasingly rely on Edge computing and 5G connectivity.  
This project demonstrates how to deploy a **Zero-Trust secure tunnel** between Edge nodes and Cloud services using **WireGuard** on embedded ARM devices.

The platform integrates:

- Infrastructure observability (Prometheus + Loki + Grafana, with Edge Alloy log forwarding)
- System hardening and security best practices
- Secure manual VPN peer registration

Default overlay network values in this repository are standardized to `10.8.0.0/24`.
The multi-peer model used here assigns `/32` host routes to each edge peer while keeping the server interface on `10.8.0.1/24`.

---

## 🏗 Architecture

                ┌────────────────────────┐
                │     Cloud Gateway      │
                │ (Amazon Linux 2023 EC2)│
                │ - WireGuard Server     │
                │ - Prometheus/Loki      │
                │ - Grafana              │
                └──────────┬─────────────┘
                           │
             Encrypted Tunnel (WireGuard)
                  over Public 5G Network
                           │
                ┌──────────▼─────────────┐
                │       Edge Node        │
                │ - Orange Pi 5 Max      │
                │ - 5G WWAN Quectel      │
                │ - WireGuard Client     │
                │ - Node Exporter        │
                │ - Grafana Alloy        │
                └────────────────────────┘

---

## 📂 Repository Structure

```text
wireguard-edge-cloud-5g/
├── README.md                 # You are here!
├── docs/                     # Deployment and operations documentation
│   ├── DEPLOYMENT.md         # End-to-end rollout guide
│   ├── COMMANDS.md           # Common command reference
│   └── BENCHMARK.md          # Benchmark suite usage and interpretation guide
├── benchmark/                # Automated test and benchmark suite
│   ├── run_all.sh            # Master runner — executes all suites and prints a combined report
│   ├── config.sh             # Shared configuration, thresholds, and helper functions
│   ├── 01-connectivity/      # ICMP latency, WireGuard tunnel health, 5G signal quality
│   ├── 02-bandwidth/         # iperf3 TCP/UDP, rsync transfer, WireGuard encryption overhead
│   ├── 03-services/          # Prometheus, Loki, Grafana, Node Exporter health and API tests
│   ├── 04-load/              # Sustained bandwidth, concurrent monitoring load, WWAN reconnect
│   ├── 05-e2e/               # Full seven-phase stack validation and failover recovery
│   └── reports/              # Generated reports (git-ignored, kept for local analysis)
├── cloud/                    # Cloud Gateway components
│   ├── terraform/ec2/        # AWS IaC (AWS Provider v6, EC2, SG, Auto-install WG & API)
│   ├── monitoring/           # Prometheus, Loki, and Grafana docker infrastructure
│   └── vpn-reference/        # Reference configuration files
├── edge/                     # Edge Node components
│   ├── 5g-wwan/              # Cellular network physical layer scripts
│   │   ├── wwan-start.sh     # Dynamic device detection & QMI Raw-IP connect
│   │   ├── docker/           # Alternative: Containerized WWAN deployment
│   │   ├── install.sh        # Systemd installation script
│   │   └── uninstall.sh      # Cleanup automation
│   ├── observability/alloy/  # Edge Alloy journald-to-Loki pipeline
│   └── vpn/                  # VPN Overlay network layer
│       ├── setup-wg-client.sh    # Key generation & Zero-Touch cloud auto-registration
│       └── uninstall-wg-client.sh# Remove the local edge WireGuard client setup
└── shared/                   # Cross-platform utilities
    └── scripts/
        ├── hardening.sh      # Distro-aware SSH/Firewall/Fail2Ban hardening
        └── install-node-exporter.sh # Prometheus metrics agent installation
```

## 🔐 Key Features

- **5G QMI Network Automation:** Dynamically locates and connects Quectel RM502Q-GL via raw IP.
- **Secure Manual Registration:** Edge nodes are registered securely by explicitly adding their public keys to the cloud gateway.
- **Multi-Peer Addressing:** The server owns `10.8.0.1/24`, while each edge peer gets a unique `/32` address such as `10.8.0.2/32`.
- **Infrastructure as Code (IaC):** Cloud environments are 100% automated using Terraform.
- **Observability:** Prometheus pulls metrics, Alloy forwards edge journald logs to Loki, and Grafana provisions Prometheus/Loki data sources from YAML.
- **Hardening:** Best-practice security including OS-aware firewalling (`ufw` on Armbian/Debian, `firewalld` on Amazon Linux 2023), Fail2Ban, and key-only SSH.

## ⚙️ Environment File

The repository includes [`.env.example`](/home/hiengyen/CODE/wireguard-edge-cloud-5g/.env.example:1) to centralize deployment and runtime variables.
For the full production-oriented rollout sequence, see [DEPLOYMENT.md](/home/hiengyen/CODE/wireguard-edge-cloud-5g/docs/DEPLOYMENT.md:1).
For a compact command cheat sheet, see [COMMANDS.md](/home/hiengyen/CODE/wireguard-edge-cloud-5g/docs/COMMANDS.md:1).

Important groups:
- `TF_VAR_*`: Terraform inputs for cloud provisioning
- `GRAFANA_ADMIN_PASSWORD`: password used by `cloud/monitoring/docker-compose.yml`
- `MONITORING_BIND_ADDRESS`, `ALLOW_MONITORING_OVER_WIREGUARD`: monitoring access mode
- `PROMETHEUS_VERSION`, `GRAFANA_VERSION`, `LOKI_VERSION`, `LOKI_PORT`, `ALLOY_LOKI_URL`, `ALLOY_HTTP_LISTEN_ADDR`: observability runtime settings
- `WIREGUARD_*`: edge VPN client runtime defaults
- `WWAN_APN`, `SSH_ADMIN_PORT`, `EDGE_EXTRA_TCP_PORTS`: edge WWAN and hardening runtime settings

Set both `TF_VAR_wireguard_port` and `WIREGUARD_PORT` to the same value if you change the default WireGuard UDP port.

Recommended workflow:

```bash
cp .env.example .env
set -a && . ./.env && set +a
```

After that, Terraform, Docker Compose, and shell scripts can reuse the same exported values.

---

## 🚀 Quick Start

### 1. Cloud Provisioning

Deploy the Cloud Server using Terraform:

```bash
cp .env.example .env
set -a && . ./.env && set +a
cd cloud/terraform/ec2
terraform init
terraform plan -out=tfplan
terraform apply "tfplan"
```

The default example uses:
- Overlay network: `10.8.0.0/24`
- Sample edge client IP: `10.8.0.2/32`

### 2. Edge Physical Connection

Connect your Quectel 5G Module via USB/M.2 to the Edge SBC (e.g., Orange Pi). You have two deployment options:

**Option A: Systemd Service (Native)**
```bash
cd edge/5g-wwan
sudo -E ./install.sh
```

The edge installer also provisions the common operator toolset:
- `curl`, `rsync`, `iperf3`, `git`, `tmux`, `stow`, `vim`, `wget`, `docker`, and Docker Compose v2
- `ufw` on apt-based edge systems, and on dnf-based edge systems when the package exists in the enabled repositories

**Option B: Docker Containerized (Alternative)**
```bash
cd edge/5g-wwan/docker
sudo -E docker compose up -d
```

### 3. Edge VPN Manual Registration

Once connected to the internet, join the VPN overlay by running the client setup script:

```bash
sudo -E ./edge/vpn/setup-wg-client.sh
```

Follow the prompts to generate a client public key. Then, SSH into your cloud gateway and add the peer manually using `sudo wg set wg0 peer <client-public-key> allowed-ips 10.8.0.x/32` and `sudo wg-quick save wg0`.

The client should keep:
- `Address = 10.8.0.x/32`
- `AllowedIPs = 10.8.0.0/24` for overlay-only routing

If you need to remove the local WireGuard client setup from the edge node later:

```bash
sudo -E ./edge/vpn/uninstall-wg-client.sh
```

To remove the local key pair too:

```bash
sudo -E REMOVE_WG_KEYS=true ./edge/vpn/uninstall-wg-client.sh
```

This only removes the local edge client. If you also need to remove the peer from the cloud server, delete that peer separately on the server with `wg set ... peer ... remove` and `wg-quick save`.

The cloud bootstrap also installs the common operator toolset on Amazon Linux 2023:
- `curl`, `rsync`, `iperf3`, `git`, `tmux`, `stow`, `vim`, `wget`, `docker`, and Docker Compose v2

### 4. Shared Operations (Hardening & Monitoring)

On both environments, run:

```bash
sudo -E ./shared/scripts/hardening.sh
sudo -E ./shared/scripts/install-node-exporter.sh
```

`hardening.sh` auto-detects the target OS:
- Edge Node on Armbian/Debian: configures `ufw`
- Cloud Gateway on Amazon Linux 2023: configures `firewalld`

If you use a non-default WireGuard port, run `hardening.sh` with `WIREGUARD_PORT=<port>`.
On the edge node, the default extra inbound TCP rules are `443` and `5201` through `EDGE_EXTRA_TCP_PORTS`. This repository does not add `8006` or `64203`.

For Grafana, set a non-default password first, then start the monitoring stack. This starts Prometheus, Loki, and Grafana; Grafana provisions the Prometheus and Loki data sources from YAML.

Before starting Grafana, you can generate the **Unified Edge & Cloud Dashboard** which provides a single-pane-of-glass overview of all nodes:

```bash
cd cloud/monitoring
python3 generate_unified_dashboard.py
```

Then start the stack:

```bash
cd cloud/monitoring
# Use -E to preserve environment variables loaded from .env
sudo -E docker compose --env-file ../../.env up -d --force-recreate
```

Or use the wrapper script which validates `GRAFANA_ADMIN_PASSWORD` and applies `ALLOW_MONITORING_OVER_WIREGUARD` automatically:

```bash
sudo ./cloud/monitoring/setup-monitoring.sh
```

If you want to reach Grafana, Prometheus, and Loki through the WireGuard overlay instead of SSH tunneling, set `ALLOW_MONITORING_OVER_WIREGUARD=true` in `.env`, then re-run:

```bash
sudo -E ./shared/scripts/hardening.sh
sudo ./cloud/monitoring/setup-monitoring.sh
```

You do not need extra AWS Security Group ingress for `3000/tcp`, `9090/tcp`, `3100/tcp`, or `9100/tcp` in that model. Only the WireGuard UDP port is exposed publicly; Grafana, Prometheus, Loki, and Node Exporter are reached after traffic is decrypted on the EC2 instance.

To access the monitoring web UIs through SSH tunneling from your local machine:

```bash
# -N keeps the tunnel open without opening a shell
# Cloud services (10.8.0.1) + Alloy UI on edge (10.8.0.2:12345)
ssh -i <your-key.pem> -N \
  -L 3000:10.8.0.1:3000 \
  -L 9090:10.8.0.1:9090 \
  -L 3100:10.8.0.1:3100 \
  -L 9100:10.8.0.1:9100 \
  -L 12345:10.8.0.2:12345 \
  ec2-user@<EC2_PUBLIC_IP>
```

Then open:
- Grafana: `http://127.0.0.1:3000`
- Prometheus: `http://127.0.0.1:9090`
- Loki readiness: `http://127.0.0.1:3100/ready`
- Node Exporter (cloud): `http://127.0.0.1:9100/metrics`
- Alloy UI (edge): `http://127.0.0.1:12345`

For the Alloy UI line to work, open port 12345 on the edge UFW once:
`sudo ufw allow in on wg0 to any port 12345 proto tcp`

To forward edge logs to Loki with Alloy after WireGuard is up:

```bash
set -a && . ./.env && set +a
sudo -E ./edge/observability/alloy/install-alloy.sh
```

The default Alloy endpoint expects cloud Loki at `10.8.0.1:3100`, so bind the monitoring stack to the WireGuard address before using it.

To verify Node Exporter after installation:

```bash
sudo systemctl status node_exporter --no-pager
ss -lntp | grep 9100
curl http://127.0.0.1:9100/metrics | head
```

The repository currently installs Node Exporter `1.11.1` by default. Override it with:

```bash
sudo -E NODE_EXPORTER_VERSION=<version> ./shared/scripts/install-node-exporter.sh
```


---

## 🧪 Benchmarking

Run the automated benchmark suite to validate the full stack after deployment:

```bash
# Start iperf3 server on the cloud gateway first
iperf3 -s -D

# On the edge node — run all non-destructive suites
./benchmark/run_all.sh

# Connectivity + bandwidth only
./benchmark/run_all.sh --suite 01,02

# Services health only (after monitoring stack is up)
set -a && . .env && set +a
./benchmark/run_all.sh --suite 03

# Full stack smoke test
bash benchmark/05-e2e/test_full_stack.sh

# Include reconnect and failover tests (requires root)
sudo ./benchmark/run_all.sh --allow-destructive
```

Reports are written to `benchmark/reports/` as `.txt`, `.csv`, and `.json` files.  
For the full parameter reference and suite descriptions, see [BENCHMARK.md](docs/BENCHMARK.md).

---

## 🇻🇳 Tiếng Việt

Kết nối bảo mật an toàn giữa Edge và Cloud thông qua **WireGuard VPN trên sóng mạng 5G** dành cho các hệ thống phân tán.

Dự án này là minh chứng về việc xây dựng kiến trúc mạng nhẹ, bảo mật và dễ mở rộng kết nối giữa các **Thiết bị biên (Edge)** và **Máy chủ đám mây (Cloud)** thông qua **mạng ảo nội bộ trên nền tảng 5G**, tích hợp quản lý peer thủ công an toàn, giám sát cơ sở hạ tầng và làm cứng (hardening) hệ thống.

---

## 🚀 Tổng quan

Các hệ thống phân tán hiện đại ngày càng phụ thuộc vào điện toán biên (Edge Computing) và kết nối không dây 5G.
Dự án này cho thấy cách triển khai một **đường hầm bảo mật Zero-Trust** giữa các Edge node và dịch vụ Cloud bằng việc sử dụng **WireGuard** trên thiết bị ARM nhúng.

Nền tảng này tích hợp sẵn:

- Phân hệ quan sát hạ tầng và log (Prometheus + Loki + Grafana, Edge dùng Alloy đẩy log).
- Áp dụng các tiêu chuẩn Làm cứng hệ thống/Bảo mật lõi (System Hardening).
- Đăng ký VPN thủ công đảm bảo mô hình Zero-Trust.

Các giá trị overlay mặc định trong repo này đã được chuẩn hoá về `10.8.0.0/24`.
Mô hình multi-peer trong repo dùng `10.8.0.1/24` cho server và cấp IP `/32` riêng cho từng edge peer.

---

## 🏗 Kiến trúc Hệ thống

                ┌────────────────────────┐
                │     Cloud Gateway      │
                │ (Amazon Linux 2023 EC2)│
                │ - Dịch vụ WireGuard    │
                │ - Prometheus/Loki      │
                │ - Grafana              │
                └──────────┬─────────────┘
                           │
             Đường hầm mã hóa (WireGuard)
                  qua Internet sóng 5G
                           │
                ┌──────────▼─────────────┐
                │       Edge Node        │
                │ - Orange Pi 5 Max      │
                │ - 5G WWAN Quectel      │
                │ - Client WireGuard     │
                │ - Node Exporter        │
                │ - Grafana Alloy        │
                └────────────────────────┘

---

## 📂 Tổ chức Thư mục

```text
wireguard-edge-cloud-5g/
├── README.md                 # Chính là tài liệu này (Song ngữ)
├── docs/                     # Tài liệu triển khai và vận hành
│   ├── DEPLOYMENT.md         # Hướng dẫn triển khai đầy đủ
│   ├── COMMANDS.md           # Tổng hợp lệnh hay dùng
│   └── BENCHMARK.md          # Hướng dẫn sử dụng và đọc kết quả benchmark
├── benchmark/                # Bộ kiểm thử và đo hiệu năng tự động
│   ├── run_all.sh            # Runner tổng — chạy toàn bộ suite và in báo cáo tổng hợp
│   ├── config.sh             # Cấu hình chung, ngưỡng chấp nhận và hàm tiện ích
│   ├── 01-connectivity/      # Độ trễ ICMP, sức khoẻ đường hầm WireGuard, chất lượng 5G
│   ├── 02-bandwidth/         # iperf3 TCP/UDP, rsync truyền file, chi phí mã hoá WireGuard
│   ├── 03-services/          # Kiểm tra sức khoẻ Prometheus, Loki, Grafana, Node Exporter
│   ├── 04-load/              # Băng thông liên tục, tải đồng thời monitoring, phục hồi WWAN
│   ├── 05-e2e/               # Kiểm thử 7 pha toàn bộ stack và kịch bản failover
│   └── reports/              # Báo cáo được sinh ra (git-ignored, dùng để phân tích cục bộ)
├── cloud/                    # Phân hệ Máy chủ Cổng kết nối
│   ├── terraform/ec2/        # Triển khai tự động AWS (Provider v6, EC2, tự động tải WG & API)
│   ├── monitoring/           # Cụm Docker cho Prometheus, Loki và Grafana
│   └── vpn-reference/        # Nơi lưu cấu hình tham chiếu của Server
├── edge/                     # Phân hệ Thiết bị Đầu cuối
│   ├── 5g-wwan/              # Kịch bản giao tiếp phần cứng mạng di động
│   │   ├── wwan-start.sh     # Phát hiện thiết bị tĩnh/động & kết nối QMI Raw-IP
│   │   ├── docker/           # Triển khai giải pháp thay thế qua Docker Container
│   │   ├── install.sh        # Tiện ích tự động cài đặt Systemd Service
│   │   └── uninstall.sh      # Tiện ích dọn dẹp hệ thống
│   ├── observability/alloy/  # Pipeline Alloy đọc journald và đẩy về Loki
│   └── vpn/                  # Tầng mạng ảo (Overlay network)
│       ├── setup-wg-client.sh    # Sinh khóa mã hóa & Gia nhập mạng tự động không chạm
│       └── uninstall-wg-client.sh# Gỡ cấu hình WireGuard client cục bộ trên edge
└── shared/                   # Các thư viện dùng chung cho cả Cloud và Edge
    └── scripts/
        ├── hardening.sh      # Hardening SSH/Firewall/Fail2Ban theo từng distro
        └── install-node-exporter.sh # Cài Agent theo dõi sức khoẻ phần cứng
```

## 🔐 Tính Năng Chính

- **Tự động Giao tiếp 5G QMI:** Định danh và kết nối tự động tới modem Quectel RM502Q-GL qua chế độ raw IP, hạn chế lỗi gán cứng `/dev/cdc-wdm0`.
- **Đăng Ký VPN Thủ Công:** Việc thêm các Edge node phải được thực hiện thông qua khai báo Public Key trên Cloud Gateway, đảm bảo tính bảo mật tối đa.
- **Mô Hình Multi-Peer:** Server dùng `10.8.0.1/24`, còn mỗi edge peer nhận một IP `/32` riêng như `10.8.0.2/32`.
- **Hạ tầng dưới dạng Mã (IaC):** Server rỗng được khởi tạo và cài cắm 100% tự động qua môi trường Terraform.
- **Khả năng Quan sát (Observability):** Prometheus thu metrics, Alloy đẩy journald log từ edge về Loki, và Grafana tự provision datasource Prometheus/Loki bằng YAML.
- **Bảo Mật (Hardening):** Áp dụng hardening theo môi trường đích: `ufw` cho Armbian/Debian ở Edge, `firewalld` cho Amazon Linux 2023 ở Cloud, kết hợp Fail2Ban và chỉ cho phép SSH bằng khoá.

## ⚙️ File Môi Trường

Repo có sẵn file [`.env.example`](/home/hiengyen/CODE/wireguard-edge-cloud-5g/.env.example:1) để gom các biến triển khai và runtime.
Danh sách lệnh dùng thường xuyên được gom trong [COMMANDS.md](/home/hiengyen/CODE/wireguard-edge-cloud-5g/docs/COMMANDS.md:1).

Các nhóm biến chính:
- `TF_VAR_*`: đầu vào Terraform cho phần cloud
- `GRAFANA_ADMIN_PASSWORD`: mật khẩu dùng cho `cloud/monitoring/docker-compose.yml`
- `MONITORING_BIND_ADDRESS`, `ALLOW_MONITORING_OVER_WIREGUARD`: chế độ truy cập monitoring
- `PROMETHEUS_VERSION`, `GRAFANA_VERSION`, `LOKI_VERSION`, `LOKI_PORT`, `ALLOY_LOKI_URL`, `ALLOY_HTTP_LISTEN_ADDR`: tham số runtime cho observability
- `WIREGUARD_*`: mặc định runtime cho edge VPN client
- `WWAN_APN`, `SSH_ADMIN_PORT`, `EDGE_EXTRA_TCP_PORTS`: tham số runtime cho WWAN và hardening

Quy trình khuyên dùng:

```bash
cp .env.example .env
set -a && . ./.env && set +a
```

Sau đó Terraform, Docker Compose và các shell script sẽ dùng chung được các biến này.

---

## 🚀 Hướng Dẫn Nhanh

### 1. Triển khai Cloud

Xây dựng Server Cloud qua Terraform:

```bash
cp .env.example .env
set -a && . ./.env && set +a
cd cloud/terraform/ec2
terraform init
terraform plan -out=tfplan
terraform apply "tfplan"
```

Ví dụ mặc định hiện tại dùng:
- Overlay network: `10.8.0.0/24`
- Sample edge client IP: `10.8.0.2/32`

### 2. Kết nối Mạng phần cứng

Cắm anten, gắn 5G Module qua ngõ USB/PCIe M.2 vào thiết bị SBC (Ví dụ: Orange Pi). 

Bạn có thể chọn 1 trong 2 cách triển khai:

**Cách 1: Chạy trực tiếp qua Systemd (Khuyên dùng)**
```bash
cd edge/5g-wwan
sudo -E ./install.sh
```

Trình cài đặt edge cũng cài sẵn bộ công cụ vận hành:
- `curl`, `rsync`, `iperf3`, `git`, `tmux`, `stow`, `vim`, `wget`, `docker`, và Docker Compose v2
- `ufw` trên edge dùng `apt`, và trên edge dùng `dnf` nếu package tồn tại trong repo đã bật

**Cách 2: Đóng gói siêu sạch qua Docker (Alternative)**
```bash
cd edge/5g-wwan/docker
sudo -E docker compose up -d
```

### 3. Đăng ký Cấu Hình VPN Thủ Công

Sau khi có kết nối Internet do SIM cấp, tạo cấu hình và tham gia vào mạng:

```bash
sudo -E ./edge/vpn/setup-wg-client.sh
```

Thực hiện theo các bước trên màn hình để tạo Client Public Key. Sau đó, SSH lên Cloud Gateway và thêm Peer thủ công bằng lệnh `sudo wg set wg0 peer <client-public-key> allowed-ips 10.8.0.x/32` và lưu lại bằng `sudo wg-quick save wg0`.

Client nên giữ:
- `Address = 10.8.0.x/32`
- `AllowedIPs = 10.8.0.0/24` nếu chỉ route trong overlay

Nếu cần gỡ cấu hình WireGuard client cục bộ trên edge sau này:

```bash
sudo -E ./edge/vpn/uninstall-wg-client.sh
```

Nếu muốn xóa cả key local:

```bash
sudo -E REMOVE_WG_KEYS=true ./edge/vpn/uninstall-wg-client.sh
```

Script này chỉ gỡ phía edge local. Nếu cần xóa peer trên cloud server thì phải thực hiện riêng bằng `wg set ... peer ... remove` và `wg-quick save`.

Bootstrap cloud cũng cài sẵn bộ công cụ vận hành trên Amazon Linux 2023:
- `curl`, `rsync`, `iperf3`, `git`, `tmux`, `stow`, `vim`, `wget`, `docker`, và Docker Compose v2

### 4. Phụ bản Quản trị (Bảo mật & Giám sát)

Hoạt động dùng chung ở cả 2 bề mặt của hệ thống:

```bash
sudo -E ./shared/scripts/hardening.sh
sudo -E ./shared/scripts/install-node-exporter.sh
```

`hardening.sh` sẽ tự nhận diện hệ điều hành:
- Edge Node chạy Armbian/Debian: cấu hình `ufw`
- Cloud Gateway chạy Amazon Linux 2023: cấu hình `firewalld`

Nếu bạn dùng cổng WireGuard khác `51820`, hãy chạy với biến `WIREGUARD_PORT=<port>`.
Trên edge node, rule TCP vào mặc định bổ sung là `443` và `5201` qua biến `EDGE_EXTRA_TCP_PORTS`. Repo này không tự thêm `8006` hoặc `64203`.

Đặt mật khẩu Grafana không mặc định rồi mới khởi chạy giám sát trên Cloud. Stack này chạy Prometheus, Loki và Grafana; Grafana tự provision datasource Prometheus/Loki bằng YAML.

Trước khi chạy, bạn có thể sinh ra **Dashboard Tổng Hợp (Unified Edge & Cloud)** để có cái nhìn bao quát toàn bộ hệ thống trên cùng một màn hình:

```bash
cd cloud/monitoring
python3 generate_unified_dashboard.py
```

Sau đó khởi động stack:

```bash
cd cloud/monitoring
# Sử dụng flag -E để giữ các biến môi trường được tải từ file .env
sudo -E docker compose --env-file ../../.env up -d --force-recreate
```

Hoặc dùng wrapper script để tự validate `GRAFANA_ADMIN_PASSWORD` và tự áp dụng `ALLOW_MONITORING_OVER_WIREGUARD`:

```bash
sudo ./cloud/monitoring/setup-monitoring.sh
```

Nếu muốn truy cập Grafana, Prometheus và Loki qua đường hầm WireGuard thay vì SSH tunnel, đặt `ALLOW_MONITORING_OVER_WIREGUARD=true` trong `.env` rồi chạy lại:

```bash
sudo -E ./shared/scripts/hardening.sh
sudo ./cloud/monitoring/setup-monitoring.sh
```

Mô hình này không cần mở thêm AWS Security Group cho `3000/tcp`, `9090/tcp`, `3100/tcp`, hoặc `9100/tcp`. Bên ngoài chỉ mở cổng UDP của WireGuard; Grafana, Prometheus, Loki và Node Exporter chỉ được truy cập sau khi gói tin được giải mã trên chính EC2.

Nếu muốn truy cập Web UI của monitoring qua SSH tunnel từ máy local:

```bash
# -N giữ tunnel mở mà không mở shell
# Cloud services (10.8.0.1) + Alloy UI trên edge (10.8.0.2:12345)
ssh -i <your-key.pem> -N \
  -L 3000:10.8.0.1:3000 \
  -L 9090:10.8.0.1:9090 \
  -L 3100:10.8.0.1:3100 \
  -L 9100:10.8.0.1:9100 \
  -L 12345:10.8.0.2:12345 \
  ec2-user@<EC2_PUBLIC_IP>
```

Sau đó mở:
- Grafana: `http://127.0.0.1:3000`
- Prometheus: `http://127.0.0.1:9090`
- Loki readiness: `http://127.0.0.1:3100/ready`
- Node Exporter (cloud): `http://127.0.0.1:9100/metrics`
- Alloy UI (edge): `http://127.0.0.1:12345`

Để dùng được dòng Alloy UI, mở port 12345 trên UFW của edge một lần:
`sudo ufw allow in on wg0 to any port 12345 proto tcp`

Đẩy log edge về Loki bằng Alloy sau khi WireGuard đã chạy:

```bash
set -a && . ./.env && set +a
sudo -E ./edge/observability/alloy/install-alloy.sh
```

Endpoint Alloy mặc định cần Loki ở `10.8.0.1:3100`, nên hãy bind monitoring stack vào địa chỉ WireGuard trước khi dùng.

Kiểm tra Node Exporter sau khi cài:

```bash
sudo systemctl status node_exporter --no-pager
ss -lntp | grep 9100
curl http://127.0.0.1:9100/metrics | head
```

Repo hiện cài Node Exporter mặc định ở phiên bản `1.11.1`. Có thể đổi bằng:

```bash
sudo -E NODE_EXPORTER_VERSION=<version> ./shared/scripts/install-node-exporter.sh
```


---

---

## 🧪 Kiểm Thử & Đo Hiệu Năng (Benchmark)

Chạy bộ benchmark tự động để xác nhận toàn bộ stack sau khi triển khai:

```bash
# Khởi động iperf3 server trên Cloud Gateway trước
iperf3 -s -D

# Trên edge node — chạy toàn bộ suite không phá hoại
./benchmark/run_all.sh

# Chỉ kết nối + băng thông
./benchmark/run_all.sh --suite 01,02

# Chỉ kiểm tra sức khoẻ dịch vụ (sau khi monitoring stack đã lên)
set -a && . .env && set +a
./benchmark/run_all.sh --suite 03

# Smoke test toàn stack
bash benchmark/05-e2e/test_full_stack.sh

# Cho phép test phá hoại (WWAN reconnect, failover) — cần sudo
sudo ./benchmark/run_all.sh --allow-destructive
```

Báo cáo được ghi vào `benchmark/reports/` dưới dạng `.txt`, `.csv` và `.json`.  
Tham khảo đầy đủ thông số và mô tả từng suite tại [BENCHMARK.md](docs/BENCHMARK.md).

---

## 🔧 Troubleshooting / Gỡ Lỗi

For the full troubleshooting guide see [DEPLOYMENT.md — Section 13](docs/DEPLOYMENT.md).

**Loki not reachable on `10.8.0.1:3100` after changing `ALLOW_MONITORING_OVER_WIREGUARD`**

The containers must be restarted for the new bind address to take effect:

```bash
cd cloud/monitoring
sudo docker compose --env-file ../../.env down
sudo docker compose --env-file ../../.env up -d
curl http://10.8.0.1:3100/ready
```

**Alloy crash loop — `invalid yaml positions file: yaml: control characters are not allowed`**

The journal read-position tracking file is corrupted. Delete it and restart:

```bash
sudo rm /var/lib/alloy/data/loki.source.journal.system/positions.yml
sudo systemctl reset-failed alloy
sudo systemctl start alloy
```

**How to trigger simulated Dashboard Alarms & Intrusion Attacks for testing / Cách giả lập Cảnh Báo Lỗi & Tấn Công Bảo Mật để kiểm thử**

To verify that the *SYSTEM ALERTS*, *KERNEL PANICS*, and *SYSTEM SECURITY* panels work correctly (which naturally show "No data" on healthy and CGNAT-shielded nodes), run the following CLI commands:

- **English:**
  * Simulate System Crash/Alert:
    ```bash
    logger "TEST ALERT: segfault crash in system service, critical exception triggered"
    ```
  * Simulate SSH Login Failure:
    ```bash
    logger "sshd[9999]: Failed password for invalid user hacker from 192.168.1.100 port 54321 ssh2"
    ```
  * Simulate Fail2Ban IP block:
    ```bash
    logger "fail2ban.actions[1234]: WARNING [sshd] Ban 192.168.1.100"
    ```
- **Tiếng Việt:**
  * Giả lập Sập tiến trình / Lỗi hệ thống:
    ```bash
    logger "TEST ALERT: segfault crash in system service, critical exception triggered"
    ```
  * Giả lập Dò mật khẩu SSH thất bại:
    ```bash
    logger "sshd[9999]: Failed password for invalid user hacker from 192.168.1.100 port 54321 ssh2"
    ```
  * Giả lập Fail2Ban cấm IP xấu:
    ```bash
    logger "fail2ban.actions[1234]: WARNING [sshd] Ban 192.168.1.100"
    ```
  *(Các dòng log giả lập này sẽ hiển thị lên màn hình Grafana chỉ sau 5-10 giây để kiểm thử xem các bộ lọc có hoạt động chuẩn xác).*

**Edge Node Clock Out-of-Sync (No logs appearing on Grafana) / Lệch giờ hệ thống ở Edge (Không thấy log xuất hiện)**

Because embedded ARM SBCs (like Orange Pi) do not have an RTC battery backup, their system clock can drift or reset to a past date after a power loss. Loki will discard logs that are too far behind, and Grafana won't display them inside current time-range queries.

- **English Fix:**
  Verify the current clock on the Edge using `date`. Fix it instantly without rebooting:
  ```bash
  # Enable automatic NTP synchronization over internet:
  sudo timedatectl set-ntp true
  sudo systemctl restart systemd-timesyncd
  # Or set the time manually (e.g. May 18, 2026):
  sudo date -s "2026-05-18 00:20:00"
  # Always restart Alloy after updating the clock:
  sudo systemctl restart alloy
  ```
- **Tiếng Việt khắc phục:**
  Kiểm tra giờ trên Edge bằng lệnh `date`. Sửa lỗi lệch giờ ngay lập tức mà không cần khởi động lại máy:
  ```bash
  # Bật đồng bộ giờ NTP tự động qua internet:
  sudo timedatectl set-ntp true
  sudo systemctl restart systemd-timesyncd
  # Hoặc chỉnh giờ thủ công bằng tay (ví dụ: ngày 18 tháng 5 năm 2026):
  sudo date -s "2026-05-18 00:20:00"
  # Luôn nhớ khởi động lại Alloy để xả log với mốc giờ mới:
  sudo systemctl restart alloy
  ```

**5G CGNAT Stealth Topology Note / Lưu ý về cơ chế ẩn mình sau 5G CGNAT**

- **English:** The Edge node sits behind Carrier-Grade NAT (CGNAT) on the 5G WWAN interface. It has no inbound public IPv4 address, meaning public bots cannot scan or brute-force SSH on the Orange Pi. The *SYSTEM SECURITY* panel for the Edge node will naturally display `"No data"`. This is highly secure by design!
- **Tiếng Việt:** Thiết bị Edge nằm sau lớp CGNAT của nhà mạng 5G nên không có IP Public đầu vào, giúp ngăn chặn tuyệt đối các cuộc quét cổng hay brute-force SSH từ bên ngoài Internet. Vì vậy, việc phần bảo mật của Orange Pi hiển thị `"No data"` là hoàn toàn bình thường và cực kỳ an toàn!

**Clearing "Ghost" Jobs in Grafana & Prometheus / Xóa dữ liệu rác (Job cũ) hiển thị sai trong Grafana**

If you rename a job in `prometheus.yml` (e.g. from `cloud-gateway` to `cloud-node`), the old name will linger in Grafana dropdowns for 15 days due to Prometheus TSDB retention. To clear it immediately, wipe the Prometheus volume:
Nếu bạn đổi tên cấu hình job (VD từ `cloud-gateway` thành `cloud-node`), tên cũ vẫn sẽ kẹt lại trong menu thả xuống của Grafana 15 ngày. Để dọn dẹp ngay, hãy xóa volume của Prometheus và khởi động lại:
```bash
cd cloud/monitoring
set -a && source ../../.env && set +a
docker compose stop prometheus
docker compose rm -f prometheus
docker volume rm monitoring_prometheus_data
docker compose up -d
```

**Testing SWAP and CPU Load / Kiểm thử ép tải CPU và SWAP trên Edge Node**

To verify that the monitoring stack correctly reports CPU and memory pressure, use `stress-ng`.
Để xác nhận hệ thống báo cáo chính xác % CPU và SWAP đang sử dụng, hãy SSH vào Edge Node và dùng công cụ `stress-ng`.
```bash
sudo apt update && sudo apt install stress-ng -y
# Max out 4 CPU cores for 60 seconds / Vắt kiệt 4 nhân CPU trong 60 giây
stress-ng --cpu 4 --timeout 60s

# Force Heavy SWAP Usage (Consume 120% RAM) / Ép hệ thống dùng SWAP bằng cách ăn 120% RAM vật lý
stress-ng --vm 4 --vm-bytes 120% --vm-keep --oomable --timeout 300s
```

---

---

## 👤 Author / Tác Giả

**Nguyen Trung Hieu**  
Cloud / System Engineer Enthusiast
