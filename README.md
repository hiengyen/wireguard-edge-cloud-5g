# WireGuard Edge–Cloud 5G Secure Overlay

Secure Edge–Cloud connectivity using **WireGuard VPN over 5G** for distributed systems.

This project explores how to build a lightweight, secure, and scalable networking architecture that connects **Edge devices and Cloud infrastructure** through a **5G private overlay network**, combined with **monitoring and system hardening**.

---

## 🚀 Overview

Modern distributed systems increasingly rely on Edge computing and 5G connectivity.  
This project demonstrates how to deploy a **Zero-Trust secure tunnel** between Edge nodes and Cloud services using **WireGuard** on embedded ARM devices.

The platform also integrates:

- Infrastructure monitoring (Prometheus + Grafana)
- System hardening and security best practices
- Reproducible lab environment for Edge–Cloud research

---

## 🧰 Hardware Platform

Edge node is built on an ARM64 embedded platform:

| Component | Model |
|---|---|
| SBC | **Orange Pi 5 Max** |
| WWAN Adapter | **ADTlink WS18** |
| 5G Module | **Quectel RM502Q-GL** |

This setup provides real **5G connectivity** for testing secure overlay networking in realistic conditions.

---

## 🏗 Architecture

                ┌────────────────────┐
                │   Cloud Gateway    │
                │ WireGuard Server   │
                │ Prometheus Server  │
                │ Grafana Dashboard  │
                └─────────┬──────────┘
                          │
            Encrypted Tunnel (WireGuard over 5G)
                          │
                ┌─────────▼──────────┐
                │     Edge Node      │
                │   Orange Pi 5 Max  │
                │ WireGuard Client   │
                │ Node Exporter      │
                └────────────────────┘

---

## 🔐 Key Features

- WireGuard VPN over public 5G network
- Secure Edge ↔ Cloud overlay network
- ARM64 embedded deployment
- Zero-Trust networking model
- Real-time infrastructure monitoring
- Hardened Linux systems

---

## 📊 Monitoring Stack

To ensure visibility and observability of the Edge-Cloud infrastructure, the project deploys a lightweight monitoring stack.

### Components

| Tool | Purpose |
|---|---|
| **Prometheus** | Metrics collection & time-series database |
| **Grafana** | Visualization & dashboards |
| **Node Exporter** | System metrics from Edge node |

### Collected Metrics

- CPU / RAM / Disk usage
- Network throughput over WireGuard tunnel
- System uptime and load
- 5G connectivity performance indicators

### Monitoring Goals

- Detect performance bottlenecks
- Observe WireGuard tunnel stability
- Monitor resource usage on embedded hardware
- Provide real-time dashboards for operations

---

## 🛡 System Hardening

Security is a core focus of this project.  
Both Edge and Cloud nodes follow Linux hardening best practices.

### Hardening Measures

**Network Security**
- Disable password SSH login
- Enforce SSH key authentication
- Firewall rules using `iptables` / `nftables`
- Restrict exposed ports

**System Security**
- Minimal package installation
- Automatic security updates
- Strong file permissions
- Audit logging enabled

**WireGuard Security**
- Public-key cryptography authentication
- Limited peer access control
- Private overlay network isolation

---

## 🧪 Research Goals

This project investigates:

- Secure networking for Edge computing
- WireGuard performance over 5G
- Monitoring distributed Edge infrastructure
- Hardening embedded Linux devices
- Building Zero-Trust Edge-Cloud architecture

---

## ⚙️ Tech Stack

- WireGuard
- Prometheus + Grafana
- Linux (Ubuntu/Debian ARM64)
- 5G WWAN (Quectel RM502Q-GL)
- Embedded networking (Orange Pi 5 Max)

---

## 📂 Repository Structure (planned)


---

## 📌 Status

🚧 Work in progress — lab environment under development.

---

## 👤 Author

Nguyen Trung Hieu  
Cloud / System Engineer Enthusiast
