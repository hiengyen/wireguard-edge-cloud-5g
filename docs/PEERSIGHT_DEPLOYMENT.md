# PeerSight Reference & Deployment Guide (WireGuard Orchestration)

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
| `peersight-app` | Vue.js 3 | Docker Container | Admin dashboard for configuring peers, visualizing host statuses, and managing alerts. |
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
| **Admin UI** | Vue 3 (Oruga/Bulma) | **Vue 3 (Custom Sleek Dark Mode)** |

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
- The `.env` file contains the PeerSight variables (see `.env.example` for reference)

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
set -a && . ./.env && set +a
sudo -E bash shared/scripts/hardening.sh
```

---

## 7. Cloud Gateway Deployment (One Command)

SSH into the Cloud Gateway and run the automated orchestrator:

```bash
cd ~/wireguard-edge-cloud-5g
set -a && . ./.env && set +a
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
2. Add it to the Cloud Gateway's `.env` file:
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

These variables are defined in `.env` and consumed by the PeerSight modules.

### 12.1 API Server Variables (`peersight-api`)

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | `postgres://peersight:...@localhost:5432/peersight` | pgx connection string. |
| `JWT_SECRET` | `change-me-in-production` | Secret key used to sign session & agent tokens. |
| `PORT` | `4000` | Port for the central API server. |
| `ENV` | `development` | Set to `production` in live environments. |
| `ALLOWED_ORIGINS`| `http://localhost:5173` | CORS allowed origins. |
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
