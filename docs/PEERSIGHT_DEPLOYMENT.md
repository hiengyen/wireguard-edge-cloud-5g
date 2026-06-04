# PeerSight Reference & Deployment Guide (WireGuard Orchestration) | Hướng Dẫn Triển Khai PeerSight

🇬🇧 [English](#-english) | 🇻🇳 [Tiếng Việt](#-tiếng-việt)

---

## 🇬🇧 English

This document is the unified source of truth for deploying, managing, and operating the **PeerSight** system (WireGuard network monitoring, security orchestration, and SIEM logging) within the distributed Edge-Cloud 5G infrastructure.

---

## 1. Architectural Overview & Modules

PeerSight replaces older Python and Elixir-based monitoring stacks (like Procustodibus) with a modern, lightweight **Golang** backend and a **Vue.js 3** frontend. It is designed to run efficiently on resource-constrained ARM edge nodes (Orange Pi) and central Cloud gateways (AWS EC2).

### 1.1 Architecture Diagram

```
┌──────────────┐       ┌──────────────┐       ┌──────────────┐
│ peersight-app│       │ peersight-api│       │  PostgreSQL  │
│  (Vue.js 3)  │◄─────►│   (Go/Gin)   │◄─────►│   Database   │
│  Port: 5173  │  HTTP │  Port: 4000  │  SQL  │  Port: 5432  │
└──────────────┘       └──────┬───────┘       └──────────────┘
                              │ REST
            ┌─────────────────┼─────────────────┐
            ▼                 ▼                 ▼
   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
   │peersight-agent│  │peersight-agent│  │peersight-broker│
   │  (Go daemon) │  │  (Go daemon) │  │  (Go daemon)  │
   │  Host A      │  │  Host B      │  │  SIEM Bridge  │
   └──────────────┘  └──────────────┘  └───────┬───────┘
         │                  │                   │
    ┌────┴────┐        ┌────┴────┐         ┌───┴────┐
    │WireGuard│        │WireGuard│         │Syslog/ │
    │ Kernel  │        │ Kernel  │         │ File   │
    └─────────┘        └─────────┘         └────────┘
```

### 1.2 Core Modules

| Module | Language | Runtime | Description |
|---|---|---|---|
| `peersight-api` | Go (Gin) | Docker Container | Central REST API — manages DB, authenticates agents, registers hosts, and queues alerts. |
| `peersight-app` | Vue.js 3 | Docker Container | Modern admin dashboard with an **Obsidian-style interactive topology graph**, configuring peers, visualizing host statuses, and managing alerts. |
| `peersight-agent` | Go | Systemd Daemon | Runs on both Cloud and Edge nodes. Periodically polls the API for desired peer configurations and runs kernel sync commands. |
| `peersight-broker` | Go | Docker Container | SIEM Bridge daemon. Polls alert events from the API and pipes them to local logs `/var/log/peersight/events.jsonl` (scraped by Alloy/Loki). |

### 1.3 Project Structure

```text
peersight/
├── docker-compose.yml      # DB, API, UI, and Broker orchestration
├── deploy-cloud.sh         # Complete Go setup, container startup, and cloud agent registration
├── deploy-edge.sh          # Native compilation or binary-transfer orchestration on Edge
├── install-go.sh           # Auto-detecting compiler installer (Go 1.23.0+)
├── install-agent.sh        # Systemd daemon registrar
├── stop-peersight.sh       # Script to halt Docker containers while keeping volumes
├── uninstall.sh            # Safe uninstaller (agent + logs + containers, preserves DB)
├── peersight-api/          # REST API codebase (Gin + pgx + migrations)
├── peersight-agent/        # Agent daemon codebase (WireGuard kernel sync)
├── peersight-broker/       # Broker daemon codebase (SIEM bridge)
└── peersight-app/          # Admin UI codebase (Vue 3 + Nginx)
```

---

## 2. PeerSight Data Flow

1. **Administration**: An operator adds/updates a peer configuration using the **App UI** (`peersight-app`).
2. **Persistence**: The **API** (`peersight-api`) stores this as a pending `DesiredChange` in **PostgreSQL**.
3. **Heartbeat**: The local **Agent** (`peersight-agent`) sends a periodic heartbeat payload to the API (`POST /hosts/:id/ping/:version`).
4. **Configuration Delivery**: The **API** responds with any pending `DesiredChange` instructions.
5. **Kernel Enforcement**: The **Agent** runs system calls (equivalent to `wg set`) to update the host's local WireGuard interface. It then reports the status back to the API.
6. **Alert Processing**: The **API** flags any drift, key mismatches, or down links, and pushes an event into the alert queue.
7. **SIEM Pipe**: The **Broker** (`peersight-broker`) polls the queue, fetches the alerts, and logs them in JSON Lines format (`/var/log/peersight/events.jsonl`).
8. **Observability**: **Grafana Alloy** reads `/var/log/peersight/events.jsonl` and streams them into **Grafana Loki** under the `{job="peersight-alerts"}` tag.

---

## 3. Comparison: Procustodibus vs PeerSight

| Metric / Feature | Procustodibus (Legacy) | PeerSight (Current Architecture) |
|---|---|---|
| **API Backend** | Elixir / Phoenix | **Go / Gin** |
| **Agent / Broker** | Python 3 | **Go (v1.23+)** |
| **Authentication** | Ed25519 Challenge-Signature | **JWT Bearer Token** |
| **Build Artifacts** | Python wheel + Mix release | **Single static binaries** |
| **Docker Image Size** | ~150 MB (Python runtime) | **~15 MB (Alpine)** |
| **Agent Memory Footprint**| ~30–50 MB | **~5–10 MB** (Highly Optimized) |
| **Cross-Compile** | Complex (Python C dependencies) | **`GOOS=linux GOARCH=arm64 go build`** |
| **Admin UI** | Vue 3 (Oruga/Bulma) | **Vue 3 (Custom Sleek Dark Mode & Obsidian-style Interactive Graph View)** |

---

## 4. Automation Scripts Overview

The deployment lifecycle is fully managed by shell scripts in the `peersight/` directory:

| Script | Purpose | Run on |
|---|---|---|
| `deploy-cloud.sh` | Installs Go 1.23, compiles agent, configures systemd agent, and launches the Docker Compose stack | Cloud Gateway |
| `deploy-edge.sh` | Sets up Go (native compile on Edge) or validates binary (cross-compiled transfer mode) and starts systemd agent | Edge Node |
| `install-go.sh` | Portable script to download, verify, and register Go 1.23.0+ from official upstream tarballs | Both |
| `install-agent.sh` | Internal helper called by deploy scripts to set up the systemd unit and register API tokens | Both |
| `stop-peersight.sh`| Halts all PeerSight containers while leaving database volumes intact | Cloud Gateway |
| `uninstall.sh` | Safe uninstaller. Stops agent, removes binaries/logs/configs, and tears down containers (keeps database volumes) | Both |

---

## 5. Prerequisites

Ensure you have completed the base infrastructure setup described in [DEPLOYMENT.md](DEPLOYMENT.md):
- Cloud Gateway is running with VPN address `10.8.0.1`
- Edge Node is connected to the VPN at `10.8.0.2`
- `.env.cloud` contains PeerSight cloud variables and `.env.edge` contains the node-specific agent variables. See [ENVIRONMENT.md](ENVIRONMENT.md) for the split.

### 5.1 Cloud Gateway Packages
```bash
# Debian/Ubuntu
sudo apt-get update -y
sudo apt-get install -y wireguard-tools git make docker.io docker-compose-v2 curl

# Amazon Linux 2023
sudo dnf update -y
sudo dnf install -y wireguard-tools git make docker curl
sudo systemctl enable --now docker
```
> [!NOTE]  
> Go 1.23 is automatically installed by `deploy-cloud.sh` via `install-go.sh`. No manual Go setup is needed on either node.

### 5.2 Edge Node Packages
`wireguard-tools` must be installed. No additional compiler tools are needed if using the recommended **transfer** build mode.

---

## 6. Zero-Trust Firewall Configuration

PeerSight enforces a strict **Zero-Trust** network overlay.

```
[Edge Node Agent] ──(Outbound over WG)──> [10.8.0.1:4000 (Cloud API)]
[Admin Browser]  ──(SSH Port-Forward) ──> [10.8.0.1:5173 (Cloud UI)]
```

- **Cloud Gateway**: Port `4000/tcp` (API) and `5173/tcp` (App UI) are bound only to the WireGuard `wg0` interface. The `hardening.sh` script applies these restrictions automatically.
- **Edge Node**: The `peersight-agent` operates in **outbound-only mode** — no inbound ports are exposed to the public Internet.

To apply the hardening configuration:
```bash
cd ~/wireguard-edge-cloud-5g
set -a && . ./.env.cloud && set +a
sudo -E bash shared/scripts/hardening.sh
```

---

## 7. Cloud Gateway Deployment (One Command)

SSH into the Cloud Gateway and run the automated orchestrator:

```bash
cd ~/wireguard-edge-cloud-5g
set -a && . ./.env.cloud && set +a
sudo -E bash peersight/deploy-cloud.sh
```

This single command will:
1. ✅ Download and install **Go 1.23.0** to `/usr/local/go`
2. ✅ Compile the `peersight-agent` binary for `x86_64`
3. ✅ Create `/var/log/peersight` for event broker logging
4. ✅ Build and launch the Docker stack (`postgres`, `peersight-api`, `peersight-app`, `peersight-broker`)
5. ✅ Perform health checks on the REST API

### 7.1 Registering the Admin Account
Once deployment is finished, register your first administrative login:

```bash
# Register user account
curl -X POST http://10.8.0.1:4000/accounts/signup \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@edge5g.local", "password": "YourSecurePass123!"}'

# Elevate account to Admin in PostgreSQL
sudo docker exec -it peersight-db psql -U peersight -c \
  "UPDATE users SET role='admin' WHERE email='admin@edge5g.local';"
```

---

## 8. Managing Hosts & Registering Agents

### 8.1 Establish the SSH Tunnel
Since ports `4000` and `5173` are secured within the WireGuard interface, open an SSH tunnel from your local PC to access the Web UI:

```bash
ssh -i <your-key.pem> -N \
  -L 4000:10.8.0.1:4000 \
  -L 5173:10.8.0.1:5173 \
  ec2-user@<ELASTIC_IP>
```
Open [http://127.0.0.1:5173](http://127.0.0.1:5173) in your browser and log in with your admin credentials.

### 8.2 Register a Host Profile (Web UI)

Navigate to **Hosts** → click **"Register Host"** → enter a name (e.g. `cloud-gateway` or `edge-orangepi-01`).

The system creates a database record and returns the **Host ID (UUID)** — copy and save it. This UUID is what you pass as `PEERSIGHT_HOST_ID` to the agent.

> **Note:** Hosts can also self-register automatically on first ping if the agent is pre-configured with a valid UUID and token (see Section 8.3).

### 8.3 Generate a Host-Scoped Agent Token (PEERSIGHT_TOKEN)

`PEERSIGHT_TOKEN` is a **host-scoped service token** signed with your `PEERSIGHT_JWT_SECRET` and tracked in PostgreSQL by hash. Because the agent runs as a systemd service 24/7, you need a **long-lived token (10 years)** — not the standard 30-minute UI session token.

The token is bound to one `Host ID`. If an edge node tries to ping a different host record, the API returns `403 token_host_mismatch`.

**Step 1 — Login and get a short-lived admin token:**
```bash
# On the cloud server (or through SSH tunnel)
ADMIN_TOKEN=$(curl -s -X POST http://10.8.0.1:4000/sessions \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@peersight.local","password":"<YOUR_ADMIN_PASSWORD>"}' \
  | jq -r '.token')
echo "Admin token: $ADMIN_TOKEN"
```

**Step 2 — Exchange for a long-lived token for one host:**
```bash
AGENT_TOKEN=$(curl -s -X POST http://10.8.0.1:4000/hosts/<HOST_UUID>/agent-tokens \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  | jq -r '.agent_token')
echo "Agent token (save this!): $AGENT_TOKEN"
```

This `AGENT_TOKEN` is valid for **10 years**, is shown only once, and can be safely stored in `/etc/peersight/agent.env`. Admins can list or revoke token metadata with:

```bash
curl -s http://10.8.0.1:4000/admin/service-tokens \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq

curl -X POST http://10.8.0.1:4000/admin/service-tokens/<TOKEN_ID>/revoke \
  -H "Authorization: Bearer $ADMIN_TOKEN"
```

> [!NOTE]
> `POST /admin/agent-tokens` remains available for one migration cycle, but it creates a deprecated unbound token. Use `/hosts/:id/agent-tokens` for new deployments.

### 8.4 Configure the Cloud Agent Service

With the `PEERSIGHT_HOST_ID` from the Web UI and `AGENT_TOKEN` from the API above:

```bash
# Navigate to your repository root directory first
cd ~/wireguard-edge-cloud-5g

# Run the installation script using a relative path
sudo -E PEERSIGHT_API_URL="http://10.8.0.1:4000" \
     PEERSIGHT_HOST_ID="<CLOUD_HOST_UUID>" \
     PEERSIGHT_TOKEN="<AGENT_TOKEN>" \
     bash peersight/install-agent.sh
```

Verify the service is running:
```bash
sudo systemctl status peersight-agent
sudo journalctl -u peersight-agent -f
```

---

## 9. Edge Node Deployment (One Command)

First, generate a **separate Host ID and Agent Token** for each edge node using the same steps in Section 8.2 and 8.3 above (e.g., name the host `edge-orangepi-01`).

### Option A: Native On-Device Compilation (Slower)
SSH to the Edge node and run:

```bash
cd ~/wireguard-edge-cloud-5g
sudo -E BUILD_MODE=native \
     PEERSIGHT_API_URL="http://10.8.0.1:4000" \
     PEERSIGHT_HOST_ID="<EDGE_HOST_UUID>" \
     PEERSIGHT_TOKEN="<AGENT_TOKEN>" \
     bash peersight/deploy-edge.sh
```

### Option B: Cross-Compilation & Transfer (Recommended & Faster)
1. **On your PC / Cloud Gateway**, cross-compile for ARM64:
   ```bash
   cd ~/wireguard-edge-cloud-5g/peersight/peersight-agent
   GOOS=linux GOARCH=arm64 go build -ldflags="-s -w" -o peersight-agent-arm64 ./cmd/agent
   rsync -avzP peersight-agent-arm64 user@10.8.0.2:/tmp/peersight-agent
   ```
2. **On the Edge Node**, install and register:
   ```bash
   sudo mv /tmp/peersight-agent /usr/local/bin/peersight-agent
   sudo chmod +x /usr/local/bin/peersight-agent

   cd ~/wireguard-edge-cloud-5g
   sudo -E BUILD_MODE=transfer \
        PEERSIGHT_API_URL="http://10.8.0.1:4000" \
        PEERSIGHT_HOST_ID="<EDGE_HOST_UUID>" \
        PEERSIGHT_TOKEN="<AGENT_TOKEN>" \
        bash ./peersight/deploy-edge.sh
   ```

### 9.1 Verification
```bash
sudo systemctl status peersight-agent
sudo journalctl -u peersight-agent -f
```

---

## 10. SIEM Bridge & Loki Integration

1. Generate a scoped **Broker Token**:
   ```bash
   BROKER_TOKEN=$(curl -s -X POST http://10.8.0.1:4000/admin/broker-tokens \
     -H "Authorization: Bearer $ADMIN_TOKEN" \
     | jq -r '.broker_token')
   echo "$BROKER_TOKEN"
   ```
2. Add it to the Cloud Gateway's `.env.cloud` file:
   ```bash
   PEERSIGHT_BROKER_TOKEN=<YOUR_BROKER_TOKEN>
   PEERSIGHT_BROKER_ID=cloud-broker-1
   PEERSIGHT_QUEUE_LEASE_SECONDS=60
   ```
3. Restart the Broker and Alloy:
   ```bash
   cd ~/wireguard-edge-cloud-5g/peersight
   sudo docker compose up -d broker
   sudo systemctl restart alloy
   ```
4. Query Loki in Grafana:
   ```logql
   {job="peersight-alerts"}
   ```

---

## 11. Halting & Uninstalling PeerSight

### 11.1 Stop PeerSight Containers (Cloud Only)
To suspend service containers on the Cloud node while retaining all Postgres database metrics and accounts:
```bash
cd ~/wireguard-edge-cloud-5g/peersight
sudo -E bash stop-peersight.sh
```

### 11.2 Complete PeerSight Clean-Up
To fully erase all PeerSight files (systemd configurations, log queues, configurations, and binaries) while **preserving your DB volumes**:
```bash
cd ~/wireguard-edge-cloud-5g/peersight
sudo -E bash uninstall.sh
```

---

## 12. Detailed Configuration Reference

These variables are defined in `.env.cloud`, `.env.edge`, or `.env.peersight-local` depending on where PeerSight is running.

### 12.1 API Server Variables (`peersight-api`)

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | `postgres://peersight:...@localhost:5432/peersight` | pgx connection string. |
| `JWT_SECRET` | `change-me-in-production` | Secret key used to sign session & agent tokens. |
| `PORT` | `4000` | Port for the central API server. |
| `ENV` | `development` | Set to `production` in live environments. |
| `ALLOWED_ORIGINS` | `http://localhost:5173` | CORS allowed origins. |
| `PEERSIGHT_HOST_STALE_SECONDS` | `120` | Creates an operational alert when a host misses this heartbeat window. |
| `PEERSIGHT_HANDSHAKE_STALE_SECONDS` | `180` | Creates an operational alert for stale or unavailable WireGuard endpoint handshakes. |
| `PEERSIGHT_QUEUE_BACKLOG_ALERT_THRESHOLD` | `1000` | Creates an operational alert when unacked broker events exceed this count. |

### 12.2 Agent Variables (`peersight-agent`)

| Variable | Default | Description |
|---|---|---|
| `PEERSIGHT_API_URL` | — | Target URL of the central API (`http://10.8.0.1:4000`). |
| `PEERSIGHT_HOST_ID` | — | UUID identifying this specific node. |
| `PEERSIGHT_TOKEN` | — | JWT token issued in Web UI for the Host. |
| `PEERSIGHT_LOOP_INTERVAL` | `30` | Interval in seconds between heartbeats. |
| `PEERSIGHT_READ_ONLY` | `false` | If true, only reports stats and doesn't run sync actions. |
| `PEERSIGHT_WG_BINARY` | `wg` | Absolute or relative path to the WireGuard CLI. |

### 12.3 Broker Variables (`peersight-broker`)

| Variable | Default | Description |
|---|---|---|
| `PEERSIGHT_API_URL` | — | Target URL of the central API. |
| `PEERSIGHT_TOKEN` | — | Broker JWT token for polling. |
| `PEERSIGHT_BROKER_ID` | `cloud-broker-1` | Stable broker identity written into queue leases. |
| `PEERSIGHT_LOOP_INTERVAL` | `30` | Interval in seconds to poll events. |
| `PEERSIGHT_QUEUE_LEASE_SECONDS` | `60` | Retry timeout for leased queue events not acknowledged by the broker. |
| `PEERSIGHT_PIPE_1_TO` | `file` | Pipe output target (`file` or `syslog`). |
| `PEERSIGHT_PIPE_1_FILE` | `/var/log/peersight/events.jsonl` | Output file for events. |

---

## 13. API Endpoints Reference

### 13.1 Public Endpoints
- `GET /health` — Health check (Uptime, Postgres connectivity status).
- `GET /version` — Version output.
- `POST /sessions` — Login credentials (Email + Password) returning Access/Refresh JWTs.
- `POST /sessions/refresh` — Standard token refresher.
- `POST /accounts/signup` — Registers a new user.

### 13.2 Host Management
- `GET /hosts` — Lists all registered nodes.
- `GET /hosts/:id` — Details of a specific host.
- `GET /hosts/:id/interfaces` — Network interfaces per host.
- `GET /hosts/:id/changes` — Pending configuration changes for the agent.

### 13.3 Agent Communication
- `POST /hosts/:host_id/ping/:version` — Reciprocal agent ping for heartbeats and state reporting.
- `POST /hosts/:id/agent-tokens` — Admin-only host-scoped agent token creation.

### 13.4 Alerts & Queues
- `GET /alerts` — List of active system alarms.
- `POST /alerts/:id/resolve` — Mark alert as resolved.
- `POST /queues/:type/next` — Polled by the Broker to retrieve events.
- `POST /queues/:type/ack` — Acknowledge successful processing of events.
- `POST /queues/:type/fail` — Release leased events for retry after broker delivery failure.
- `POST /admin/broker-tokens` — Admin-only scoped broker token creation.
- `GET /admin/service-tokens` — Admin-only token metadata listing.
- `POST /admin/service-tokens/:id/revoke` — Admin-only service token revocation.

---

## 🇻🇳 Tiếng Việt

Tài liệu này là nguồn thông tin chuẩn xác nhất để triển khai, quản lý và vận hành hệ thống **PeerSight** (hệ thống giám sát mạng WireGuard, điều phối bảo mật và lưu nhật ký SIEM) trong kiến trúc phân tán Edge-Cloud 5G.

---

## 1. Tổng Quan Kiến Trúc & Các Phân Hệ

PeerSight thay thế hoàn toàn cụm giám sát cũ xây dựng bằng Python và Elixir (như Procustodibus) bằng một hệ thống backend tối giản, hiệu năng cao viết bằng **Golang** kết hợp giao diện frontend bằng **Vue.js 3**. Hệ thống được thiết kế để chạy cực kỳ mượt mà trên các thiết bị biên chạy chip ARM giới hạn tài nguyên (Orange Pi) cũng như cổng cloud gateway trung tâm (AWS EC2).

### 1.1 Sơ Đồ Kiến Trúc

```
┌──────────────┐       ┌──────────────┐       ┌──────────────┐
│ peersight-app│       │ peersight-api│       │  PostgreSQL  │
│  (Vue.js 3)  │◄─────►│   (Go/Gin)   │◄─────►│   Database   │
│  Port: 5173  │  HTTP │  Port: 4000  │  SQL  │  Port: 5432  │
└──────────────┘       └──────┬───────┘       └──────────────┘
                              │ REST
            ┌─────────────────┼─────────────────┐
            ▼                 ▼                 ▼
   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
   │peersight-agent│  │peersight-agent│  │peersight-broker│
   │  (Go daemon) │  │  (Go daemon) │  │  (Go daemon)  │
   │  Host A      │  │  Host B      │  │  SIEM Bridge  │
   └──────────────┘  └──────────────┘  └───────┬───────┘
         │                  │                   │
    ┌────┴────┐        ┌────┴────┐         ┌───┴────┐
    │WireGuard│        │WireGuard│         │Syslog/ │
    │ Kernel  │        │ Kernel  │         │ File   │
    └─────────┘        └─────────┘         └────────┘
```

### 1.2 Các Phân Hệ Cốt Lõi

| Phân hệ | Ngôn ngữ | Chế độ chạy | Mô tả |
|---|---|---|---|
| `peersight-api` | Go (Gin) | Docker Container | Central REST API — quản lý DB, xác thực agent, đăng ký hosts và xếp hàng cảnh báo. |
| `peersight-app` | Vue.js 3 | Docker Container | Dashboard quản trị hiện đại tích hợp **sơ đồ topology tương tác kiểu Obsidian**, cấu hình peers, trực quan hóa trạng thái hosts và quản lý cảnh báo. |
| `peersight-agent` | Go | Systemd Daemon | Chạy trên cả Cloud và Edge nodes. Định kỳ truy vấn API để lấy cấu hình peer mong muốn và thực thi lệnh đồng bộ ở nhân kernel. |
| `peersight-broker` | Go | Docker Container | SIEM Bridge daemon. Truy vấn các sự kiện cảnh báo từ API và ghi vào log cục bộ `/var/log/peersight/events.jsonl` (được thu thập bởi Alloy/Loki). |

### 1.3 Cấu Trúc Dự Án

```text
peersight/
├── docker-compose.yml      # Điều phối DB, API, UI và Broker
├── deploy-cloud.sh         # Thiết lập Go, khởi động container và đăng ký cloud agent
├── deploy-edge.sh          # Biên dịch trực tiếp hoặc chuyển file nhị phân tới Edge
├── install-go.sh           # Tự động phát hiện và cài đặt trình biên dịch Go (1.23.0+)
├── install-agent.sh        # Đăng ký Systemd daemon
├── stop-peersight.sh       # Dừng các Docker container nhưng giữ lại volumes dữ liệu
├── uninstall.sh            # Gỡ bỏ an toàn (agent + logs + containers, giữ lại DB)
├── peersight-api/          # Mã nguồn REST API (Gin + pgx + migrations)
├── peersight-agent/        # Mã nguồn Agent daemon (Đồng bộ kernel WireGuard)
├── peersight-broker/       # Mã nguồn Broker daemon (SIEM bridge)
└── peersight-app/          # Giao diện Admin UI (Vue 3 + Nginx)
```

---

## 2. Luồng Dữ Liệu Của PeerSight

1. **Quản trị**: Người vận hành thêm/cập nhật cấu hình peer thông qua giao diện Web **App UI** (`peersight-app`).
2. **Lưu trữ**: Phân hệ **API** (`peersight-api`) lưu thông tin này vào **PostgreSQL** dưới dạng trạng thái chờ thực thi `DesiredChange`.
3. **Nhịp tim (Heartbeat)**: Dịch vụ **Agent** cục bộ (`peersight-agent`) định kỳ gửi dữ liệu heartbeat về API (`POST /hosts/:id/ping/:version`).
4. **Nhận cấu hình**: Phân hệ **API** phản hồi kèm theo các chỉ thị `DesiredChange` đang chờ xử lý.
5. **Đồng bộ nhân Kernel**: Dịch vụ **Agent** thực thi các cuộc gọi hệ thống (tương đương lệnh `wg set`) để cập nhật giao diện mạng WireGuard cục bộ của host, sau đó báo cáo lại trạng thái cho API.
6. **Xử lý cảnh báo**: Phân hệ **API** sẽ gắn cờ (flag) đối với các lỗi sai lệch cấu hình, sai khóa (key mismatch) hoặc mất kết nối, sau đó đẩy sự kiện vào hàng đợi cảnh báo.
7. **Kênh SIEM**: Dịch vụ **Broker** (`peersight-broker`) kiểm tra hàng đợi, lấy các cảnh báo và ghi vào log dưới dạng JSON Lines (`/var/log/peersight/events.jsonl`).
8. **Khả năng quan sát (Observability)**: **Grafana Alloy** đọc tệp log `/var/log/peersight/events.jsonl` và đẩy luồng dữ liệu này về **Grafana Loki** dưới nhãn `{job="peersight-alerts"}`.

---

## 3. Bảng So Sánh: Procustodibus vs PeerSight

| Chỉ số / Tính năng | Procustodibus (Cũ) | PeerSight (Kiến trúc Hiện tại) |
|---|---|---|
| **API Backend** | Elixir / Phoenix | **Go / Gin** |
| **Agent / Broker** | Python 3 | **Go (v1.23+)** |
| **Xác thực** | Thử thách-Ký số Ed25519 | **JWT Bearer Token** |
| **Đóng gói sản phẩm**| Python wheel + Mix release | **Tệp tin nhị phân tĩnh duy nhất (Single static binary)** |
| **Kích thước Docker Image**| ~150 MB (Python runtime) | **~15 MB (Alpine)** |
| **Tải bộ nhớ Agent** | ~30–50 MB | **~5–10 MB** (Đã tối ưu hóa vượt trội) |
| **Biên dịch chéo** | Phức tạp (phụ thuộc thư viện C) | **`GOOS=linux GOARCH=arm64 go build`** |
| **Giao diện quản trị** | Vue 3 (Oruga/Bulma) | **Vue 3 (Giao diện Dark Mode Obsidian hiện đại & Đồ thị tương tác dạng Obsidian)** |

---

## 4. Tổng Quan Về Các Script Tự Động Hóa

Vòng đời triển khai hệ thống được quản lý hoàn toàn bằng các shell script trong thư mục `peersight/`:

| Script | Mục đích | Thực thi tại |
|---|---|---|
| `deploy-cloud.sh` | Cài đặt Go 1.23, biên dịch agent, cấu hình systemd agent và khởi động Docker Compose stack | Cloud Gateway |
| `deploy-edge.sh` | Thiết lập Go (biên dịch trực tiếp) hoặc xác thực file nhị phân (chuyển file biên dịch chéo) và khởi chạy systemd agent | Edge Node |
| `install-go.sh` | Tải xuống, xác thực và cấu hình Go 1.23.0+ từ trang chủ chính thức | Cả hai |
| `install-agent.sh` | Đăng ký dịch vụ systemd unit và cấu hình API tokens | Cả hai |
| `stop-peersight.sh`| Dừng các container PeerSight nhưng giữ lại PostgreSQL volumes | Cloud Gateway |
| `uninstall.sh` | Gỡ bỏ an toàn. Dừng agent, xóa file nhị phân/logs/cấu hình và dừng cụm container (giữ lại DB volumes) | Cả hai |

---

## 5. Điều Kiện Tiên Quyết

Đảm bảo bạn đã hoàn thành thiết lập hạ tầng cơ sở như mô tả trong tài liệu [DEPLOYMENT.md](DEPLOYMENT.md):
- Cloud Gateway đang chạy với IP VPN `10.8.0.1`.
- Edge Node đã kết nối thành công vào VPN tại địa chỉ `10.8.0.2`.
- Tệp `.env.cloud` chứa biến PeerSight phía cloud và `.env.edge` chứa biến agent riêng từng node. Xem [ENVIRONMENT.md](ENVIRONMENT.md) để biết quy ước tách file.

### 5.1 Các Gói Cần Thiết Trên Cloud Gateway
```bash
# Debian/Ubuntu
sudo apt-get update -y
sudo apt-get install -y wireguard-tools git make docker.io docker-compose-v2 curl

# Amazon Linux 2023
sudo dnf update -y
sudo dnf install -y wireguard-tools git make docker curl
sudo systemctl enable --now docker
```
> [!NOTE]  
> Go 1.23 sẽ được cài đặt tự động bởi script `deploy-cloud.sh` thông qua `install-go.sh`. Bạn không cần cài đặt Go bằng tay trên bất kỳ node nào.

### 5.2 Các Gói Cần Thiết Trên Edge Node
Yêu cầu đã cài đặt gói `wireguard-tools`. Không cần cài đặt trình biên dịch nếu sử dụng chế độ build biên dịch chéo và **truyền file** khuyên dùng.

---

## 6. Cấu Hình Tường Lửa Theo Mô Hình Zero-Trust

PeerSight thực thi các chính sách bảo mật mạng **Zero-Trust** cực kỳ nghiêm ngặt.

```
[Edge Node Agent] ──(Outbound over WG)──> [10.8.0.1:4000 (Cloud API)]
[Admin Browser]  ──(SSH Port-Forward) ──> [10.8.0.1:5173 (Cloud UI)]
```

- **Cloud Gateway**: Cổng API `4000/tcp` và cổng Web UI `5173/tcp` chỉ được phép lắng nghe trên giao diện mạng WireGuard `wg0`. Kịch bản `hardening.sh` tự động cấu hình các ràng buộc bảo mật này.
- **Edge Node**: Dịch vụ `peersight-agent` hoạt động theo **chế độ chỉ gửi ra ngoài (outbound-only)** — tuyệt đối không mở bất kỳ cổng kết nối đầu vào nào ra Internet công cộng.

Để áp dụng cấu hình làm cứng hệ thống bảo mật:
```bash
cd ~/wireguard-edge-cloud-5g
set -a && . ./.env.cloud && set +a
sudo -E bash shared/scripts/hardening.sh
```

---

## 7. Triển Khai Trên Cloud Gateway (Một Lệnh Duy Nhất)

Kết nối SSH vào Cloud Gateway và khởi chạy lệnh sau:

```bash
cd ~/wireguard-edge-cloud-5g
set -a && . ./.env.cloud && set +a
sudo -E bash peersight/deploy-cloud.sh
```

Lệnh duy nhất này sẽ thực hiện:
1. ✅ Tải và cài đặt **Go 1.23.0** vào đường dẫn `/usr/local/go`
2. ✅ Biên dịch file nhị phân `peersight-agent` cho cấu trúc `x86_64`
3. ✅ Tạo thư mục `/var/log/peersight` phục vụ cho log SIEM broker
4. ✅ Xây dựng và khởi động cụm Docker stack (`postgres`, `peersight-api`, `peersight-app`, `peersight-broker`)
5. ✅ Thực hiện kiểm tra sức khỏe hệ thống (healthcheck) của REST API

### 7.1 Đăng Ký Tài Khoản Quản Trị Viên
Khi tiến trình triển khai hoàn tất, hãy đăng ký tài khoản quản trị viên đầu tiên của bạn:

```bash
# Đăng ký tài khoản người dùng
curl -X POST http://10.8.0.1:4000/accounts/signup \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@edge5g.local", "password": "YourSecurePass123!"}'

# Nâng quyền tài khoản lên Admin trong PostgreSQL
sudo docker exec -it peersight-db psql -U peersight -c \
  "UPDATE users SET role='admin' WHERE email='admin@edge5g.local';"
```

---

## 8. Quản Lý Host & Đăng Ký Agent

### 8.1 Thiết Lập SSH Tunnel
Ví các cổng `4000` và `5173` đã được khóa an toàn bên trong dải IP WireGuard, hãy thiết lập SSH tunnel từ máy tính local của bạn để truy cập giao diện quản trị Web:

```bash
ssh -i <your-key.pem> -N \
  -L 4000:10.8.0.1:4000 \
  -L 5173:10.8.0.1:5173 \
  ec2-user@<ELASTIC_IP>
```
Mở đường dẫn [http://127.0.0.1:5173](http://127.0.0.1:5173) trên trình duyệt máy tính của bạn và đăng nhập bằng tài khoản quản trị đã tạo.

### 8.2 Đăng Ký Hồ Sơ Host (Trên Giao Diện Web)

Đi tới mục **Hosts** → nhấn chọn **"Register Host"** → điền tên gợi nhớ (ví dụ: `cloud-gateway` hoặc `edge-orangepi-01`).

Hệ thống sẽ lưu trữ thông tin và trả về mã **Host ID (dạng UUID)** — hãy lưu lại mã này. Đây chính là giá trị bạn sẽ truyền vào cấu hình `PEERSIGHT_HOST_ID` cho Agent.

> **Lưu ý:** Các host cũng có khả năng tự động đăng ký trong lần ping đầu tiên nếu agent được cấu hình sẵn với UUID và token hợp lệ (xem Mục 8.3).

### 8.3 Tạo Agent Token Theo Từng Host (PEERSIGHT_TOKEN)

`PEERSIGHT_TOKEN` là một **token dịch vụ có phạm vi riêng theo từng host (host-scoped service token)** được ký bằng khóa bí mật `PEERSIGHT_JWT_SECRET` và lưu hash trong PostgreSQL. Vì Agent chạy liên tục 24/7 như một systemd service, bạn cần tạo **token dài hạn (có thời hạn 10 năm)** — chứ không dùng token phiên làm việc UI 30 phút thông thường.

Mỗi token được liên kết cố định với một `Host ID`. Nếu một edge node cố tình dùng token này để ping cho một host ID khác, API sẽ trả về lỗi từ chối `403 token_host_mismatch`.

**Bước 1 — Đăng nhập để lấy admin token ngắn hạn:**
```bash
# Thực hiện trên máy chủ cloud (hoặc thông qua SSH tunnel)
ADMIN_TOKEN=$(curl -s -X POST http://10.8.0.1:4000/sessions \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@peersight.local","password":"<YOUR_ADMIN_PASSWORD>"}' \
  | jq -r '.token')
echo "Admin token: $ADMIN_TOKEN"
```

**Bước 2 — Đổi lấy token dài hạn cho host cụ thể:**
```bash
AGENT_TOKEN=$(curl -s -X POST http://10.8.0.1:4000/hosts/<HOST_UUID>/agent-tokens \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  | jq -r '.agent_token')
echo "Agent token (hãy lưu lại!): $AGENT_TOKEN"
```

Mã `AGENT_TOKEN` này có thời hạn sử dụng lên tới **10 năm**, chỉ hiển thị duy nhất một lần và được lưu an toàn tại đường dẫn `/etc/peersight/agent.env`. Quản trị viên có thể liệt kê hoặc thu hồi các tokens thông qua lệnh:

```bash
curl -s http://10.8.0.1:4000/admin/service-tokens \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq

curl -X POST http://10.8.0.1:4000/admin/service-tokens/<TOKEN_ID>/revoke \
  -H "Authorization: Bearer $ADMIN_TOKEN"
```

> [!NOTE]
> Quyền Admin tạo token qua `POST /admin/agent-tokens` vẫn khả dụng cho việc tương thích ngược, tuy nhiên phương thức này đã cũ và không ràng buộc theo host. Hãy luôn dùng `/hosts/:id/agent-tokens` cho các hệ thống triển khai mới.

### 8.4 Cấu Hinh Dịch Vụ Agent Trên Cloud

Sử dụng mã `PEERSIGHT_HOST_ID` lấy từ giao diện Web UI và mã `AGENT_TOKEN` lấy từ API ở trên để kích hoạt dịch vụ:

```bash
# Di chuyển tới thư mục gốc của repository
cd ~/wireguard-edge-cloud-5g

# Khởi chạy script cài đặt
sudo -E PEERSIGHT_API_URL="http://10.8.0.1:4000" \
     PEERSIGHT_HOST_ID="<CLOUD_HOST_UUID>" \
     PEERSIGHT_TOKEN="<AGENT_TOKEN>" \
     bash peersight/install-agent.sh
```

Xác thực trạng thái hoạt động của dịch vụ:
```bash
sudo systemctl status peersight-agent
sudo journalctl -u peersight-agent -f
```

---

## 9. Triển Khai Trên Edge Node (Một Lệnh Duy Nhất)

Trước tiên, hãy sinh một **cặp mã Host ID và Agent Token riêng biệt** cho mỗi thiết bị biên (Edge Node) theo đúng quy trình hướng dẫn ở Mục 8.2 và 8.3 (ví dụ, đặt tên host là `edge-orangepi-01`).

### Cách 1: Biên Dịch Trực Tiếp Trên Thiết Bị (Chậm Hơn)
Kết nối SSH tới Edge node và chạy:

```bash
cd ~/wireguard-edge-cloud-5g
sudo -E BUILD_MODE=native \
     PEERSIGHT_API_URL="http://10.8.0.1:4000" \
     PEERSIGHT_HOST_ID="<EDGE_HOST_UUID>" \
     PEERSIGHT_TOKEN="<AGENT_TOKEN>" \
     bash peersight/deploy-edge.sh
```

### Cách 2: Biên Dịch Chéo & Truyền File (Khuyên Dùng & Nhanh Hơn)
1. **Thực hiện trên Máy tính của bạn hoặc Cloud Gateway**, biên dịch chéo cho nhân ARM64:
   ```bash
   cd ~/wireguard-edge-cloud-5g/peersight/peersight-agent
   GOOS=linux GOARCH=arm64 go build -ldflags="-s -w" -o peersight-agent-arm64 ./cmd/agent
   rsync -avzP peersight-agent-arm64 user@10.8.0.2:/tmp/peersight-agent
   ```
2. **Thực hiện trên Edge Node**, cài đặt và cấu hình dịch vụ:
   ```bash
   sudo mv /tmp/peersight-agent /usr/local/bin/peersight-agent
   sudo chmod +x /usr/local/bin/peersight-agent

   cd ~/wireguard-edge-cloud-5g
   sudo -E BUILD_MODE=transfer \
        PEERSIGHT_API_URL="http://10.8.0.1:4000" \
        PEERSIGHT_HOST_ID="<EDGE_HOST_UUID>" \
        PEERSIGHT_TOKEN="<AGENT_TOKEN>" \
        bash ./peersight/deploy-edge.sh
   ```

### 9.1 Xác Thực Trạng Thái
```bash
sudo systemctl status peersight-agent
sudo journalctl -u peersight-agent -f
```

---

## 10. Tích Hợp SIEM Bridge & Loki

1. Tạo mã **Broker Token** phục vụ cho luồng log:
   ```bash
   BROKER_TOKEN=$(curl -s -X POST http://10.8.0.1:4000/admin/broker-tokens \
     -H "Authorization: Bearer $ADMIN_TOKEN" \
     | jq -r '.broker_token')
   echo "$BROKER_TOKEN"
   ```
2. Cập nhật mã này vào tệp `.env.cloud` trên Cloud Gateway:
   ```bash
   PEERSIGHT_BROKER_TOKEN=<YOUR_BROKER_TOKEN>
   PEERSIGHT_BROKER_ID=cloud-broker-1
   PEERSIGHT_QUEUE_LEASE_SECONDS=60
   ```
3. Khởi động lại phân hệ Broker và Alloy:
   ```bash
   cd ~/wireguard-edge-cloud-5g/peersight
   sudo docker compose up -d broker
   sudo systemctl restart alloy
   ```
4. Truy vấn log Loki trên màn hình Grafana:
   ```logql
   {job="peersight-alerts"}
   ```

---

## 11. Dừng & Gỡ Bỏ Cấu Hình PeerSight

### 11.1 Dừng các Container PeerSight (Chỉ trên Cloud)
Dừng toàn bộ container hoạt động trên Cloud nhưng giữ lại toàn bộ cơ sở dữ liệu PostgreSQL và tài khoản:
```bash
cd ~/wireguard-edge-cloud-5g/peersight
sudo -E bash stop-peersight.sh
```

### 11.2 Gỡ bỏ hoàn toàn PeerSight
Để xóa sạch toàn bộ các file của PeerSight (cấu hình systemd, log queues, tệp nhị phân) nhưng **giữ lại DB volumes**:
```bash
cd ~/wireguard-edge-cloud-5g/peersight
sudo -E bash uninstall.sh
```

---

## 12. Tham Chiếu Cấu Hình Chi Tiết

Các biến môi trường dưới đây được khai báo trong `.env.cloud`, `.env.edge`, hoặc `.env.peersight-local` tùy vị trí chạy PeerSight.

### 12.1 Biến Của Máy Chủ API (`peersight-api`)

| Biến | Mặc định | Mô tả |
|---|---|---|
| `DATABASE_URL` | `postgres://peersight:...@localhost:5432/peersight` | pgx connection string. |
| `JWT_SECRET` | `change-me-in-production` | Secret key used to sign session & agent tokens. |
| `PORT` | `4000` | Port for the central API server. |
| `ENV` | `development` | Set to `production` in live environments. |
| `ALLOWED_ORIGINS` | `http://localhost:5173` | CORS allowed origins. |
| `PEERSIGHT_HOST_STALE_SECONDS` | `120` | Creates an operational alert when a host misses this heartbeat window. |
| `PEERSIGHT_HANDSHAKE_STALE_SECONDS` | `180` | Creates an operational alert for stale or unavailable WireGuard endpoint handshakes. |
| `PEERSIGHT_QUEUE_BACKLOG_ALERT_THRESHOLD` | `1000` | Creates an operational alert when unacked broker events exceed this count. |

### 12.2 Biến Của Agent (`peersight-agent`)

| Biến | Mặc định | Mô tả |
|---|---|---|
| `PEERSIGHT_API_URL` | — | Target URL of the central API (`http://10.8.0.1:4000`). |
| `PEERSIGHT_HOST_ID` | — | UUID identifying this specific node. |
| `PEERSIGHT_TOKEN` | — | JWT token issued in Web UI for the Host. |
| `PEERSIGHT_LOOP_INTERVAL` | `30` | Interval in seconds between heartbeats. |
| `PEERSIGHT_READ_ONLY` | `false` | If true, only reports stats and doesn't run sync actions. |
| `PEERSIGHT_WG_BINARY` | `wg` | Absolute or relative path to the WireGuard CLI. |

### 12.3 Biến Của Broker (`peersight-broker`)

| Biến | Mặc định | Mô tả |
|---|---|---|
| `PEERSIGHT_API_URL` | — | Target URL of the central API. |
| `PEERSIGHT_TOKEN` | — | Broker JWT token for polling. |
| `PEERSIGHT_BROKER_ID` | `cloud-broker-1` | Stable broker identity written into queue leases. |
| `PEERSIGHT_LOOP_INTERVAL` | `30` | Interval in seconds to poll events. |
| `PEERSIGHT_QUEUE_LEASE_SECONDS` | `60` | Retry timeout for leased queue events not acknowledged by the broker. |
| `PEERSIGHT_PIPE_1_TO` | `file` | Pipe output target (`file` or `syslog`). |
| `PEERSIGHT_PIPE_1_FILE` | `/var/log/peersight/events.jsonl` | Output file for events. |

---

## 13. API Endpoints Reference

### 13.1 Public Endpoints
- `GET /health` — Health check (Uptime, Postgres connectivity status).
- `GET /version` — Version output.
- `POST /sessions` — Login credentials (Email + Password) returning Access/Refresh JWTs.
- `POST /sessions/refresh` — Standard token refresher.
- `POST /accounts/signup` — Registers a new user.

### 13.2 Host Management
- `GET /hosts` — Lists all registered nodes.
- `GET /hosts/:id` — Details of a specific host.
- `GET /hosts/:id/interfaces` — Network interfaces per host.
- `GET /hosts/:id/changes` — Pending configuration changes for the agent.

### 13.3 Agent Communication
- `POST /hosts/:host_id/ping/:version` — Reciprocal agent ping for heartbeats and state reporting.
- `POST /hosts/:id/agent-tokens` — Admin-only host-scoped agent token creation.

### 13.4 Alerts & Queues
- `GET /alerts` — List of active system alarms.
- `POST /alerts/:id/resolve` — Mark alert as resolved.
- `POST /queues/:type/next` — Polled by the Broker to retrieve events.
- `POST /queues/:type/ack` — Acknowledge successful processing of events.
- `POST /queues/:type/fail` — Release leased events for retry after broker delivery failure.
- `POST /admin/broker-tokens` — Admin-only scoped broker token creation.
- `GET /admin/service-tokens` — Admin-only token metadata listing.
- `POST /admin/service-tokens/:id/revoke` — Admin-only service token revocation.
