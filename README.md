# WireGuard Edge–Cloud 5G Secure Overlay

🇬🇧 [English](#-english) | 🇻🇳 [Tiếng Việt](#-tiếng-việt)

---

## 🇬🇧 English

Secure Edge–Cloud connectivity using **WireGuard VPN over 5G** for distributed systems.

This project demonstrates a lightweight, secure, and scalable networking architecture connecting **Edge devices and Cloud infrastructure** through a **5G private overlay network**, utilizing Zero-touch auto-registration, infrastructure monitoring, and system hardening.

---

## 🚀 Overview

Modern distributed systems increasingly rely on Edge computing and 5G connectivity.  
This project demonstrates how to deploy a **Zero-Trust secure tunnel** between Edge nodes and Cloud services using **WireGuard** on embedded ARM devices.

The platform integrates:

- Infrastructure observability (Prometheus + Loki + Grafana, with Edge Alloy log forwarding)
- System hardening and security best practices
- Auto-Registration API for seamless Zero-touch VPN enrollment

Default overlay network values in this repository are standardized to `10.8.0.0/24`.
The multi-peer model used here assigns `/32` host routes to each edge peer while keeping the server interface on `10.8.0.1/24`.

---

## 🏗 Architecture

                ┌────────────────────────┐
                │     Cloud Gateway      │
                │ (Amazon Linux 2023 EC2)│
                │ - WireGuard Server     │
                │ - Registration API     │
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
│   └── COMMANDS.md           # Common command reference
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
- **Zero-Touch VPN Registration:** Edge nodes can register through a token-secured API, but API ingress is disabled by default and should be exposed only behind trusted CIDRs or TLS.
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
- `PROMETHEUS_VERSION`, `GRAFANA_VERSION`, `LOKI_VERSION`, `LOKI_PORT`, `ALLOY_LOKI_URL`: observability runtime settings
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

_Prepare a strong `TF_VAR_wg_api_token` before `terraform apply`. Terraform will output the server endpoint, but not the token._

The default example uses:
- Overlay network: `10.8.0.0/24`
- Sample edge client IP: `10.8.0.2/32`
- Registration API: disabled by default
- Public registration API TLS endpoint: automatically uses the EC2 Elastic IP when `registration_api_domain` is empty

You can set `registration_api_domain` to either:
- a public hostname such as `vpn-api.example.com`
- or the EC2 Elastic IP directly

If you leave `registration_api_domain` empty, Terraform will automatically use the EC2 Elastic IP.

### 2. Edge Physical Connection

Connect your Quectel 5G Module via USB/M.2 to the Edge SBC (e.g., Orange Pi). You have two deployment options:

**Option A: Systemd Service (Native)**
```bash
cd edge/5g-wwan
sudo ./install.sh
```

The edge installer also provisions the common operator toolset:
- `curl`, `rsync`, `iperf3`, `git`, `tmux`, `stow`, `vim`, `wget`, `docker`, and Docker Compose v2
- `ufw` on apt-based edge systems, and on dnf-based edge systems when the package exists in the enabled repositories

**Option B: Docker Containerized (Alternative)**
```bash
cd edge/5g-wwan/docker
sudo docker compose up -d
```

### 3. Edge VPN Auto-Registration

Once connected to the internet, join the VPN overlay:

```bash
sudo ./edge/vpn/setup-wg-client.sh
```

_When prompted, use auto-registration only if you intentionally enabled API ingress and restricted it to trusted CIDRs or placed it behind TLS._

The cloud bootstrap currently provisions a self-signed certificate for the reverse proxy so the API is encrypted immediately. Replace it with a trusted certificate before production rollout.

The client should keep:
- `Address = 10.8.0.x/32`
- `AllowedIPs = 10.8.0.0/24` for overlay-only routing

If you need to remove the local WireGuard client setup from the edge node later:

```bash
sudo ./edge/vpn/uninstall-wg-client.sh
```

To remove the local key pair too:

```bash
sudo REMOVE_WG_KEYS=true ./edge/vpn/uninstall-wg-client.sh
```

This only removes the local edge client. If you also need to remove the peer from the cloud server, delete that peer separately on the server with `wg set ... peer ... remove` and `wg-quick save`.

The cloud bootstrap also installs the common operator toolset on Amazon Linux 2023:
- `curl`, `rsync`, `iperf3`, `git`, `tmux`, `stow`, `vim`, `wget`, `docker`, and Docker Compose v2

### 4. Shared Operations (Hardening & Monitoring)

On both environments, run:

```bash
sudo ./shared/scripts/hardening.sh
sudo ./shared/scripts/install-node-exporter.sh
```

`hardening.sh` auto-detects the target OS:
- Edge Node on Armbian/Debian: configures `ufw`
- Cloud Gateway on Amazon Linux 2023: configures `firewalld`

If you use a non-default WireGuard port, run `hardening.sh` with `WIREGUARD_PORT=<port>`.
On the edge node, the default extra inbound TCP rules are `443` and `5201` through `EDGE_EXTRA_TCP_PORTS`. This repository does not add `8006` or `64203`.

For Grafana, set a non-default password first, then start the monitoring stack. This starts Prometheus, Loki, and Grafana; Grafana provisions the Prometheus and Loki data sources from YAML.

```bash
set -a && . ./.env && set +a
cd cloud/monitoring
sudo docker compose up -d
```

If you want to reach Grafana, Prometheus, and Loki through the WireGuard overlay instead of SSH tunneling, set:

```bash
MONITORING_BIND_ADDRESS=10.8.0.1
ALLOW_MONITORING_OVER_WIREGUARD=true
```

Then re-run:

```bash
sudo ./shared/scripts/hardening.sh
cd cloud/monitoring
sudo docker compose up -d
```

You do not need extra AWS Security Group ingress for `3000/tcp`, `9090/tcp`, `3100/tcp`, or `9100/tcp` in that model. Only the WireGuard UDP port is exposed publicly; Grafana, Prometheus, Loki, and Node Exporter are reached after traffic is decrypted on the EC2 instance.

To access the monitoring web UIs through SSH tunneling from your local machine:

```bash
ssh -i <your-key.pem> \
  -L 3000:127.0.0.1:3000 \
  -L 9090:127.0.0.1:9090 \
  -L 3100:127.0.0.1:3100 \
  -L 9100:127.0.0.1:9100 \
  ec2-user@<EC2_PUBLIC_IP>
```

Then open:
- Grafana: `http://127.0.0.1:3000`
- Prometheus: `http://127.0.0.1:9090`
- Loki readiness: `http://127.0.0.1:3100/ready`
- Node Exporter metrics: `http://127.0.0.1:9100/metrics`

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
sudo NODE_EXPORTER_VERSION=<version> ./shared/scripts/install-node-exporter.sh
```


---

## 🇻🇳 Tiếng Việt

Kết nối bảo mật an toàn giữa Edge và Cloud thông qua **WireGuard VPN trên sóng mạng 5G** dành cho các hệ thống phân tán.

Dự án này là minh chứng về việc xây dựng kiến trúc mạng nhẹ, bảo mật và dễ mở rộng kết nối giữa các **Thiết bị biên (Edge)** và **Máy chủ đám mây (Cloud)** thông qua **mạng ảo nội bộ trên nền tảng 5G**, tích hợp khả năng tự động đăng ký (Zero-touch), giám sát cơ sở hạ tầng và làm cứng (hardening) hệ thống.

---

## 🚀 Tổng quan

Các hệ thống phân tán hiện đại ngày càng phụ thuộc vào điện toán biên (Edge Computing) và kết nối không dây 5G.
Dự án này cho thấy cách triển khai một **đường hầm bảo mật Zero-Trust** giữa các Edge node và dịch vụ Cloud bằng việc sử dụng **WireGuard** trên thiết bị ARM nhúng.

Nền tảng này tích hợp sẵn:

- Phân hệ quan sát hạ tầng và log (Prometheus + Loki + Grafana, Edge dùng Alloy đẩy log).
- Áp dụng các tiêu chuẩn Làm cứng hệ thống/Bảo mật lõi (System Hardening).
- Auto-Registration API hỗ trợ tính năng gia nhập mạng VPN tự động (Zero-touch).

Các giá trị overlay mặc định trong repo này đã được chuẩn hoá về `10.8.0.0/24`.
Mô hình multi-peer trong repo dùng `10.8.0.1/24` cho server và cấp IP `/32` riêng cho từng edge peer.

---

## 🏗 Kiến trúc Hệ thống

                ┌────────────────────────┐
                │     Cloud Gateway      │
                │ (Amazon Linux 2023 EC2)│
                │ - Dịch vụ WireGuard    │
                │ - Registration API     │
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
│   └── COMMANDS.md           # Tổng hợp lệnh hay dùng
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
- **Đăng Ký VPN Tự Động (Zero-Touch):** Edge nodes có thể đăng ký bằng API dùng token, nhưng API ingress bị tắt mặc định và chỉ nên bật khi đã giới hạn CIDR tin cậy hoặc đặt sau TLS.
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
- `PROMETHEUS_VERSION`, `GRAFANA_VERSION`, `LOKI_VERSION`, `LOKI_PORT`, `ALLOY_LOKI_URL`: tham số runtime cho observability
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

_Hãy chuẩn bị `TF_VAR_wg_api_token` đủ mạnh trước khi chạy `terraform apply`. Terraform chỉ in endpoint, không in token._

Ví dụ mặc định hiện tại dùng:
- Overlay network: `10.8.0.0/24`
- Sample edge client IP: `10.8.0.2/32`
- Registration API: tắt mặc định
- Public registration API TLS endpoint: tự dùng Elastic IP của EC2 khi `registration_api_domain` để trống

Bạn có thể đặt `registration_api_domain` theo một trong hai cách:
- hostname public như `vpn-api.example.com`
- hoặc dùng trực tiếp Elastic IP của EC2

Nếu để trống `registration_api_domain`, Terraform sẽ tự dùng Elastic IP của EC2.

### 2. Kết nối Mạng phần cứng

Cắm anten, gắn 5G Module qua ngõ USB/PCIe M.2 vào thiết bị SBC (Ví dụ: Orange Pi). 

Bạn có thể chọn 1 trong 2 cách triển khai:

**Cách 1: Chạy trực tiếp qua Systemd (Khuyên dùng)**
```bash
cd edge/5g-wwan
sudo ./install.sh
```

Trình cài đặt edge cũng cài sẵn bộ công cụ vận hành:
- `curl`, `rsync`, `iperf3`, `git`, `tmux`, `stow`, `vim`, `wget`, `docker`, và Docker Compose v2
- `ufw` trên edge dùng `apt`, và trên edge dùng `dnf` nếu package tồn tại trong repo đã bật

**Cách 2: Đóng gói siêu sạch qua Docker (Alternative)**
```bash
cd edge/5g-wwan/docker
sudo docker compose up -d
```

### 3. Đăng ký Tự động Cấu Hình VPN

Sau khi có kết nối Internet do SIM cấp, khởi chạy đường hầm ảo vào hệ thống:

```bash
sudo ./edge/vpn/setup-wg-client.sh
```

_Chỉ nên chọn `Y` khi bạn đã chủ động bật API ingress và giới hạn nó về CIDR tin cậy hoặc đặt sau TLS._

Bootstrap cloud hiện tạo sẵn chứng chỉ self-signed để reverse proxy có TLS ngay từ đầu. Trước khi đưa vào production thật, hãy thay bằng chứng chỉ đáng tin cậy.

Client nên giữ:
- `Address = 10.8.0.x/32`
- `AllowedIPs = 10.8.0.0/24` nếu chỉ route trong overlay

Nếu cần gỡ cấu hình WireGuard client cục bộ trên edge sau này:

```bash
sudo ./edge/vpn/uninstall-wg-client.sh
```

Nếu muốn xóa cả key local:

```bash
sudo REMOVE_WG_KEYS=true ./edge/vpn/uninstall-wg-client.sh
```

Script này chỉ gỡ phía edge local. Nếu cần xóa peer trên cloud server thì phải thực hiện riêng bằng `wg set ... peer ... remove` và `wg-quick save`.

Bootstrap cloud cũng cài sẵn bộ công cụ vận hành trên Amazon Linux 2023:
- `curl`, `rsync`, `iperf3`, `git`, `tmux`, `stow`, `vim`, `wget`, `docker`, và Docker Compose v2

### 4. Phụ bản Quản trị (Bảo mật & Giám sát)

Hoạt động dùng chung ở cả 2 bề mặt của hệ thống:

```bash
sudo ./shared/scripts/hardening.sh
sudo ./shared/scripts/install-node-exporter.sh
```

`hardening.sh` sẽ tự nhận diện hệ điều hành:
- Edge Node chạy Armbian/Debian: cấu hình `ufw`
- Cloud Gateway chạy Amazon Linux 2023: cấu hình `firewalld`

Nếu bạn dùng cổng WireGuard khác `51820`, hãy chạy với biến `WIREGUARD_PORT=<port>`.
Trên edge node, rule TCP vào mặc định bổ sung là `443` và `5201` qua biến `EDGE_EXTRA_TCP_PORTS`. Repo này không tự thêm `8006` hoặc `64203`.

Đặt mật khẩu Grafana không mặc định rồi mới khởi chạy giám sát trên Cloud. Stack này chạy Prometheus, Loki và Grafana; Grafana tự provision datasource Prometheus/Loki bằng YAML.

```bash
set -a && . ./.env && set +a
cd cloud/monitoring
sudo docker compose up -d
```

Nếu muốn truy cập Grafana, Prometheus và Loki qua đường hầm WireGuard thay vì SSH tunnel, hãy đặt:

```bash
MONITORING_BIND_ADDRESS=10.8.0.1
ALLOW_MONITORING_OVER_WIREGUARD=true
```

Sau đó chạy lại:

```bash
sudo ./shared/scripts/hardening.sh
cd cloud/monitoring
sudo docker compose up -d
```

Mô hình này không cần mở thêm AWS Security Group cho `3000/tcp`, `9090/tcp`, `3100/tcp`, hoặc `9100/tcp`. Bên ngoài chỉ mở cổng UDP của WireGuard; Grafana, Prometheus, Loki và Node Exporter chỉ được truy cập sau khi gói tin được giải mã trên chính EC2.

Nếu muốn truy cập Web UI của monitoring qua SSH tunnel từ máy local:

```bash
ssh -i <your-key.pem> \
  -L 3000:127.0.0.1:3000 \
  -L 9090:127.0.0.1:9090 \
  -L 3100:127.0.0.1:3100 \
  -L 9100:127.0.0.1:9100 \
  ec2-user@<EC2_PUBLIC_IP>
```

Sau đó mở:
- Grafana: `http://127.0.0.1:3000`
- Prometheus: `http://127.0.0.1:9090`
- Loki readiness: `http://127.0.0.1:3100/ready`
- Node Exporter metrics: `http://127.0.0.1:9100/metrics`

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
sudo NODE_EXPORTER_VERSION=<version> ./shared/scripts/install-node-exporter.sh
```


---

## 👤 Author / Tác Giả

**Nguyen Trung Hieu**  
Cloud / System Engineer Enthusiast
