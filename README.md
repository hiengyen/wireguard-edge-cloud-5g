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

- Infrastructure monitoring (Prometheus + Grafana)
- System hardening and security best practices
- Auto-Registration API for seamless Zero-touch VPN enrollment

Default overlay network values in this repository are standardized to `10.8.0.0/24`.

---

## 🏗 Architecture

                ┌────────────────────────┐
                │     Cloud Gateway      │
                │ (Amazon Linux 2023 EC2)│
                │ - WireGuard Server     │
                │ - Registration API     │
                │ - Prometheus/Grafana   │
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
                └────────────────────────┘

---

## 📂 Repository Structure

```text
wireguard-edge-cloud-5g/
├── README.md                 # You are here!
├── cloud/                    # Cloud Gateway components
│   ├── terraform/ec2/        # AWS IaC (AWS Provider v6, EC2, SG, Auto-install WG & API)
│   ├── monitoring/           # Prometheus & Grafana docker infrastructure
│   └── vpn-reference/        # Reference configuration files
├── edge/                     # Edge Node components
│   ├── 5g-wwan/              # Cellular network physical layer scripts
│   │   ├── wwan-start.sh     # Dynamic device detection & QMI Raw-IP connect
│   │   ├── docker/           # Alternative: Containerized WWAN deployment
│   │   ├── install.sh        # Systemd installation script
│   │   └── uninstall.sh      # Cleanup automation
│   └── vpn/                  # VPN Overlay network layer
│       └── setup-wg-client.sh# Key generation & Zero-Touch cloud auto-registration
└── shared/                   # Cross-platform utilities
    └── scripts/
        ├── hardening.sh      # Distro-aware SSH/Firewall/Fail2Ban hardening
        └── install-node-exporter.sh # Prometheus metrics agent installation
```

## 🔐 Key Features

- **5G QMI Network Automation:** Dynamically locates and connects Quectel RM502Q-GL via raw IP.
- **Zero-Touch VPN Registration:** Edge nodes can register through a token-secured API, but API ingress is disabled by default and should be exposed only behind trusted CIDRs or TLS.
- **Infrastructure as Code (IaC):** Cloud environments are 100% automated using Terraform.
- **Observability:** Prometheus and Grafana dashboards actively pull metrics via the private `10.8.0.0/24` tunnel.
- **Hardening:** Best-practice security including OS-aware firewalling (`ufw` on Armbian/Debian, `firewalld` on Amazon Linux 2023), Fail2Ban, and key-only SSH.

## ⚙️ Environment File

The repository includes [`.env.example`](/home/hiengyen/CODE/wireguard-edge-cloud-5g/.env.example:1) to centralize deployment and runtime variables.

Important groups:
- `TF_VAR_*`: Terraform inputs for cloud provisioning
- `GRAFANA_ADMIN_PASSWORD`: password used by `cloud/monitoring/docker-compose.yml`
- `WIREGUARD_*`: edge VPN client runtime defaults
- `WWAN_APN`, `SSH_ADMIN_PORT`: edge WWAN and hardening runtime settings

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
- Sample edge client IP: `10.8.0.2/24`
- Registration API: disabled by default

### 2. Edge Physical Connection

Connect your Quectel 5G Module via USB/M.2 to the Edge SBC (e.g., Orange Pi). You have two deployment options:

**Option A: Systemd Service (Native)**
```bash
cd edge/5g-wwan
sudo ./install.sh
```

**Option B: Docker Containerized (Alternative)**
```bash
cd edge/5g-wwan/docker
sudo docker-compose up -d
```

### 3. Edge VPN Auto-Registration

Once connected to the internet, join the VPN overlay:

```bash
sudo ./edge/vpn/setup-wg-client.sh
```

_When prompted, use auto-registration only if you intentionally enabled API ingress and restricted it to trusted CIDRs or placed it behind TLS._

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

For Grafana, set a non-default password first, then start the monitoring stack:

