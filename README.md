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


