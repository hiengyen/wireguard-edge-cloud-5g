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
        ├── hardening.sh      # UFW Firewall & Fail2Ban & SSH security config
        └── install-node-exporter.sh # Prometheus metrics agent installation
```

## 🔐 Key Features

- **5G QMI Network Automation:** Dynamically locates and connects Quectel RM502Q-GL via raw IP.
- **Zero-Touch VPN Registration:** Edge nodes automatically generate key pairs and register with the AWS Cloud Gateway through a token-secured REST API.
- **Infrastructure as Code (IaC):** Cloud environments are 100% automated using Terraform.
- **Observability:** Prometheus and Grafana dashboards actively pull metrics via the private `10.8.0.x` tunnel.
- **Hardening:** Best-practice security including UFW restricted ports, Fail2Ban, and key-only SSH.

---

## 🚀 Quick Start

### 1. Cloud Provisioning

Deploy the Cloud Server using Terraform:

```bash
cd cloud/terraform/ec2
terraform init
terraform plan -out=tfplan
terraform apply "tfplan"
```

_Note down the API token, Server Endpoint, and Port displayed in the Terraform outputs or inside `variables.tf`._

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

_When prompted, select `Y` to automatically register the device via the API, using the Token specified in Terraform._

### 4. Shared Operations (Hardening & Monitoring)

On both environments, run:

```bash
sudo ./shared/scripts/hardening.sh
sudo ./shared/scripts/install-node-exporter.sh
```

For Grafana, navigate to the Cloud node:

```bash
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
        ├── hardening.sh      # Bật UFW Firewall, Fail2Ban, cấm SSH password
        └── install-node-exporter.sh # Cài Agent theo dõi sức khoẻ phần cứng
```

## 🔐 Tính Năng Chính

- **Tự động Giao tiếp 5G QMI:** Định danh và kết nối tự động tới modem Quectel RM502Q-GL qua chế độ raw IP, hạn chế lỗi gán cứng `/dev/cdc-wdm0`.
- **Đăng Ký VPN Tự Động (Zero-Touch):** Edge nodes tự định hình cặp khóa bảo mật và đăng ký xin phép truy cập lên trung tâm AWS bằng một REST API kết nối qua phương thức Token bảo mật.
- **Hạ tầng dưới dạng Mã (IaC):** Server rỗng được khởi tạo và cài cắm 100% tự động qua môi trường Terraform.
- **Khả năng Quan sát (Observability):** Dashboard Grafana và trạm trung chuyển Prometheus tự động cào metrics (sức khoẻ phần cứng) bọc kín theo luồng đường hầm `10.8.0.x`.
- **Bảo Mật (Hardening):** Áp dụng tiêu chuẩn bảo mật cho Amazon Linux 2023 qua tường lửa drop-all của UFW (Port-whitelist), Fail2Ban chặn bruteforce, và loại bỏ hoàn toàn SSH bằng tài khoản/mật khẩu.

---

## 🚀 Hướng Dẫn Nhanh

### 1. Triển khai Cloud

Xây dựng Server Cloud qua Terraform:

```bash
cd cloud/terraform/ec2
terraform init
terraform plan -out=tfplan
terraform apply "tfplan"
```

_Lưu ý ghi chép lại các giá trị đầu ra (API token, Endpoint, Port Server, v.v)._

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

_Gõ phím `Y` khi nhận được lời mời hỏi để hệ thống tiến hành giao tiếp nối kết chìa khoá tự động qua API._

### 4. Phụ bản Quản trị (Bảo mật & Giám sát)

Hoạt động dùng chung ở cả 2 bề mặt của hệ thống:

```bash
sudo ./shared/scripts/hardening.sh
sudo ./shared/scripts/install-node-exporter.sh
```

Trực tiếp kích hoạt giao diện trang điều khiển giám sát (chỉ chạy trên Cloud):

```bash
cd cloud/monitoring
sudo docker-compose up -d
```

---

## 👤 Author / Tác Giả

**Nguyen Trung Hieu**  
Cloud / System Engineer Enthusiast
