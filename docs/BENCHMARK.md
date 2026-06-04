# Benchmark Guide | Hướng Dẫn Đo Hiệu Năng (Benchmark)

🇬🇧 [English](#-english) | 🇻🇳 [Tiếng Việt](#-tiếng-việt)

---

## 🇬🇧 English

This document explains how to run the benchmark suite in `benchmark/` to validate connectivity, measure bandwidth, verify service health, and stress-test the full `wireguard-edge-cloud-5g` stack.

For the general deployment workflow see [DEPLOYMENT.md](./DEPLOYMENT.md).  
For the quick command reference see [COMMANDS.md](./COMMANDS.md).

---

## 🚀 Overview

The suite is organised into five numbered suites that can be run individually or all at once:

| Suite | Directory | What it tests |
|-------|-----------|---------------|
| **01** | `01-connectivity/` | ICMP latency, WireGuard tunnel health, 5G signal quality |
| **02** | `02-bandwidth/` | TCP/UDP throughput (iperf3), rsync file transfer, WireGuard encryption overhead |
| **03** | `03-services/` | Prometheus, Loki, Grafana, Node Exporter health and API response times |
| **04** | `04-load/` | Sustained 60-second bandwidth, concurrent monitoring requests, WWAN reconnect recovery |
| **05** | `05-e2e/` | Seven-phase full-stack validation, failover and recovery scenario |

All output is written to `benchmark/reports/` (git-ignored). Each run appends a timestamped `.txt`, `.csv`, or `.json` file so you can compare runs over time.

---

## 📋 Prerequisites

### Required tools (edge node)

```bash
# Connectivity and bandwidth
ping                 # usually pre-installed
iperf3               # sudo apt install iperf3  /  sudo dnf install iperf3
rsync                # sudo apt install rsync
wg                   # sudo apt install wireguard-tools

# Service tests
curl
python3              # for JSON parsing inside scripts

# 5G signal (optional — skipped gracefully if absent)
qmicli               # sudo apt install libqmi-utils
```

### Required: iperf3 server on the cloud gateway

Suites 02 and 04 require an `iperf3` server running on the cloud EC2 instance. The Terraform Security Group already opens TCP/UDP port 5201.

```bash
# On the cloud gateway — start once, runs in background
iperf3 -s -D
```

---

## ⚙️ Configuration

All tuneable parameters live in [`benchmark/config.sh`](../benchmark/config.sh). Override any value via environment variable before running a script — no file edits needed. For repeatable runs, copy [`.env.benchmark.example`](../.env.benchmark.example) to `.env.benchmark`; benchmark scripts auto-load it when present.

### Key variables

| Variable | Default | Description |
|----------|---------|-------------|
| `WG_SERVER_IP` | `10.8.0.1` | WireGuard overlay IP of the cloud gateway |
| `WG_CLIENT_IP` | `10.8.0.2` | This edge node's WireGuard overlay IP |
| `WG_INTERFACE` | `wg0` | WireGuard interface name |
| `CLOUD_PUBLIC_IP` | _(empty)_ | EC2 public IP — required only for overhead comparison (02-D) |
| `IPERF3_SERVER` | `10.8.0.1` | iperf3 server host (defaults to WireGuard overlay) |
| `IPERF3_PORT` | `5201` | iperf3 server port |
| `IPERF3_DURATION` | `10` | Seconds per iperf3 run |
| `IPERF3_PARALLEL` | `4` | Parallel TCP streams |
| `TCP_WINDOW_SIZE` | `512K` | Optional TCP socket buffer for the tuned-window iperf3 test |
| `SUSTAINED_DURATION` | `60` | Seconds for sustained load test (04-A) |
| `PING_COUNT` | `20` | ICMP packets per ping test |
| `HTTP_TIMEOUT` | `10` | curl timeout in seconds |
| `PROMETHEUS_URL` | `http://10.8.0.1:9090` | Prometheus base URL |
| `LOKI_URL` | `http://10.8.0.1:3100` | Loki base URL |
| `GRAFANA_URL` | `http://10.8.0.1:3000` | Grafana base URL |
| `GRAFANA_ADMIN_PASSWORD` | `admin` | Grafana admin password |
| `SSH_USER` | `ec2-user` | SSH user for rsync tests (02-C) |
| `SSH_KEY` | `~/.ssh/id_rsa` | Path to SSH private key for rsync tests |

### Acceptance thresholds

| Variable | Default | Used in |
|----------|---------|---------|
| `MAX_RTT_MS` | `150` | 01-A ping latency |
| `MAX_LOSS_PCT` | `5` | 01-A, 02-B packet loss |
| `MAX_JITTER_MS` | `30` | 01-A, 02-B UDP jitter |
| `MAX_HANDSHAKE_AGE` | `180` | 01-B WireGuard handshake age (s) |
| `MIN_TCP_MBPS` | `5` | 02-A minimum TCP throughput |
| `MIN_UDP_MBPS` | `2` | 02-B minimum UDP throughput for normal-rate tests |
| `UDP_LOW_RATE_MIN_RATIO` | `0.90` | 02-B minimum pass ratio for UDP targets below `MIN_UDP_MBPS`, such as 1 Mbps and VoIP 64 kbps |
| `MIN_RSYNC_MBPS` | `2` | 02-C minimum rsync throughput |
| `MIN_SUSTAINED_MBPS` | `3` | 04-A minimum sustained throughput |
| `MAX_VARIANCE_PCT` | `40` | 04-A max throughput stddev as % of mean |
| `MAX_P95_MS` | `3000` | 04-B monitoring API p95 response time |
| `MAX_RECONNECT_S` | `30` | 04-C WWAN reconnect time |
| `MAX_WG_RECOVERY_S` | `60` | 04-C WireGuard tunnel recovery time |

---

## 🏃 Running the Benchmark Suite

### Run all suites (non-destructive)

```bash
cd /path/to/wireguard-edge-cloud-5g
bash benchmark/run_all.sh
```

### Run specific suites

```bash
# Connectivity only
bash benchmark/run_all.sh --suite 01

# Connectivity + bandwidth
bash benchmark/run_all.sh --suite 01,02

# Services only
bash benchmark/run_all.sh --suite 03
```

### Run a single script directly

```bash
bash benchmark/01-connectivity/test_ping_latency.sh
bash benchmark/02-bandwidth/test_iperf3_tcp.sh
bash benchmark/03-services/test_prometheus.sh
```

### Override parameters inline

```bash
# Longer iperf3 runs and custom server
IPERF3_DURATION=30 IPERF3_PARALLEL=8 bash benchmark/run_all.sh 02

# Lower latency threshold for high-quality 5G
MAX_RTT_MS=80 bash benchmark/run_all.sh 01

# Use auto-loaded .env.benchmark values for service URLs and passwords
bash benchmark/run_all.sh 03
```

### Enable destructive tests (WWAN reconnect and failover)

These tests briefly drop the WWAN interface or remove the WireGuard peer to measure recovery time. They require root.

```bash
sudo -E bash benchmark/run_all.sh --allow-destructive

# Or a single test
sudo bash benchmark/04-load/test_wwan_reconnect.sh
sudo bash benchmark/05-e2e/test_failover.sh
```

### Verbose mode (show full script output)

```bash
bash benchmark/run_all.sh --verbose
```

---

## 🔍 Suite-by-suite Details

### Suite 01 — Connectivity

| Script | What it measures |
|--------|-----------------|
| `test_ping_latency.sh` | RTT min/avg/max/jitter and packet loss to the WireGuard gateway and to 8.8.8.8. Also tests MTU fragmentation at 1300 B. |
| `test_wg_tunnel.sh` | Interface existence, peer count, latest handshake age, TX/RX byte counters, allowed-IPs, overlay reachability. |
| `test_5g_signal.sh` | WWAN IP assignment, QMI network registration state, RSRP/RSRQ/SNR, data session byte counters, DNS resolution. |

**Typical healthy output on 5G NR Sub-6:**
- RTT to cloud gateway: 30–80 ms
- Packet loss: 0–1 %
- RSRP: −80 to −95 dBm
- Handshake age: < 30 s (PersistentKeepalive = 25 s)

---

### Suite 02 — Bandwidth

| Script | What it measures |
|--------|-----------------|
| `test_iperf3_tcp.sh` | TCP uplink, downlink, single stream, 512 K window, bidirectional. Reports Mbps and retransmit count. |
| `test_iperf3_udp.sh` | UDP at 1/5/10/20/50 Mbps targets plus VoIP simulation (64 kbps, 160 B packets) and large-MTU (1300 B). Reports jitter and loss %. |
| `test_rsync_transfer.sh` | Transfers 1/10/50 MiB files and a 50 × 100 KB multi-file dataset over the WireGuard overlay. Measures effective application throughput in Mbps. |
| `test_wg_overhead.sh` | Compares throughput to the EC2 public IP (raw 5G) vs the overlay IP (WireGuard). Reports overhead %. Requires `CLOUD_PUBLIC_IP`. |

**Typical throughput on a 5G-connected Orange Pi 5 Max:**
- TCP uplink: 20–60 Mbps
- TCP downlink: 30–80 Mbps
- UDP jitter at 10 Mbps: 2–8 ms
- WireGuard overhead: 2–5 % (ChaCha20-Poly1305 with ARMv8 NEON)

**Run the overhead test:**
```bash
CLOUD_PUBLIC_IP=<ec2-public-ip> bash benchmark/02-bandwidth/test_wg_overhead.sh
```

---

### Suite 03 — Services

| Script | What it checks |
|--------|---------------|
| `test_prometheus.sh` | `/−/healthy`, `/−/ready`, query API latency, scrape target health, key metric presence, TSDB series count. |
| `test_loki.sh` | `/ready`, push a test log entry, query it back, ingestion rate via LogQL. |
| `test_grafana.sh` | `/api/health`, data source connection test, dashboard count, API latency. |
| `test_node_exporter.sh` | CPU, memory, disk, network metrics from both cloud gateway (`10.8.0.1:9100`) and edge node (`127.0.0.1:9100`). Verifies the WireGuard interface appears in network metrics. |

**Prerequisite:** monitoring stack must be running.

```bash
set -a && . ./.env.cloud && set +a
cd cloud/monitoring && sudo -E docker compose --env-file ../../.env.cloud up -d
```

---

### Suite 04 — Load

| Script | What it measures |
|--------|-----------------|
| `test_sustained_bandwidth.sh` | Runs iperf3 for `SUSTAINED_DURATION` (default 60 s) with per-5-second interval reporting. Computes mean, min, max, stddev, and variance %. Saves per-interval CSV. |
| `test_monitoring_load.sh` | Fires `CONCURRENCY` (default 10) parallel HTTP requests to Prometheus, Loki, Grafana, and Node Exporter. Reports p50/p95/p99 and failure rate. Saves CSV with per-request latencies. |
| `test_wwan_reconnect.sh` | Runs `TRIALS` (default 3) reconnect cycles: takes `WWAN_INTERFACE` down, brings it back up, measures time to re-acquire IP and time for the WireGuard overlay to recover. **Requires root. Briefly disrupts network.** |

**Interpret sustained bandwidth results:**
- Variance < 20 %: stable link
- Variance 20–40 %: acceptable, typical 5G variation
- Variance > 40 %: unstable — check signal quality (Suite 01-C) and interference

---

### Suite 05 — End-to-End

| Script | What it tests |
|--------|--------------|
| `test_full_stack.sh` | Seven sequential phases: 5G WWAN IP → WireGuard overlay ping → handshake freshness → all service health checks → Prometheus edge scrape target → Loki edge-journal stream → quick iperf3 bandwidth baseline → SSH over overlay. |
| `test_failover.sh` | Records a Prometheus baseline, removes the WireGuard peer (simulating a tunnel drop), waits `DISRUPTION_S` (default 15 s), restores the peer, measures overlay recovery time, checks that Prometheus series count is restored, and verifies Loki resumes ingestion. **Requires root.** |

Run the full-stack test as a smoke test after initial deployment:

```bash
bash benchmark/05-e2e/test_full_stack.sh
```

---

## 📊 Reading Results

### Console output

Each line is prefixed with a status symbol:

```
  ✔ PASS  WG-overlay → cloud-gateway: RTT=42ms loss=0% jitter=3ms
  ✘ FAIL  Prometheus health check failed at http://10.8.0.1:9090/-/healthy
  ⚠ WARN  RSRP=-105dBm is below threshold -110dBm — weak signal
  ℹ INFO  Current log ingestion rate: 2.341 entries/s
```

The master runner prints a global summary at the end:

```
  PASS: 38  |  FAIL: 2  |  WARN: 5
```

### Report files

```
benchmark/reports/
├── run_all_20260507_143021.log       # master per-suite summary
├── 01-ping-latency_143022.txt        # per-test detail
├── iperf3_tcp_20260507_143045.txt    # iperf3 JSON output
├── sustained_20260507_143200.csv     # per-interval throughput data
└── monitoring_load_20260507_143310.csv  # per-request latencies
```

Import the CSV files into a spreadsheet or Grafana to visualise throughput trends across test runs.

---

## 🛠 Troubleshooting

### iperf3 tests fail — "server unreachable"

```bash
# On cloud gateway: start server
iperf3 -s -D
# Verify the port is open
ss -lnp | grep 5201
# From edge: quick check
iperf3 -c 10.8.0.1 -p 5201 -t 3
```

### rsync tests fail — SSH refused

```bash
# Verify SSH key path
ls -la ~/.ssh/id_rsa
# Test SSH manually
ssh -i ~/.ssh/id_rsa -o ConnectTimeout=5 ec2-user@10.8.0.1 echo ok
# Set the correct key path
SSH_KEY=~/.ssh/my-key.pem bash benchmark/02-bandwidth/test_rsync_transfer.sh
```

### Service tests fail — connection refused

The monitoring stack binds to `MONITORING_BIND_ADDRESS` (default `127.0.0.1`). To reach it from the edge over WireGuard:

```bash
# On cloud gateway
export MONITORING_BIND_ADDRESS=10.8.0.1
export ALLOW_MONITORING_OVER_WIREGUARD=true
cd cloud/monitoring && sudo -E docker compose up -d
```

### 5G signal test skipped — QMI device not found

```bash
# Check if modem is visible
ls /dev/cdc-wdm*
# Verify QMI device manually
sudo qmicli -d /dev/cdc-wdm0 --nas-get-serving-system
# Set device explicitly
QMI_DEVICE=/dev/cdc-wdm0 bash benchmark/01-connectivity/test_5g_signal.sh
```

### Destructive tests fail — permission denied

```bash
sudo bash benchmark/04-load/test_wwan_reconnect.sh
sudo bash benchmark/05-e2e/test_failover.sh
# Or via run_all.sh
sudo -E bash benchmark/run_all.sh --allow-destructive
```

---

## 🔄 Integrating into CI

Add a non-destructive smoke-test step to any pipeline that has access to the WireGuard overlay:

```yaml
# Example: GitHub Actions job running on a self-hosted runner on the edge node
- name: Run benchmark smoke test
  env:
    WG_SERVER_IP: "10.8.0.1"
    GRAFANA_ADMIN_PASSWORD: ${{ secrets.GRAFANA_ADMIN_PASSWORD }}
  run: |
    set -e
    bash benchmark/01-connectivity/test_wg_tunnel.sh
    bash benchmark/03-services/test_prometheus.sh
    bash benchmark/05-e2e/test_full_stack.sh
```

---

## 🇻🇳 Tiếng Việt

Tài liệu này hướng dẫn cách chạy bộ công cụ đo hiệu năng (benchmark suite) trong thư mục `benchmark/` để xác nhận trạng thái kết nối, đo băng thông, kiểm tra sức khỏe dịch vụ và ép tải (stress-test) toàn bộ hệ thống `wireguard-edge-cloud-5g`.

Để biết quy trình triển khai chung, xem [DEPLOYMENT.md](./DEPLOYMENT.md).  
Để tra cứu nhanh các lệnh thông dụng, xem [COMMANDS.md](./COMMANDS.md).

---

## 🚀 Tổng Quan

Bộ công cụ được tổ chức thành 5 bộ kiểm thử (suites) được đánh số, có thể chạy riêng lẻ hoặc chạy đồng thời:

| Bộ kiểm thử | Thư mục | Nội dung kiểm thử |
|---|---|---|
| **01** | `01-connectivity/` | Độ trễ ICMP, sức khoẻ đường hầm WireGuard, chất lượng tín hiệu 5G |
| **02** | `02-bandwidth/` | Băng thông TCP/UDP (iperf3), truyền file qua rsync, hao hụt mã hoá WireGuard |
| **03** | `03-services/` | Sức khỏe của Prometheus, Loki, Grafana, Node Exporter và thời gian phản hồi API |
| **04** | `04-load/` | Đo băng thông liên tục trong 60 giây, tải yêu cầu giám sát đồng thời, khả năng khôi phục kết nối WWAN |
| **05** | `05-e2e/` | Xác thực toàn bộ stack qua 7 pha kiểm thử, kịch bản chuyển đổi dự phòng (failover) và khôi phục |

Tất cả kết quả đầu ra được ghi vào thư mục `benchmark/reports/` (đã được cấu hình git-ignore). Mỗi lượt chạy sẽ ghi thêm một file kèm mốc thời gian dưới dạng `.txt`, `.csv` hoặc `.json` để bạn có thể so sánh hiệu năng theo thời gian.

---

## 📋 Điều Kiện Tiên Quyết

### Các công cụ cần thiết (trên Edge Node)

```bash
# Kết nối và băng thông
ping                 # thường đã được cài sẵn
iperf3               # cài bằng: sudo apt install iperf3  hoặc  sudo dnf install iperf3
rsync                # cài bằng: sudo apt install rsync
wg                   # cài bằng: sudo apt install wireguard-tools

# Kiểm tra dịch vụ
curl
python3              # dùng để phân tích cú pháp JSON trong các script

# Tín hiệu 5G (tùy chọn — tự động bỏ qua nếu không có)
qmicli               # cài bằng: sudo apt install libqmi-utils
```

### Yêu cầu: iperf3 server trên Cloud Gateway

Bộ kiểm thử số 02 và 04 yêu cầu một `iperf3` server chạy trên máy ảo cloud EC2. Nhóm bảo mật (Security Group) của Terraform đã mở sẵn cổng TCP/UDP `5201`.

```bash
# Trên Cloud Gateway — khởi chạy một lần để chạy ẩn dưới nền (background)
iperf3 -s -D
```

---

## ⚙️ Cấu Hình

Tất cả các tham số có thể tinh chỉnh đều nằm trong file [`benchmark/config.sh`](../benchmark/config.sh). Bạn có thể ghi đè bất kỳ giá trị nào thông qua biến môi trường trước khi chạy script mà không cần sửa file trực tiếp. Với các lần chạy lặp lại, copy [`.env.benchmark.example`](../.env.benchmark.example) thành `.env.benchmark`; các script benchmark sẽ tự nạp file này khi tồn tại.

### Các biến chính

| Biến | Mặc định | Mô tả |
|---|---|---|
| `WG_SERVER_IP` | `10.8.0.1` | IP mạng ảo WireGuard của Cloud Gateway |
| `WG_CLIENT_IP` | `10.8.0.2` | IP mạng ảo WireGuard của Edge Node này |
| `WG_INTERFACE` | `wg0` | Tên giao diện mạng WireGuard |
| `CLOUD_PUBLIC_IP` | _(trống)_ | IP Public của EC2 — chỉ cần thiết cho kiểm thử so sánh hao hụt mã hoá (02-D) |
| `IPERF3_SERVER` | `10.8.0.1` | Địa chỉ máy chủ iperf3 (mặc định trỏ về mạng ảo WireGuard) |
| `IPERF3_PORT` | `5201` | Cổng dịch vụ iperf3 |
| `IPERF3_DURATION` | `10` | Thời gian chạy iperf3 tính bằng giây |
| `IPERF3_PARALLEL` | `4` | Số lượng luồng TCP chạy song song |
| `TCP_WINDOW_SIZE` | `512K` | Kích thước socket buffer tùy chọn cho bài test TCP tuned-window |
| `SUSTAINED_DURATION` | `60` | Thời gian chạy kiểm thử tải liên tục (04-A) tính bằng giây |
| `PING_COUNT` | `20` | Số lượng gói tin ICMP cho mỗi lần test ping |
| `HTTP_TIMEOUT` | `10` | Thời gian chờ tối đa của curl tính bằng giây |
| `PROMETHEUS_URL` | `http://10.8.0.1:9090` | URL cơ sở của Prometheus |
| `LOKI_URL` | `http://10.8.0.1:3100` | URL cơ sở của Loki |
| `GRAFANA_URL` | `http://10.8.0.1:3000` | URL cơ sở của Grafana |
| `GRAFANA_ADMIN_PASSWORD` | `admin` | Mật khẩu quản trị của Grafana |
| `SSH_USER` | `ec2-user` | Tài khoản SSH dùng cho các kiểm thử rsync (02-C) |
| `SSH_KEY` | `~/.ssh/id_rsa` | Đường dẫn tới khóa riêng tư SSH cho các kiểm thử rsync |

### Ngưỡng chấp nhận

| Biến | Mặc định | Sử dụng trong |
|---|---|---|
| `MAX_RTT_MS` | `150` | 01-A Độ trễ ping |
| `MAX_LOSS_PCT` | `5` | 01-A, 02-B Tỷ lệ mất gói tin |
| `MAX_JITTER_MS` | `30` | 01-A, 02-B Độ trễ biến động (jitter) của UDP |
| `MAX_HANDSHAKE_AGE` | `180` | 01-B Thời gian bắt tay (handshake) lớn nhất của WireGuard (giây) |
| `MIN_TCP_MBPS` | `5` | 02-A Băng thông TCP tối thiểu |
| `MIN_UDP_MBPS` | `2` | 02-B Băng thông UDP tối thiểu cho các bài test tốc độ thông thường |
| `UDP_LOW_RATE_MIN_RATIO` | `0.90` | 02-B Tỷ lệ pass tối thiểu cho các target UDP thấp hơn `MIN_UDP_MBPS`, ví dụ 1 Mbps và VoIP 64 kbps |
| `MIN_RSYNC_MBPS` | `2` | 02-C Băng thông truyền file rsync tối thiểu |
| `MIN_SUSTAINED_MBPS` | `3` | 04-A Băng thông tối thiểu khi tải liên tục |
| `MAX_VARIANCE_PCT` | `40` | 04-A Độ lệch chuẩn băng thông tối đa (tính theo % của giá trị trung bình) |
| `MAX_P95_MS` | `3000` | 04-B Thời gian phản hồi phân vị 95 (p95) của API giám sát |
| `MAX_RECONNECT_S` | `30` | 04-C Thời gian khôi phục kết nối mạng di động WWAN |
| `MAX_WG_RECOVERY_S` | `60` | 04-C Thời gian khôi phục đường hầm WireGuard |

---

## 🏃 Chạy Bộ Kiểm Thử

### Chạy toàn bộ các suite (Không gây gián đoạn mạng)

```bash
cd /path/to/wireguard-edge-cloud-5g
bash benchmark/run_all.sh
```

### Chạy các suite cụ thể

```bash
# Chỉ chạy kiểm thử kết nối
bash benchmark/run_all.sh --suite 01

# Chạy kết nối và đo băng thông
bash benchmark/run_all.sh --suite 01,02

# Chỉ chạy kiểm thử dịch vụ giám sát
bash benchmark/run_all.sh --suite 03
```

### Chạy trực tiếp một script đơn lẻ

```bash
bash benchmark/01-connectivity/test_ping_latency.sh
bash benchmark/02-bandwidth/test_iperf3_tcp.sh
bash benchmark/03-services/test_prometheus.sh
```

### Ghi đè trực tiếp các tham số cấu hình trên dòng lệnh

```bash
# Chạy iperf3 lâu hơn và cấu hình số luồng song song lớn hơn
IPERF3_DURATION=30 IPERF3_PARALLEL=8 bash benchmark/run_all.sh 02

# Hạ ngưỡng chấp nhận độ trễ áp dụng cho mạng 5G chất lượng cao
MAX_RTT_MS=80 bash benchmark/run_all.sh 01

# Sử dụng biến auto-loaded từ .env.benchmark cho URL dịch vụ và mật khẩu
bash benchmark/run_all.sh 03
```

### Cho phép các kiểm thử có tính phá hủy (WWAN reconnect và failover)

Các bài kiểm thử này sẽ tạm thời ngắt kết nối mạng di động WWAN hoặc xóa peer WireGuard để đo lường thời gian tự phục hồi của hệ thống. **Yêu cầu quyền root.**

```bash
sudo -E bash benchmark/run_all.sh --allow-destructive

# Hoặc chỉ chạy một bài test đơn lẻ
sudo bash benchmark/04-load/test_wwan_reconnect.sh
sudo bash benchmark/05-e2e/test_failover.sh
```

### Chế độ hiển thị chi tiết (Verbose)

```bash
bash benchmark/run_all.sh --verbose
```

---

## 🔍 Chi Tiết Từng Bộ Kiểm Thử

### Suite 01 — Kết Nối

| Script | Chỉ số đo lường |
|---|---|
| `test_ping_latency.sh` | RTT min/avg/max/jitter và tỷ lệ mất gói tin tới WireGuard gateway và 8.8.8.8. Đồng thời kiểm tra phân mảnh MTU ở mức 1300 B. |
| `test_wg_tunnel.sh` | Kiểm tra sự tồn tại của interface, số lượng peer kết nối, thời gian của handshake gần nhất, bộ đếm byte TX/RX, allowed-IPs, khả năng thông mạng ảo overlay. |
| `test_5g_signal.sh` | Kiểm tra việc gán IP WWAN, trạng thái đăng ký mạng qua QMI, các chỉ số RSRP/RSRQ/SNR, bộ đếm byte của phiên dữ liệu và phân giải DNS. |

**Đầu ra chuẩn của một hệ thống chạy tốt trên sóng 5G NR Sub-6:**
- Độ trễ RTT tới cloud gateway: 30–80 ms
- Tỷ lệ mất gói: 0–1 %
- RSRP: −80 đến −95 dBm
- Thời gian handshake gần nhất: < 30 giây (nhờ cơ chế PersistentKeepalive = 25 giây)

---

### Suite 02 — Băng Thông

| Script | Chỉ số đo lường |
|---|---|
| `test_iperf3_tcp.sh` | Đo băng thông TCP tải lên (uplink), tải xuống (downlink), luồng đơn, cửa sổ truyền 512 K, chạy hai chiều (bidirectional). Báo cáo Mbps và số lần truyền lại (retransmit count). |
| `test_iperf3_udp.sh` | Đo băng thông UDP với các mức tiêu chuẩn 1/5/10/20/50 Mbps kèm giả lập cuộc gọi VoIP (64 kbps, gói tin 160 B) và gói tin lớn (MTU 1300 B). Báo cáo độ trễ biến động (jitter) và tỷ lệ mất gói. |
| `test_rsync_transfer.sh` | Thực hiện truyền các file dung lượng 1/10/50 MiB và bộ dữ liệu chứa nhiều file nhỏ (50 file × 100 KB) thông qua mạng ảo WireGuard. Đo băng thông hiệu dụng thực tế của ứng dụng (Mbps). |
| `test_wg_overhead.sh` | So sánh băng thông thực tế khi đi qua IP Public của EC2 (mạng 5G gốc) so với đi qua IP mạng ảo WireGuard. Báo cáo tỷ lệ hao hụt hiệu năng (%). Yêu cầu biến `CLOUD_PUBLIC_IP`. |

**Hiệu năng thực tế trung bình trên thiết bị Orange Pi 5 Max kết nối 5G:**
- TCP uplink: 20–60 Mbps
- TCP downlink: 30–80 Mbps
- UDP jitter ở mức tải 10 Mbps: 2–8 ms
- Hao hụt mã hóa của WireGuard: 2–5 % (ChaCha20-Poly1305 được tối ưu hóa bằng tập lệnh ARMv8 NEON)

**Cách chạy kiểm thử hao hụt hiệu năng:**
```bash
CLOUD_PUBLIC_IP=<ec2-public-ip> bash benchmark/02-bandwidth/test_wg_overhead.sh
```

---

### Suite 03 — Dịch Vụ

| Script | Nội dung kiểm tra |
|---|---|
| `test_prometheus.sh` | Trạng thái sức khỏe `/—/healthy`, độ sẵn sàng `/—/ready`, độ trễ truy vấn API, sức khỏe của các mục tiêu thu thập dữ liệu (scrape target), sự hiện diện của các metric cốt lõi, và số lượng series trong TSDB. |
| `test_loki.sh` | Trạng thái `/ready`, thực hiện ghi log thử nghiệm, truy vấn lại log đó, đo tốc độ ghi log qua LogQL. |
| `test_grafana.sh` | Trạng thái `/api/health`, kết nối tới các nguồn dữ liệu (data source), đếm số lượng dashboard và độ trễ phản hồi API. |
| `test_node_exporter.sh` | Thu thập metrics CPU, RAM, disk và mạng từ cả Cloud Gateway (`10.8.0.1:9100`) và Edge Node (`127.0.0.1:9100`). Xác nhận interface WireGuard hiển thị đầy đủ trong metrics. |

**Điều kiện tiên quyết:** Cụm giám sát (monitoring stack) phải đang chạy.

```bash
set -a && . ./.env.cloud && set +a
cd cloud/monitoring && sudo -E docker compose --env-file ../../.env.cloud up -d
```

---

## Suite 04 — Ép Tải

| Script | Chỉ số đo lường |
|---|---|
| `test_sustained_bandwidth.sh` | Khởi chạy iperf3 liên tục trong khoảng thời gian `SUSTAINED_DURATION` (mặc định 60 giây) và báo cáo chỉ số mỗi 5 giây. Tính toán giá trị trung bình, tối thiểu, tối đa, độ lệch chuẩn (stddev) và độ biến động %. Lưu báo cáo chi tiết theo từng khoảng thời gian dưới dạng file CSV. |
| `test_monitoring_load.sh` | Thực hiện gửi đồng thời `CONCURRENCY` (mặc định 10) yêu cầu HTTP song song tới Prometheus, Loki, Grafana và Node Exporter. Báo cáo các chỉ số phân vị p50/p95/p99 và tỷ lệ lỗi. Xuất báo cáo CSV chứa độ trễ của từng yêu cầu. |
| `test_wwan_reconnect.sh` | Thực hiện `TRIALS` (mặc định 3) chu kỳ ngắt và kết nối lại mạng di động: tắt interface `WWAN_INTERFACE`, bật lại, đo thời gian nhận lại IP và thời gian đường hầm WireGuard khôi phục hoàn toàn kết nối. **Yêu cầu quyền root và sẽ gây gián đoạn mạng tạm thời.** |

**Cách đọc kết quả đo tải băng thông liên tục:**
- Độ biến động (Variance) < 20%: Kết nối cực kỳ ổn định.
- Độ biến động (Variance) 20–40%: Chấp nhận được, đây là mức dao động bình thường của sóng mạng 5G.
- Độ biến động (Variance) > 40%: Kết nối không ổn định — cần kiểm tra lại chất lượng tín hiệu sóng (Suite 01-C) hoặc tình trạng nhiễu sóng.

---

### Suite 05 — Kiểm Thử Tích Hợp Đầu Cuối (End-to-End)

| Script | Nội dung kiểm thử |
|---|---|
| `test_full_stack.sh` | Chạy tuần tự 7 pha xác thực hệ thống: Nhận IP 5G WWAN → Ping thông mạng ảo WireGuard → Kiểm tra handshake mới nhất → Trạng thái của toàn bộ dịch vụ giám sát → Thu thập metrics Edge qua Prometheus → Luồng log Edge đẩy về Loki qua Alloy → Đo băng thông iperf3 cơ sở → Thử nghiệm kết nối SSH qua mạng ảo overlay. |
| `test_failover.sh` | Ghi lại mốc metrics cơ sở trên Prometheus, tiến hành xóa peer WireGuard (giả lập mất kết nối đường hầm), đợi `DISRUPTION_S` (mặc định 15 giây), khôi phục lại cấu hình peer, đo thời gian khôi phục của mạng ảo overlay, kiểm tra số lượng metrics series trên Prometheus được phục hồi hoàn toàn và xác nhận Loki tiếp tục nhận log bình thường. **Yêu cầu quyền root.** |

Chạy bài test tích hợp này như một bước kiểm tra nhanh (smoke test) sau khi hoàn tất triển khai ban đầu:

```bash
bash benchmark/05-e2e/test_full_stack.sh
```

---

## 📊 Đọc Và Hiểu Kết Quả

### Output hiển thị trên Terminal

Mỗi dòng thông tin sẽ đi kèm một ký hiệu thể hiện trạng thái:

```
  ✔ PASS  WG-overlay → cloud-gateway: RTT=42ms loss=0% jitter=3ms
  ✘ FAIL  Prometheus health check failed at http://10.8.0.1:9090/-/healthy
  ⚠ WARN  RSRP=-105dBm is below threshold -110dBm — weak signal
  ℹ INFO  Current log ingestion rate: 2.341 entries/s
```

Trình chạy tổng hợp (master runner) sẽ in một bảng tổng kết kết quả kiểm thử ở cuối phiên:

```
  PASS: 38  |  FAIL: 2  |  WARN: 5
```

### Các tệp tin báo cáo được tạo ra

```
benchmark/reports/
├── run_all_20260507_143021.log       # Tóm tắt kết quả theo từng bộ kiểm thử
├── 01-ping-latency_143022.txt        # Chi tiết kết quả của từng lượt kiểm thử cụ thể
├── iperf3_tcp_20260507_143045.txt    # Kết quả thô dạng JSON của công cụ iperf3
├── sustained_20260507_143200.csv     # Chỉ số đo băng thông liên tục theo từng khoảng thời gian
└── monitoring_load_20260507_143310.csv  # Độ trễ chi tiết của từng request tải giám sát
```

Bạn có thể nhập các tệp tin `.csv` này vào các công cụ bảng tính (Excel/Google Sheets) hoặc tích hợp trực tiếp vào Grafana để trực quan hóa xu hướng hiệu năng hệ thống qua các lượt chạy khác nhau.

---

## 🛠 Xử Lý Sự Cố Thường Gặp

### Lỗi kiểm thử iperf3 — báo "server unreachable" (không thể kết nối máy chủ)

```bash
# Trên Cloud Gateway: Khởi chạy lại server iperf3 dưới nền
iperf3 -s -D
# Xác nhận xem cổng dịch vụ đã được lắng nghe chưa
ss -lnp | grep 5201
# Từ thiết bị Edge: Kiểm tra nhanh kết nối tới máy chủ
iperf3 -c 10.8.0.1 -p 5201 -t 3
```

### Lỗi kiểm thử rsync — báo từ chối kết nối SSH (SSH refused)

```bash
# Xác nhận xem tệp khóa riêng SSH có tồn tại và đúng đường dẫn không
ls -la ~/.ssh/id_rsa
# Kiểm tra thủ công xem có kết nối SSH được không
ssh -i ~/.ssh/id_rsa -o ConnectTimeout=5 ec2-user@10.8.0.1 echo ok
# Chỉ định rõ ràng đường dẫn khóa nếu bạn dùng tên khóa khác mặc định
SSH_KEY=~/.ssh/my-key.pem bash benchmark/02-bandwidth/test_rsync_transfer.sh
```

### Lỗi kiểm thử dịch vụ — báo từ chối kết nối (connection refused)

Cụm dịch vụ giám sát mặc định chỉ lắng nghe kết nối cục bộ trên máy chủ `MONITORING_BIND_ADDRESS` (mặc định là `127.0.0.1`). Để cho phép Edge Node truy cập được qua đường hầm WireGuard:

```bash
# Trên Cloud Gateway
export MONITORING_BIND_ADDRESS=10.8.0.1
export ALLOW_MONITORING_OVER_WIREGUARD=true
cd cloud/monitoring && sudo -E docker compose up -d
```

### Bỏ qua kiểm thử tín hiệu 5G — do không tìm thấy thiết bị QMI (QMI device not found)

```bash
# Kiểm tra xem hệ thống có nhận diện được modem không
ls /dev/cdc-wdm*
# Truy vấn thông tin mạng phục vụ thủ công qua qmicli
sudo qmicli -d /dev/cdc-wdm0 --nas-get-serving-system
# Chỉ định rõ cổng cdc-wdm của modem khi chạy test
QMI_DEVICE=/dev/cdc-wdm0 bash benchmark/01-connectivity/test_5g_signal.sh
```

### Lỗi chạy các kiểm thử phá hủy — báo thiếu quyền hạn (permission denied)

```bash
sudo bash benchmark/04-load/test_wwan_reconnect.sh
sudo bash benchmark/05-e2e/test_failover.sh
# Hoặc chạy thông qua run_all.sh
sudo -E bash benchmark/run_all.sh --allow-destructive
```

---

## 🔄 Tích Hợp Vào Quy Trình CI

Bạn có thể thêm một bước kiểm tra nhanh (smoke-test) không gây gián đoạn mạng vào bất kỳ pipeline CI/CD nào có khả năng truy cập được vào mạng ảo WireGuard:

```yaml
# Ví dụ cấu hình cho GitHub Actions chạy trên self-hosted runner nằm tại Edge Node
- name: Run benchmark smoke test
  env:
    WG_SERVER_IP: "10.8.0.1"
    GRAFANA_ADMIN_PASSWORD: ${{ secrets.GRAFANA_ADMIN_PASSWORD }}
  run: |
    set -e
    bash benchmark/01-connectivity/test_wg_tunnel.sh
    bash benchmark/03-services/test_prometheus.sh
    bash benchmark/05-e2e/test_full_stack.sh
```
