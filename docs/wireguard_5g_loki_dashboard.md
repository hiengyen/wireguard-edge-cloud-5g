# WireGuard 5G Edge Observability Dashboard Blueprint | Sơ Đồ Thiết Kế Dashboard Giám Sát WireGuard 5G Edge

🇬🇧 [English](#-english) | 🇻🇳 [Tiếng Việt](#-tiếng-việt)

---

## 🇬🇧 English

This document details the newly designed, high-performance **Grafana Loki Dashboard** specifically customized to monitor your WireGuard Edge-Cloud 5G overlay network, system hardening, and 5G Quectel cellular modem logs.

> [!IMPORTANT]
> **Zero-Touch Provisioning Enabled!**  
> We have automated the loading of this dashboard. It is configured directly inside the Grafana provisioning directory:
> - Config Provider: `cloud/monitoring/grafana/provisioning/dashboards/dashboards.yml`
> - Dashboard JSON: `cloud/monitoring/grafana/provisioning/dashboards/definitions/loki_edge_5g.json`
>
> When you start or restart your monitoring Docker containers, Grafana will **automatically import and configure** this dashboard for you. No manual JSON copy-pasting is required.

---

## 🏗️ Dashboard Layout & Panel Blueprints

The dashboard is structured into a clean, **100% full-width vertically stacked layout** (`w: 24`) designed for high-density log reading without side-by-side splits. The rows use a flat, modern typography aesthetic:

### 1. SYSTEM OVERVIEW & LOGS RATE
*   **Total Logs Received (Stat Panel):** Shows the total logs received across all nodes.
    *   *LogQL Query:* `sum(count_over_time({job="$job", host=~"$host"}[$__range]))`
*   **Log Distribution by Service / Systemd Unit (Donut Chart):** Shows which services are generating the most logs.
    *   *Layout Optimization:* Donut slice labels are disabled (`displayLabels: []`) to keep the visual clean and uncluttered. It relies on the interactive **Table Legend** on the right, which displays absolute log count and percentages.
    *   *LogQL Query:* `sum by (unit) (count_over_time({job="$job", host=~"$host"} | regexp "^.*? (?P<unit>[a-zA-Z0-9\-_.]+)(?:\[\d+\])?:" [$__interval]))`

### 2. 5G CELLULAR & WIREGUARD VPN OVERLAY MONITORING
*   **5G Modem & Cellular Connection Logs (Logs Panel):** Focuses on cellular dynamic detection, raw IP configuration, APN handshakes, and WWAN disconnect/reconnect signals.
    *   *LogQL Query:* `{job="$job", host=~"$host"} |~ "(?i)(wwan|quectel|qmi|cdc-wdm|apn|sim|signal|disconnect|reconnect|cm)"`
*   **WireGuard Secure VPN Overlay Logs (Logs Panel):** Tracks secure VPN tunnel health, keepalives, and peer handshakes.
    *   *LogQL Query:* `{job="$job", host=~"$host"} |~ "(?i)(\bwireguard\b|wg0|handshake|peer|keepalive|endpoint)"`

### 3. SYSTEM SECURITY & HARDENING (SSH & FIREWALL)
*   **Blocked Intrusion Attempts per Node (Stat Panel):** Displays an alarming red card counting failed SSH logins or Fail2Ban bans, grouped automatically by host.
    *   *LogQL Query:* `sum by (host) (count_over_time({job="$job", host=~"$host"} |~ "(?i)(sshd.*Failed|fail2ban.*Ban)" [$__range]))`
*   **Security History & Blocked Attacks (Logs Panel):** Aggregates direct unauthorized SSH attempts, UFW/Firewalld block alerts, and iptables warnings.
    *   *LogQL Query:* `{job="$job", host=~"$host"} |~ "(?i)(sshd.*(Failed|Accepted|invalid)|fail2ban.*Ban|ufw.*BLOCK|firewall)"`

### 4. SYSTEM ALERTS & KERNEL PANICS
*   **Critical System & Kernel Logs (Logs Panel):** Isolates critical system issues like Out-Of-Memory (OOM) kills, kernel panics, hardware errors, segment faults, or crashed Systemd units.
    *   *LogQL Query:* `{job="$job", host=~"$host"} |~ "(?i)(oom|panic|hardware error|segfault|kill|aborted|critical|exception|failed to start)"`

---

## ⚠️ Edge Time Synchronization (Critical Gotcha)

Embedded ARM single-board computers (such as Orange Pi 5 Max) **do not have a hardware RTC battery backup by default**. If they lose power or internet access, their system clock can fall back to a hardcoded past date (e.g. May 12th instead of May 18th).

**Why this breaks the Loki dashboard:**
1. **Loki Discards Logs:** Loki rejects logs that are too far behind the active ingestion window (e.g., older than 2-7 days).
2. **Outside Grafana Query Range:** If Grafana is set to query "Last 1 hour" of today, logs dated days in the past will simply never appear.

**How to verify and fix the Edge clock:**
Check the time on the Edge:
```bash
date
# Or view synchronization status
timedatectl
```
To instantly fix the time without rebooting, run:
```bash
# Option A: Automatic NTP sync
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd

# Option B: Manual clock sync (set to today's date)
sudo date -s "2026-05-18 00:20:00"
```
After fixing the date, always **restart Alloy** to flush logs with correct timestamps:
```bash
sudo systemctl restart alloy
```

---

## 🛡️ 5G CGNAT Stealth Topology Note

Because the Edge node connects through a **5G QMI cellular interface**, it naturally sits behind **CGNAT (Carrier-Grade NAT)** provided by the cellular network operator. 

*   **Immune to Scans:** The Edge node has no public inbound IPv4 address. It is practically impossible for internet scanners, hackers, or automated bots to scan or brute-force SSH on the Orange Pi.
*   **Log Behavior:** As a result, the **SYSTEM SECURITY & HARDENING** panel for the Edge node host will naturally display `"No data"`. This is highly secure architecture by design!
*   **Cloud Node exposure:** Only the Cloud Gateway (which has a public Elastic IP) will show active security brute-force blocks if SSH port 22 is exposed to `0.0.0.0/0`.

---

## 🧪 Simulating and Testing Dashboard Panels

Because your systems operate healthily under normal circumstances, the **SYSTEM ALERTS & KERNEL PANICS** and **SYSTEM SECURITY** panels will naturally display `"No data"`. 

To safely test these panels and verify the ingestion pipeline, run these simulation commands:

### A. Simulating a System Crash (Alerts Panel)
Run on the host:
```bash
logger "TEST ALERT: segfault crash in system service, critical exception triggered"
```

### B. Simulating an SSH Intrusion Attempt (Security Panel)
```bash
logger "sshd[9999]: Failed password for invalid user hacker from 192.168.1.100 port 54321 ssh2"
```

### C. Simulating a Fail2Ban Ban (Security Panel)
```bash
logger "fail2ban.actions[1234]: WARNING [sshd] Ban 192.168.1.100"
```

Within **5 to 10 seconds**, Grafana will pick up these mock logs, and the red counters and history tables will instantly spring to life!

---

## 🛡️ Production Hardening: Docker Log Rotation

To prevent container logs (from Loki, Prometheus, and Grafana) from consuming all available disk space over long runtimes, we have implemented automated **Docker Log Rotation** inside `cloud/monitoring/docker-compose.yml`:

```yaml
    logging:
      driver: "json-file"
      options:
        max-size: "50m" # Keep each log file under 50MB
        max-file: "3"   # Maintain at most 3 historical files per container (max 150MB total)
```

---

## 🚀 How to Apply and Run

### Step 1: Apply the configuration
Run the command below in the cloud gateway workspace:

```bash
cd cloud/monitoring
sudo -E docker compose --env-file ../../.env up -d --force-recreate
```

### Step 2: Access Grafana UIs
If using a WireGuard overlay, access directly at: `http://10.8.0.1:3000`  
Otherwise, set up an SSH tunnel:
```bash
ssh -i <your-key.pem> -N -L 3000:10.8.0.1:3000 ec2-user@<EC2_PUBLIC_IP>
```
Open your browser to `http://127.0.0.1:3000`.

---

## 🛠️ Dynamic Variables Explained
At the top of the dashboard, you will find two drop-down selectors:
*   **`Job`**: Set of jobs (defaults to `edge-journal`).
*   **`Node / Host`**: Automatically dynamically lists all Cloud and Edge hosts pushing logs. If you select "All", statistics are aggregated; or you can filter down to one specific host.

---

## 🇻🇳 Tiếng Việt

Tài liệu này chi tiết hóa bản thiết kế **Grafana Loki Dashboard** hiệu năng cao, được tùy chỉnh chuyên biệt để giám sát mạng ảo WireGuard Edge-Cloud 5G overlay, quá trình làm cứng hệ thống bảo mật và nhật ký log từ modem di động 5G Quectel.

> [!IMPORTANT]
> **Kích hoạt Cơ Chế Tự Động Khởi Tạo (Zero-Touch Provisioning)!**  
> Chúng tôi đã tự động hóa hoàn toàn quy trình nạp dashboard này. Nó được cấu hình sẵn bên trong thư mục quản trị tự động của Grafana:
> - Tệp cấu hình phân phối: `cloud/monitoring/grafana/provisioning/dashboards/dashboards.yml`
> - Định nghĩa cấu trúc Dashboard: `cloud/monitoring/grafana/provisioning/dashboards/definitions/loki_edge_5g.json`
>
> Khi bạn khởi động hoặc khởi động lại cụm Docker containers giám sát, Grafana sẽ **tự động import và cấu hình sẵn** dashboard này cho bạn. Bạn tuyệt đối không cần thực hiện copy-paste mã JSON thủ công bằng tay.

---

## 🏗️ Bố Cục Dashboard & Thiết Kế Các Panel

Bố cục của dashboard được thiết kế theo dạng **dàn hàng dọc tối đa 100% độ rộng màn hình** (`w: 24`) giúp tăng cường khả năng đọc nhật ký log dải dày mà không bị phân mảnh ngang. Các hàng panel sử dụng ngôn ngữ thiết kế phẳng, hiện đại và tinh tế:

### 1. SYSTEM OVERVIEW & LOGS RATE (TỔNG QUAN HỆ THỐNG & TỐC ĐỘ LOG)
*   **Tổng số Log Đã Nhận (Stat Panel):** Hiển thị tổng số bản ghi log thu thập được từ tất cả các node.
    *   *Câu lệnh LogQL:* `sum(count_over_time({job="$job", host=~"$host"}[$__range]))`
*   **Phân bổ Log theo Dịch vụ / Systemd Unit (Biểu đồ Donut):** Biểu diễn tỷ lệ phát sinh log từ các dịch vụ phần mềm khác nhau.
    *   *Tối ưu hóa Bố cục:* Ẩn nhãn trực tiếp trên lát cắt của donut (`displayLabels: []`) để giữ giao diện luôn tinh tế, sạch sẽ. Panel sử dụng **Table Legend** tương tác ở bên phải hiển thị số lượng log tuyệt đối và tỷ lệ phần trăm cụ thể.
    *   *Câu lệnh LogQL:* `sum by (unit) (count_over_time({job="$job", host=~"$host"} | regexp "^.*? (?P<unit>[a-zA-Z0-9\-_.]+)(?:\[\d+\])?:" [$__interval]))`

### 2. 5G CELLULAR & WIREGUARD VPN OVERLAY MONITORING (GIÁM SÁT MẠNG DI ĐỘNG 5G & WIREGUARD VPN OVERLAY)
*   **Log của Modem 5G & Kết nối Di động (Logs Panel):** Tập trung vào tiến trình tự động phát hiện mạng di động, gán địa chỉ IP thô (raw IP), bắt tay APN và các tín hiệu mất/kết nối lại mạng WWAN.
    *   *Câu lệnh LogQL:* `{job="$job", host=~"$host"} |~ "(?i)(wwan|quectel|qmi|cdc-wdm|apn|sim|signal|disconnect|reconnect|cm)"`
*   **Log của Mạng Ảo Bảo Mật WireGuard VPN Overlay (Logs Panel):** Theo dõi sức khỏe đường hầm VPN, gói tin duy trì kết nối (keepalive) và các sự kiện bắt tay (handshake) của các peers.
    *   *Câu lệnh LogQL:* `{job="$job", host=~"$host"} |~ "(?i)(\bwireguard\b|wg0|handshake|peer|keepalive|endpoint)"`

### 3. BẢO MẬT & LÀM CỨNG HỆ THỐNG - SSH & FIREWALL (SYSTEM SECURITY & HARDENING)
*   **Số Vụ Tấn Công Bị Chặn Trên Mỗi Node (Stat Panel):** Hiển thị dưới dạng thẻ màu đỏ cảnh báo (alarming red card) tổng hợp số lần thử đăng nhập SSH sai hoặc các lượt khóa tài khoản từ Fail2Ban, tự động nhóm theo host.
    *   *Câu lệnh LogQL:* `sum by (host) (count_over_time({job="$job", host=~"$host"} |~ "(?i)(sshd.*Failed|fail2ban.*Ban)" [$__range]))`
*   **Lịch sử Bảo mật & Các Cuộc Tấn công Bị Chặn (Logs Panel):** Tổng hợp chi tiết các lượt truy cập SSH không hợp lệ, cảnh báo chặn gói tin từ tường lửa UFW/Firewalld và các cảnh báo từ iptables.
    *   *Câu lệnh LogQL:* `{job="$job", host=~"$host"} |~ "(?i)(sshd.*(Failed|Accepted|invalid)|fail2ban.*Ban|ufw.*BLOCK|firewall)"`

### 4. SYSTEM ALERTS & KERNEL PANICS (CẢNH BÁO HỆ THỐNG & KERNEL PANICS)
*   **Log Cảnh báo Hệ thống & Lỗi Nhân Kernel (Logs Panel):** Lọc riêng các lỗi nghiêm trọng cấp độ hệ thống như kích hoạt tắt ứng dụng do tràn bộ nhớ (Out-Of-Memory/OOM kills), lỗi nhân kernel panic, lỗi phần cứng (hardware error), phân mảnh bộ nhớ (segfault) hoặc lỗi crash hệ thống của dịch vụ Systemd.
    *   *Câu lệnh LogQL:* `{job="$job", host=~"$host"} |~ "(?i)(oom|panic|hardware error|segfault|kill|aborted|critical|exception|failed to start)"`

---

## ⚠️ Đồng Bộ Giờ Trên Thiết Bị Biên (Lưu Ý Cực Kỳ Quan Trọng)

Các bo mạch máy tính nhúng ARM (như Orange Pi 5 Max) **mặc định thường không tích hợp sẵn pin dự phòng RTC cho chip giờ cứng**. Khi bị mất điện nguồn hoặc mất mạng, đồng hồ hệ thống có thể bị reset lùi về một mốc thời gian cũ trong quá khứ (ví dụ: ngày 12 tháng 5 thay vì ngày 18 tháng 5).

**Tại sao việc lệch giờ sẽ làm hỏng Dashboard Loki:**
1. **Loki Từ Chối Nhận Log:** Loki sẽ tự động reject các log có mốc thời gian quá lệch so với thời gian hiện tại của máy chủ Loki (lệch quá cửa sổ nhận log từ 2-7 ngày).
2. **Nằm Ngoài Khoảng Truy Vấn Của Grafana:** Nếu bạn đang chọn xem log trên Grafana trong khoảng "1 giờ qua", thì các bản ghi log bị đánh dấu thời gian của những ngày trước đó sẽ không bao giờ được hiển thị.

**Cách kiểm tra và sửa giờ trên Edge Node:**
Kiểm tra thời gian hiện tại:
```bash
date
# Hoặc xem trạng thái đồng bộ giờ
timedatectl
```
Đồng bộ giờ nhanh không cần khởi động lại:
```bash
# Phương án A: Tự động đồng bộ qua NTP
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd

# Phương án B: Cài đặt giờ thủ công bằng tay (đặt theo ngày giờ hiện tại)
sudo date -s "2026-05-18 00:20:00"
```
Sau khi sửa giờ hệ thống, luôn luôn **khởi động lại Alloy** để dọn dẹp bộ đệm log cũ và đẩy các log mới đi kèm timestamp chuẩn xác:
```bash
sudo systemctl restart alloy
```

---

## 🛡️ Lưu Ý Về Kiến Trúc Ẩn Danh Phía Sau 5G CGNAT

Vì thiết bị biên Edge Node kết nối Internet qua **giao diện mạng di động 5G QMI**, thiết bị này sẽ nằm ẩn phía sau hệ thống dịch địa chỉ **CGNAT (Carrier-Grade NAT)** của nhà mạng viễn thông.

*   **Chống Quét Gói Tin (Immune to Scans):** Edge Node không có địa chỉ IPv4 công cộng để tiếp nhận kết nối đầu vào. Nhờ đó, các hacker, bot tự động hay công cụ quét cổng trên Internet hoàn toàn không thể tiếp cận hay tấn công brute-force SSH vào thiết bị Orange Pi của bạn.
*   **Trạng thái Hiển thị Log:** Do đặc tính an toàn trên, bảng panel **BẢO MẬT & LÀM CỨNG HỆ THỐNG** của Edge Node sẽ tự động hiển thị trạng thái `"No data"`. Đây là một đặc điểm thiết kế kiến trúc bảo mật cực kỳ an toàn!
*   **Đối với Cloud Node:** Chỉ có Cloud Gateway (do sử dụng địa chỉ Elastic IP public trực tiếp) mới xuất hiện các cảnh báo brute-force và nhật ký chặn nếu cổng SSH 22 được mở công khai ra toàn thế giới `0.0.0.0/0`.

---

## 🧪 Giả Lập Và Kiểm Thử Các Panel Trên Dashboard

Trong điều kiện vận hành bình thường, các bảng **CẢNH BÁO HỆ THỐNG & KERNEL PANICS** và **BẢO MẬT HỆ THỐNG** sẽ hiển thị trạng thái `"No data"`.

Để kiểm thử nhanh và xác minh đường truyền log hoạt động thông suốt, hãy thực thi các câu lệnh giả lập sau trực tiếp trên thiết bị:

### A. Giả lập một lỗi Crash hệ thống (Panel Alerts)
Khởi chạy lệnh:
```bash
logger "TEST ALERT: segfault crash in system service, critical exception triggered"
```

### B. Giả lập một cuộc tấn công dò mật khẩu SSH (Panel Security)
```bash
logger "sshd[9999]: Failed password for invalid user hacker from 192.168.1.100 port 54321 ssh2"
```

### C. Giả lập một hành vi khóa IP của Fail2Ban (Panel Security)
```bash
logger "fail2ban.actions[1234]: WARNING [sshd] Ban 192.168.1.100"
```

Trong vòng **5 đến 10 giây**, Grafana sẽ tự động cào các log giả lập này, và các biểu đồ đếm màu đỏ cùng bảng lịch sử tấn công sẽ lập tức hiển thị dữ liệu!

---

## 🛡️ Làm Cứng Môi Trường Thực Tế: Docker Log Rotation

Để ngăn chặn việc log của các container (Loki, Prometheus, Grafana) phình to chiếm dụng toàn bộ dung lượng đĩa cứng sau thời gian dài vận hành, chúng tôi đã tích hợp cơ chế tự động **Docker Log Rotation** trong tệp cấu hình `cloud/monitoring/docker-compose.yml`:

```yaml
    logging:
      driver: "json-file"
      options:
        max-size: "50m" # Giới hạn mỗi file log dưới 50MB
        max-file: "3"   # Chỉ lưu trữ tối đa 3 file lịch sử (tổng cộng tối đa 150MB mỗi container)
```

---

## 🚀 Cách Thức Áp Dụng Và Khởi Chạy

### Bước 1: Áp dụng cấu hình
Khởi chạy câu lệnh sau tại thư mục giám sát của Cloud Gateway:

```bash
cd cloud/monitoring
sudo -E docker compose --env-file ../../.env up -d --force-recreate
```

### Bước 2: Truy cập giao diện Grafana Web UI
Nếu đang kết nối trong mạng ảo WireGuard overlay, truy cập trực tiếp tại: `http://10.8.0.1:3000`  
Hoặc thiết lập SSH tunnel từ máy tính local của bạn:
```bash
ssh -i <your-key.pem> -N -L 3000:10.8.0.1:3000 ec2-user@<EC2_PUBLIC_IP>
```
Mở trình duyệt và truy cập: `http://127.0.0.1:3000`.

---

## 🛠️ Giải Thích Các Biến Động (Dynamic Variables)
Ở phía trên cùng của giao diện dashboard, bạn có thể tương tác với hai bộ lọc:
*   **`Job`**: Nhóm các công việc thu thập log (mặc định chọn `edge-journal`).
*   **`Node / Host`**: Tự động liệt kê động danh sách tất cả các Cloud và Edge hosts đang đẩy log về hệ thống. Nếu chọn "All", dashboard sẽ gộp chung số liệu; hoặc bạn có thể lọc chi tiết cho riêng một thiết bị cụ thể.
