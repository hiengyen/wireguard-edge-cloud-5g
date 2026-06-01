# 📈 WireGuard 5G Resource & Hardware Metrics Dashboard Blueprint | Sơ Đồ Thiết Kế Dashboard Giám Sát Tài Nguyên & Cấu Hình Cứng WireGuard 5G

🇬🇧 [English](#-english) | 🇻🇳 [Tiếng Việt](#-tiếng-việt)

---

## 🇬🇧 English

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

---

## 🇻🇳 Tiếng Việt

Tài liệu này chi tiết hóa bản thiết kế **Prometheus Node Exporter Dashboard** hiệu năng cao, được tùy chỉnh chuyên biệt để giám sát tài nguyên phần cứng, nhiệt độ CPU/SoC, dung lượng ổ đĩa, và băng thông mạng thời gian thực của WireGuard VPN / 5G cho cả Cloud Gateway và các thiết bị biên Edge Node phân tán.

> [!IMPORTANT]
> **Kích hoạt Cơ Chế Tự Động Khởi Tạo (Zero-Touch Provisioning)!**  
> Tương tự như dashboard logs Loki, dashboard này được tích hợp cấu hình trực tiếp bên trong thư mục quản trị phân phối tự động của Grafana:
> - Tệp cấu hình phân phối: `cloud/monitoring/grafana/provisioning/dashboards/dashboards.yml`
> - Định nghĩa cấu trúc Dashboard: `cloud/monitoring/grafana/provisioning/dashboards/definitions/prometheus_node_exporter.json`
>
> Khi cụm Docker Compose giám sát được khởi động hoặc khởi tạo lại, Grafana sẽ **tự động import và kích hoạt** dashboard này cho bạn mà không cần bất kỳ thao tác thủ công nào!

---

## 🏗️ Bố Cục Dashboard & Thiết Kế Các Panel

Bố cục của dashboard được thiết kế theo dạng **dàn hàng dọc tối đa 100% độ rộng màn hình** (`w: 24`) giúp hiển thị mật độ thông tin cao cho việc phân tích tài nguyên thời gian thực. Các panel sử dụng ngôn ngữ thiết kế phẳng, hiện đại và tối giản:

### 1. TỔNG QUAN TÀI NGUYÊN HỆ THỐNG (SYSTEM RESOURCES OVERVIEW)
*   **Thời gian Hoạt động Hệ thống (Stat Panel):** Hiển thị tổng số thời gian máy chủ đã chạy liên tục kể từ lần khởi động gần nhất.
    *   *Câu lệnh PromQL:* `time() - node_boot_time_seconds{instance=~"$instance"}`
*   **Mức Độ Sử Dụng CPU (Stat Panel):** Hiển thị tỷ lệ phần trăm CPU tổng thể đang hoạt động đi kèm các ngưỡng cảnh báo màu sắc trực quan (Màu Cam > 70%, Màu Đỏ > 90%).
    *   *Câu lệnh PromQL:* `100 - (avg by (instance) (irate(node_cpu_seconds_total{instance=~"$instance", mode="idle"}[5m])) * 100)`
*   **Mức Độ Sử Dụng Bộ Nhớ RAM (Stat Panel):** Hiển thị tỷ lệ phần trăm dung lượng RAM thực tế đang bị chiếm dụng đi kèm các ngưỡng cảnh báo dung lượng trống.
    *   *Câu lệnh PromQL:* `100 * (1 - (node_memory_MemAvailable_bytes{instance=~"$instance"} / node_memory_MemTotal_bytes{instance=~"$instance"}))`
*   **Độ Tải Hệ Thống 1 Phút Gần Nhất (Stat Panel):** Hiển thị chỉ số Load Average trung bình của CPU trong vòng 1 phút qua.
    *   *Câu lệnh PromQL:* `node_load1{instance=~"$instance"}`

### 2. XU HƯỚNG SỬ DỤNG TÀI NGUYÊN (RESOURCE UTILIZATION TRENDS)
*   **Lịch Sử Sử Dụng CPU (Biểu đồ TimeSeries):** Biểu đồ dạng đường mượt mà mô tả chi tiết trạng thái hoạt động của CPU phân bổ theo từng chế độ (idle, user, system, iowait).
    *   *Câu lệnh PromQL:* `sum by (mode) (irate(node_cpu_seconds_total{instance=~"$instance"}[5m])) / count(node_cpu_seconds_total{instance=~"$instance", mode="idle"}) * 100`
*   **Lịch Sử Cấp Phát Bộ Nhớ (Biểu đồ TimeSeries):** Biểu đồ dạng vùng (area chart) theo dõi trực quan lượng RAM cấp phát (Tổng RAM vs RAM Sử dụng vs RAM Sẵn có).
    *   *Câu lệnh PromQL:*
        - Tổng RAM: `node_memory_MemTotal_bytes{instance=~"$instance"}`
        - RAM Sử dụng: `node_memory_MemTotal_bytes{instance=~"$instance"} - node_memory_MemAvailable_bytes{instance=~"$instance"}`
        - RAM Sẵn có: `node_memory_MemAvailable_bytes{instance=~"$instance"}`

### 3. BĂNG THÔNG MẠNG & WIREGUARD VPN (NETWORK TRAFFIC & WIREGUARD VPN)
*   **Lưu Lượng Mạng Ảo WireGuard Overlay - wg0 (Biểu đồ TimeSeries):** Hiển thị băng thông thời gian thực độ chính xác cao (đơn vị bps/Mbps) truyền tải trực tiếp thông qua đường hầm mã hóa WireGuard VPN overlay.
    *   *Câu lệnh PromQL (Đầu vào/Đầu ra):*
        - Đầu vào (Inbound): `irate(node_network_receive_bytes_total{instance=~"$instance", device="wg0"}[5m]) * 8`
        - Đầu ra (Outbound): `irate(node_network_transmit_bytes_total{instance=~"$instance", device="wg0"}[5m]) * 8`
*   **Lưu Lượng Mạng Di Động 5G WAN / Cổng Ethernet Vật Lý (Biểu đồ TimeSeries):** Đo đạc băng thông thực tế chạy qua các giao diện mạng vật lý (ví dụ: cổng modem 5G Quectel `wwan0`/`rmnet_data0`/`usb0` hoặc card mạng dây `eth0`).
    *   *Câu lệnh PromQL:*
        - Đầu vào (Inbound): `irate(node_network_receive_bytes_total{instance=~"$instance", device=~"wwan.*|rmnet.*|usb.*|eth0"}[5m]) * 8`
        - Đầu ra (Outbound): `irate(node_network_transmit_bytes_total{instance=~"$instance", device=~"wwan.*|rmnet.*|usb.*|eth0"}[5m]) * 8`

### 4. DUNG LƯỢNG LƯU TRỮ & NHIỆT ĐỘ PHẦN CỨNG (STORAGE & HARDWARE TEMPERATURE)
*   **Dung Lượng Ổ Đĩa (Phân Vùng Gốc /) (Bar Gauge):** Thanh đo dạng LCD nằm ngang thể hiện tỷ lệ phần trăm dung lượng bộ nhớ lưu trữ đã sử dụng trên phân vùng `/`.
    *   *Câu lệnh PromQL:* `100 * (1 - (node_filesystem_free_bytes{instance=~"$instance", mountpoint="/"} / node_filesystem_size_bytes{instance=~"$instance", mountpoint="/"}))`
*   **Nhiệt Độ SoC / Chip Cứng Edge Node (Gauge Panel):** Đồng hồ đo góc tròn hiển thị động nhiệt độ CPU/SoC. **Đặc biệt quan trọng đối với các máy tính nhúng nhỏ gọn như Orange Pi 5 Max để kịp thời cảnh báo, ngăn ngừa việc hạ hiệu năng do quá nhiệt (thermal throttling)!**
    *   *Câu lệnh PromQL:* `avg by (instance) (node_thermal_zone_temp{instance=~"$instance"} / 1000) or avg by (instance) (node_hwmon_temp_celsius{instance=~"$instance"})`
    *   *Định nghĩa màu sắc:* Màu Xanh (<60°C), Màu Cam (60°C - 75°C), Màu Đỏ (>75°C).

---

## 🚀 Cách Thức Áp Dụng Và Khởi Chạy

### Bước 1: Khởi Tạo Lại Cụm Container Giám Sát Trên Cloud Node
Khởi chạy câu lệnh sau tại thư mục giám sát của Cloud Gateway:

```bash
cd cloud/monitoring
sudo -E docker compose --env-file ../../.env up -d --force-recreate
```

### Bước 2: Truy Cập Giao Diện Dashboard Grafana
1. Mở trình duyệt truy cập Grafana (`http://10.8.0.1:3000` hoặc thiết lập SSH tunnel `http://127.0.0.1:3000`).
2. Di chuyển đến menu **Dashboards** ở thanh công cụ bên trái.
3. Nhấp chọn thư mục **Edge Monitoring**.
4. Chọn dashboard **WireGuard 5G Resource & Hardware Metrics**.

---

## 🛠️ Giải Thích Các Biến Động (Dynamic Variables)
Ở phía trên cùng của giao diện dashboard, bạn sẽ thấy một bộ lọc quan trọng:
*   **`Host / Node`**: Tự động hiển thị danh sách tất cả các host đang kích hoạt dịch vụ Node Exporter đẩy dữ liệu về. Bạn có thể chọn "All" để xem dữ liệu tổng hợp gộp chung, hoặc chọn riêng biệt `orangepi5-max` / `Cloud` để phân tích chuyên sâu cho từng thiết bị!
