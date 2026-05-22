# PeerSight Deployment Guide (WireGuard Orchestration)

This document provides instructions for deploying the **PeerSight** system (WireGuard network monitoring and management) into the existing Edge-Cloud 5G infrastructure.

The architecture consists of 4 core parts:
1. **Database** (PostgreSQL) — Cloud
2. **API Backend** (Golang) — Cloud
3. **App UI** (Vue.js via Nginx) — Cloud
4. **Agent** (Golang daemon) — Running directly on **both** the Cloud Gateway and Edge Nodes

The design implements **Zero-Trust** security principles: all traffic operates inside the WireGuard overlay network (`10.8.0.x`), and no administrative ports are exposed to the public Internet.

---

## Automation Scripts Overview

The deployment is fully automated via shell scripts in the `peersight/` directory:

| Script | Purpose | Run on |
|---|---|---|
| `deploy-cloud.sh` | Installs Go, builds agent, launches Docker stack, registers systemd service | Cloud Gateway |
| `deploy-edge.sh` | Installs Go (native mode) or validates binary (transfer mode), registers systemd service | Edge Node |
| `install-go.sh` | Downloads and installs Go from official upstream tarball (auto-detects amd64/arm64) | Both |
| `install-agent.sh` | Creates `/etc/peersight/agent.env` and the systemd unit file (called internally by deploy scripts) | Both |
| `stop-peersight.sh`| Stops PeerSight Docker services on the Cloud Gateway (preserving data volumes) | Cloud Gateway |
| `uninstall.sh` | Full uninstaller: stops agent, removes binaries/config/logs, and tears down Docker stack (preserving database volume) | Both |

---

## 1. Prerequisites

Ensure you have completed the base infrastructure setup described in [DEPLOYMENT.md](DEPLOYMENT.md):
- Cloud Gateway is running with VPN address `10.8.0.1`
- Edge Node is connected to the VPN at `10.8.0.2`
- The `.env` file contains the PeerSight variables (see `.env.example` for reference)

### 1.1 Cloud Gateway Packages

```bash
# Debian/Ubuntu
sudo apt-get update -y
sudo apt-get install -y wireguard-tools git make docker.io docker-compose-v2 curl

# Amazon Linux 2023
sudo dnf update -y
sudo dnf install -y wireguard-tools git make docker curl
sudo systemctl enable --now docker
```

> **Note:** Go is installed automatically by `deploy-cloud.sh` via `install-go.sh`. No manual Go setup is needed.

### 1.2 Edge Node Packages

`wireguard-tools` should already be installed from the WireGuard bootstrap step. No additional packages are required — `deploy-edge.sh` handles everything.

---

## 2. Firewall Rules (Zero-Trust)

```
[Edge Node Agent] ──(Outbound over WG)──> [10.8.0.1:4000 (Cloud API)]
[Admin Browser]  ──(SSH Port-Forward) ──> [10.8.0.1:5173 (Cloud UI)]
```

### 2.1 Cloud Gateway
Ports `4000/tcp` (API) and `5173/tcp` (App UI) are restricted to the WireGuard overlay. The `hardening.sh` script handles this automatically:

```bash
cd ~/wireguard-edge-cloud-5g
set -a && . ./.env && set +a
sudo -E ./shared/scripts/hardening.sh
```

### 2.2 Edge Node
The `peersight-agent` operates in **outbound-only mode** — no inbound ports need to be opened.

---

## 3. Cloud Gateway Deployment (One Command)

SSH into the Cloud Gateway and run:

```bash
cd ~/wireguard-edge-cloud-5g
set -a && . ./.env && set +a
sudo -E ./peersight/deploy-cloud.sh
```

This single command will:
1. ✅ Install Go 1.23 from the official upstream (if not present)
2. ✅ Build the `peersight-agent` binary for x86_64
3. ✅ Create `/var/log/peersight` for SIEM broker logs
4. ✅ Launch the full Docker Compose stack (PostgreSQL, API, Web UI, Broker)
5. ✅ Wait until the API health check passes
6. ✅ Print endpoint summary and next steps

After the script completes, bootstrap the first admin account:

```bash
# Sign up
curl -X POST http://10.8.0.1:4000/accounts/signup \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@edge5g.local", "password": "YourSecurePass123!"}'

# Promote to admin
sudo docker exec -it peersight-db psql -U peersight -c \
  "UPDATE users SET role='admin' WHERE email='admin@edge5g.local';"
```

---

