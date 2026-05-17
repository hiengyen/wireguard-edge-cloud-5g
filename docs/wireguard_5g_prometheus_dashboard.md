# 📈 WireGuard 5G Resource & Hardware Metrics Dashboard Blueprint

This document details the newly designed, high-performance **Prometheus Node Exporter Dashboard** specifically tailored to monitor hardware resources, CPU/SoC temperatures, disk capacity, and real-time WireGuard VPN / 5G cellular network bandwidth for both the Cloud Gateway and distributed Edge nodes.

> [!IMPORTANT]
> **Zero-Touch Provisioning Enabled!**  
> Just like our Loki log dashboard, this dashboard is configured directly inside the Grafana provisioning directory:
> - Config Provider: `cloud/monitoring/grafana/provisioning/dashboards/dashboards.yml`
> - Dashboard JSON: `cloud/monitoring/grafana/provisioning/dashboards/definitions/prometheus_node_exporter.json`
>
> Once your docker-compose monitoring stack is started or recreated, Grafana will **automatically import and provision** this dashboard. No manual imports required!

---

## 🏗️ Dashboard Layout & Panel Blueprints

The dashboard is structured into a clean, **100% full-width vertically stacked layout** (`w: 24`) designed for high-density, real-time resource analysis. The rows use flat, modern typography:

### 1. SYSTEM RESOURCES OVERVIEW
*   **System Uptime (Stat Panel):** Displays the elapsed time since the host last booted up.
    *   *PromQL Query:* `time() - node_boot_time_seconds{instance=~"$instance"}`
*   **CPU Utilization (Stat Panel):** Shows current total CPU usage percentage with color-coded critical thresholds (Orange > 70%, Red > 90%).
    *   *PromQL Query:* `100 - (avg by (instance) (irate(node_cpu_seconds_total{instance=~"$instance", mode="idle"}[5m])) * 100)`
*   **Memory Utilization (Stat Panel):** Shows real-time RAM usage percentage with precise threshold warnings.
    *   *PromQL Query:* `100 * (1 - (node_memory_MemAvailable_bytes{instance=~"$instance"} / node_memory_MemTotal_bytes{instance=~"$instance"}))`
*   **System Load 1m (Stat Panel):** Displays load averages over the last minute.
    *   *PromQL Query:* `node_load1{instance=~"$instance"}`

### 2. RESOURCE UTILIZATION TRENDS
*   **CPU Usage History (TimeSeries Graph):** Smooth time-series chart showing CPU usage breakdown by mode (idle, user, system, iowait).
    *   *PromQL Query:* `sum by (mode) (irate(node_cpu_seconds_total{instance=~"$instance"}[5m])) / count(node_cpu_seconds_total{instance=~"$instance", mode="idle"}) * 100`
*   **Memory Allocation History (TimeSeries Graph):** Smooth area chart tracking RAM allocation (Total vs Used vs Available).
    *   *PromQL Query:*
        - Total: `node_memory_MemTotal_bytes{instance=~"$instance"}`
        - Used: `node_memory_MemTotal_bytes{instance=~"$instance"} - node_memory_MemAvailable_bytes{instance=~"$instance"}`
        - Available: `node_memory_MemAvailable_bytes{instance=~"$instance"}`

### 3. NETWORK TRAFFIC & WIREGUARD VPN
*   **WireGuard Overlay Traffic - wg0 (TimeSeries Graph):** Displays high-precision real-time bandwidth consumption (in bps/Mbps) specifically traversing the WireGuard VPN overlay tunnel.
    *   *PromQL Query (Inbound/Outbound):*
        - Inbound: `irate(node_network_receive_bytes_total{instance=~"$instance", device="wg0"}[5m]) * 8`
        - Outbound: `irate(node_network_transmit_bytes_total{instance=~"$instance", device="wg0"}[5m]) * 8`
*   **5G WAN / Ethernet Interface Traffic (TimeSeries Graph):** Tracks raw physical interface bandwidth (e.g. Quectel 5G modem `wwan0`/`rmnet_data0`/`usb0` or `eth0`).
    *   *PromQL Query:*
        - Inbound: `irate(node_network_receive_bytes_total{instance=~"$instance", device=~"wwan.*|rmnet.*|usb.*|eth0"}[5m]) * 8`
        - Outbound: `irate(node_network_transmit_bytes_total{instance=~"$instance", device=~"wwan.*|rmnet.*|usb.*|eth0"}[5m]) * 8`

### 4. STORAGE & HARDWARE TEMPERATURE
*   **Storage Allocation (Root Partition) (Bar Gauge):** Modern horizontal LCD bar gauge displaying `/` partition usage.
    *   *PromQL Query:* `100 * (1 - (node_filesystem_free_bytes{instance=~"$instance", mountpoint="/"} / node_filesystem_size_bytes{instance=~"$instance", mountpoint="/"}))`
*   **Edge SoC / Hardware Temperature (Gauge Panel):** Dynamic radial gauge monitoring CPU/SoC temperatures. **Crucial for embedded single board computers like Orange Pi 5 Max to prevent thermal throttling!**
    *   *PromQL Query:* `avg by (instance) (node_thermal_zone_temp{instance=~"$instance"} / 1000) or avg by (instance) (node_hwmon_temp_celsius{instance=~"$instance"})`
    *   *Color-coded steps:* Green (<60°C), Orange (60°C - 75°C), Red (>75°C).

---

## 🚀 How to Load and Access

### Step 1: Recreate the Monitoring Containers on the Cloud Node
Run this command in the cloud gateway workspace:

```bash
cd cloud/monitoring
sudo -E docker compose --env-file ../../.env up -d --force-recreate
```

### Step 2: Access Grafana Dashboard
1. Open Grafana (`http://10.8.0.1:3000` or via SSH tunnel `http://127.0.0.1:3000`).
2. Navigate to **Dashboards** in the left-hand menu.
3. Click on the **Edge Monitoring** folder.
4. Click on **WireGuard 5G Resource & Hardware Metrics**.

---

## 🛠️ Dynamic Variables Explained
At the top of the dashboard, you will find one critical drop-down selector:
*   **`Host / Node`**: Automatically populated with all active nodes running Node Exporter. You can select "All" to view aggregated data or select `orangepi5-max` / `Cloud` to drill down into a single host!