```bash
set -a && . ./.env && set +a
cd cloud/monitoring
sudo docker-compose up -d
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

- Phân hệ Giám sát Hạ tầng (Prometheus + Grafana).
- Áp dụng các tiêu chuẩn Làm cứng hệ thống/Bảo mật lõi (System Hardening).
- Auto-Registration API hỗ trợ tính năng gia nhập mạng VPN tự động (Zero-touch).

Các giá trị overlay mặc định trong repo này đã được chuẩn hoá về `10.8.0.0/24`.

---

## 🏗 Kiến trúc Hệ thống

                ┌────────────────────────┐
                │     Cloud Gateway      │
                │ (Amazon Linux 2023 EC2)│
                │ - Dịch vụ WireGuard    │
                │ - Registration API     │
                │ - Prometheus/Grafana   │
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
                └────────────────────────┘

---

## 📂 Tổ chức Thư mục

```text
wireguard-edge-cloud-5g/
├── README.md                 # Chính là tài liệu này (Song ngữ)
├── cloud/                    # Phân hệ Máy chủ Cổng kết nối
│   ├── terraform/ec2/        # Triển khai tự động AWS (Provider v6, EC2, tự động tải WG & API)
│   ├── monitoring/           # Cụm Docker cho Prometheus & Grafana
│   └── vpn-reference/        # Nơi lưu cấu hình tham chiếu của Server
├── edge/                     # Phân hệ Thiết bị Đầu cuối
│   ├── 5g-wwan/              # Kịch bản giao tiếp phần cứng mạng di động
│   │   ├── wwan-start.sh     # Phát hiện thiết bị tĩnh/động & kết nối QMI Raw-IP
│   │   ├── docker/           # Triển khai giải pháp thay thế qua Docker Container
│   │   ├── install.sh        # Tiện ích tự động cài đặt Systemd Service
│   │   └── uninstall.sh      # Tiện ích dọn dẹp hệ thống
│   └── vpn/                  # Tầng mạng ảo (Overlay network)
│       └── setup-wg-client.sh# Sinh khóa mã hóa & Gia nhập mạng tự động không chạm
└── shared/                   # Các thư viện dùng chung cho cả Cloud và Edge
    └── scripts/
        ├── hardening.sh      # Hardening SSH/Firewall/Fail2Ban theo từng distro
        └── install-node-exporter.sh # Cài Agent theo dõi sức khoẻ phần cứng
```

## 🔐 Tính Năng Chính

- **Tự động Giao tiếp 5G QMI:** Định danh và kết nối tự động tới modem Quectel RM502Q-GL qua chế độ raw IP, hạn chế lỗi gán cứng `/dev/cdc-wdm0`.
- **Đăng Ký VPN Tự Động (Zero-Touch):** Edge nodes có thể đăng ký bằng API dùng token, nhưng API ingress bị tắt mặc định và chỉ nên bật khi đã giới hạn CIDR tin cậy hoặc đặt sau TLS.
- **Hạ tầng dưới dạng Mã (IaC):** Server rỗng được khởi tạo và cài cắm 100% tự động qua môi trường Terraform.
- **Khả năng Quan sát (Observability):** Dashboard Grafana và trạm trung chuyển Prometheus tự động cào metrics (sức khoẻ phần cứng) bọc kín theo luồng đường hầm `10.8.0.0/24`.
- **Bảo Mật (Hardening):** Áp dụng hardening theo môi trường đích: `ufw` cho Armbian/Debian ở Edge, `firewalld` cho Amazon Linux 2023 ở Cloud, kết hợp Fail2Ban và chỉ cho phép SSH bằng khoá.

## ⚙️ File Môi Trường

Repo có sẵn file [`.env.example`](/home/hiengyen/CODE/wireguard-edge-cloud-5g/.env.example:1) để gom các biến triển khai và runtime.

Các nhóm biến chính:
- `TF_VAR_*`: đầu vào Terraform cho phần cloud
- `GRAFANA_ADMIN_PASSWORD`: mật khẩu dùng cho `cloud/monitoring/docker-compose.yml`
- `WIREGUARD_*`: mặc định runtime cho edge VPN client
- `WWAN_APN`, `SSH_ADMIN_PORT`: tham số runtime cho WWAN và hardening

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
- Sample edge client IP: `10.8.0.2/24`
- Registration API: tắt mặc định

### 2. Kết nối Mạng phần cứng

Cắm anten, gắn 5G Module qua ngõ USB/PCIe M.2 vào thiết bị SBC (Ví dụ: Orange Pi). 

Bạn có thể chọn 1 trong 2 cách triển khai:

**Cách 1: Chạy trực tiếp qua Systemd (Khuyên dùng)**
```bash
cd edge/5g-wwan
sudo ./install.sh
```

**Cách 2: Đóng gói siêu sạch qua Docker (Alternative)**
```bash
cd edge/5g-wwan/docker
sudo docker-compose up -d
```

### 3. Đăng ký Tự động Cấu Hình VPN

Sau khi có kết nối Internet do SIM cấp, khởi chạy đường hầm ảo vào hệ thống:

```bash
sudo ./edge/vpn/setup-wg-client.sh
```

_Chỉ nên chọn `Y` khi bạn đã chủ động bật API ingress và giới hạn nó về CIDR tin cậy hoặc đặt sau TLS._

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

Đặt mật khẩu Grafana không mặc định rồi mới khởi chạy giám sát trên Cloud:

```bash
set -a && . ./.env && set +a
cd cloud/monitoring
sudo docker-compose up -d
```

---

## 👤 Author / Tác Giả

**Nguyen Trung Hieu**  
Cloud / System Engineer Enthusiast
