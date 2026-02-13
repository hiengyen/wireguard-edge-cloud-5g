# WireGuard Edge–Cloud 5G Secure Overlay

Secure Edge–Cloud connectivity using **WireGuard VPN over 5G** for distributed systems.

This project explores how to build a lightweight, secure, and scalable networking architecture that connects **Edge devices and Cloud infrastructure** through a **5G private overlay network**.

---

## 🚀 Overview

Modern distributed systems increasingly rely on Edge computing and 5G connectivity.  
This project demonstrates how to deploy a **Zero-Trust secure tunnel** between Edge nodes and Cloud services using **WireGuard** on embedded ARM devices.

The goal is to provide:

- Secure communication over public 5G networks
- Lightweight VPN suitable for edge hardware
- Easy deployment and reproducible lab environment
- Foundation for Edge-Cloud distributed data systems

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

       ┌──────────────┐
       │   Cloud VM   │
       │ WireGuard    │
       │ VPN Gateway  │
       └──────┬───────┘
              │ Encrypted Tunnel
              │ (WireGuard over 5G)
       ┌──────▼───────┐
       │ Edge Node    │
       │ Orange Pi 5  │
       │ + RM502Q-GL  │
       └──────────────┘


Key idea:
- 5G provides connectivity
- WireGuard provides encryption & identity
- Overlay network connects Edge ↔ Cloud securely

---

## 🔐 Key Features

- WireGuard VPN over 5G network
- Edge-to-Cloud secure tunnel
- ARM64 embedded deployment
- Zero-Trust networking model
- Low-latency encrypted communication
- Reproducible lab environment

---

## 🧪 Research Goals

This project investigates:

- Secure networking for Edge computing
- WireGuard performance over 5G
- Edge-Cloud architecture design
- Feasibility of lightweight VPN on ARM devices
- Foundation for distributed data collection systems

---

## ⚙️ Tech Stack

- WireGuard
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



