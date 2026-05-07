# Benchmark Guide

This document explains how to run the benchmark suite in `benchmark/` to validate connectivity, measure bandwidth, verify service health, and stress-test the full `wireguard-edge-cloud-5g` stack.

For the general deployment workflow see [DEPLOYMENT.md](./DEPLOYMENT.md).  
For the quick command reference see [COMMANDS.md](./COMMANDS.md).

---

## Overview

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

## Prerequisites

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

## Configuration

All tuneable parameters live in [`benchmark/config.sh`](../benchmark/config.sh). Override any value via environment variable before running a script — no file edits needed.

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
| `MIN_UDP_MBPS` | `2` | 02-B minimum UDP throughput |
| `MIN_RSYNC_MBPS` | `2` | 02-C minimum rsync throughput |
| `MIN_SUSTAINED_MBPS` | `3` | 04-A minimum sustained throughput |
| `MAX_VARIANCE_PCT` | `40` | 04-A max throughput stddev as % of mean |
| `MAX_P95_MS` | `3000` | 04-B monitoring API p95 response time |
| `MAX_RECONNECT_S` | `30` | 04-C WWAN reconnect time |
| `MAX_WG_RECOVERY_S` | `60` | 04-C WireGuard tunnel recovery time |

---

## Running the benchmark suite

### Run all suites (non-destructive)

```bash
cd /path/to/wireguard-edge-cloud-5g
./benchmark/run_all.sh
```

### Run specific suites

```bash
# Connectivity only
./benchmark/run_all.sh --suite 01

# Connectivity + bandwidth
./benchmark/run_all.sh --suite 01,02

# Services only
./benchmark/run_all.sh --suite 03
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
IPERF3_DURATION=30 IPERF3_PARALLEL=8 ./benchmark/run_all.sh 02

# Lower latency threshold for high-quality 5G
MAX_RTT_MS=80 ./benchmark/run_all.sh 01

# Use .env values for service URLs and passwords
set -a && . .env && set +a
./benchmark/run_all.sh 03
```

### Enable destructive tests (WWAN reconnect and failover)

These tests briefly drop the WWAN interface or remove the WireGuard peer to measure recovery time. They require root.

```bash
sudo ./benchmark/run_all.sh --allow-destructive

# Or a single test
sudo bash benchmark/04-load/test_wwan_reconnect.sh
sudo bash benchmark/05-e2e/test_failover.sh
```

### Verbose mode (show full script output)

```bash
./benchmark/run_all.sh --verbose
```

---

## Suite-by-suite details

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
set -a && . .env && set +a
cd cloud/monitoring && sudo -E docker compose up -d
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

## Reading results

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

## Troubleshooting

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
sudo ./benchmark/run_all.sh --allow-destructive
```

---

## Integrating into CI

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