## 4. Access the Web UI (SSH Tunnel)

On your **local development machine**:

```bash
ssh -i <your-key.pem> -N \
  -L 4000:10.8.0.1:4000 \
  -L 5173:10.8.0.1:5173 \
  ec2-user@<ELASTIC_IP>
```

Then open [http://127.0.0.1:5173](http://127.0.0.1:5173) and log in.

### Create Host Identities

1. Go to **Hosts** → **Create Host** → name it `cloud-gateway`. Save the **Host ID** and **Agent Token**.
2. Create another Host → name it `edge-orangepi-01`. Save its **Host ID** and **Agent Token**.

### Register the Cloud Agent

Now that you have the Cloud host credentials, register the agent service:

```bash
sudo PEERSIGHT_HOST_ID="<CLOUD_UUID>" \
     PEERSIGHT_TOKEN="<CLOUD_JWT>" \
     ~/wireguard-edge-cloud-5g/peersight/install-agent.sh
```

---

## 5. Edge Node Deployment (One Command)

Choose one of two modes depending on your situation:

### Option A: Native Build on the Edge Device

SSH into the Edge node and run everything in a single command:

```bash
cd ~/wireguard-edge-cloud-5g
sudo -E BUILD_MODE=native \
     PEERSIGHT_API_URL="http://10.8.0.1:4000" \
     PEERSIGHT_HOST_ID="<EDGE_UUID>" \
     PEERSIGHT_TOKEN="<EDGE_JWT>" \
     ./peersight/deploy-edge.sh
```

This will:
1. ✅ Install Go 1.23 from the official upstream (auto-detects arm64)
2. ✅ Build the `peersight-agent` natively on the ARM device
3. ✅ Install and start the systemd service
4. ✅ Print connection status

### Option B: Cross-Compile + Transfer (Faster)

**On the Cloud Gateway (or your PC):**
```bash
cd ~/wireguard-edge-cloud-5g/peersight/peersight-agent
GOOS=linux GOARCH=arm64 go build -ldflags="-s -w" -o peersight-agent-arm64 ./cmd/agent
rsync -avzP peersight-agent-arm64 user@10.8.0.2:/tmp/peersight-agent
```

**On the Edge Node:**
```bash
sudo mv /tmp/peersight-agent /usr/local/bin/peersight-agent
sudo chmod +x /usr/local/bin/peersight-agent

cd ~/wireguard-edge-cloud-5g
sudo -E BUILD_MODE=transfer \
     PEERSIGHT_API_URL="http://10.8.0.1:4000" \
     PEERSIGHT_HOST_ID="<EDGE_UUID>" \
     PEERSIGHT_TOKEN="<EDGE_JWT>" \
     ./peersight/deploy-edge.sh
```

### Verify Agent Status

```bash
sudo systemctl status peersight-agent
sudo journalctl -u peersight-agent -f
```

Both hosts should now appear **Online** in the PeerSight Web UI.

---

## 6. SIEM Bridge & Loki Log Integration

To pipe security events into Grafana Loki:

1. Obtain a **Broker Token** from the PeerSight API.
2. Set it in `.env` on the Cloud host:
   ```bash
   PEERSIGHT_BROKER_TOKEN=<YOUR_BROKER_TOKEN>
   ```
3. Restart the Broker and Alloy:
   ```bash
   cd ~/wireguard-edge-cloud-5g/peersight
   sudo docker compose up -d broker
   sudo systemctl restart alloy
   ```
4. In Grafana → **Explore** → **Loki**, query:
   ```logql
   {job="peersight-alerts"}
   ```

---

## 7. Halting & Uninstalling PeerSight

### 7.1 Stop All PeerSight Containers (Cloud Only)
To temporarily halt PeerSight services on the Cloud Gateway while keeping your configuration and DB volumes intact, run:
```bash
cd ~/wireguard-edge-cloud-5g/peersight
sudo ./stop-peersight.sh
```
*(Alternatively, without using the script, run `docker compose stop` inside the `peersight/` folder).*

### 7.2 Full PeerSight Uninstallation
To completely remove the PeerSight Agent and (if on Cloud) the Docker container stack while preserving your database volumes (so you don't lose admin accounts or registered host configurations), run:
```bash
cd ~/wireguard-edge-cloud-5g/peersight
sudo ./uninstall.sh
```
This script will safely clean up the agent systemd service, log files at `/var/log/peersight`, configuration at `/etc/peersight`, and the binaries at `/usr/local/bin/peersight-agent`.
