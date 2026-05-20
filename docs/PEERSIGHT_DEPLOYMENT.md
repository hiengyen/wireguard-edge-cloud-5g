# PeerSight Deployment Guide (WireGuard Orchestration)

This document provides instructions on deploying the **PeerSight** system (WireGuard network monitoring and management) into the existing Edge-Cloud 5G infrastructure. The system consists of 4 main components:
1. **Database** (PostgreSQL)
2. **API Backend** (Golang)
3. **App UI** (Vue.js)
4. **Agent** (Golang daemon running on both the Cloud Gateway and Edge Nodes)

The system is designed with a Zero-Trust architecture: all connections run through the WireGuard virtual network (Overlay network `10.8.0.x`) and no ports are exposed directly to the Internet.

---

## 1. Prerequisites
Ensure you have completed the basic steps in [DEPLOYMENT.md](DEPLOYMENT.md), including:
- Cloud Gateway is running and has a VPN address (e.g., `10.8.0.1`)
- Edge Node is connected to the VPN network (e.g., `10.8.0.2`)
- The `.env` configuration file has all the necessary variables for PeerSight.

Check your `.env` file and make sure the following lines exist:
```bash
# ── PeerSight ──
PEERSIGHT_DB_PASSWORD=YourSecureDatabasePassword
PEERSIGHT_JWT_SECRET=change-me-in-production-min-32-chars
PEERSIGHT_API_PORT=4000
PEERSIGHT_APP_PORT=5173
PEERSIGHT_BROKER_TOKEN=
```

---

## 2. Deploying the Core System on the Cloud Gateway

The API, UI, Database, and Broker will be deployed using Docker Compose on the Cloud server (Amazon Linux / Debian).

1. **Access the Cloud Gateway:**
   ```bash
   ssh -i <your-key.pem> ec2-user@<elastic-ip>
   ```

2. **Run the Hardening script to open ports in the VPN network:**
   *(If you haven't run it yet)*
   ```bash
   cd ~/wireguard-edge-cloud-5g
   set -a && . ./.env && set +a
   sudo -E ./shared/scripts/hardening.sh
   ```

3. **Start the PeerSight Stack:**
   ```bash
   sudo mkdir -p /var/log/peersight
   sudo chmod 755 /var/log/peersight

   cd ~/wireguard-edge-cloud-5g/peersight
   set -a && . ../.env && set +a
   sudo -E docker compose --env-file ../.env up -d --build
   ```

4. **Check the status:**
   ```bash
   sudo docker ps | grep peersight
   curl -s http://10.8.0.1:4000/health
   ```

5. **Create the first Administrator account:**
   ```bash
   # Register an account
   curl -X POST http://10.8.0.1:4000/accounts/signup \
     -H "Content-Type: application/json" \
     -d '{"email": "admin@edge5g.local", "password": "YourSecurePass123!"}'

   # Grant Admin privileges directly via the Database
   sudo docker exec -it peersight-db psql -U peersight -c \
     "UPDATE users SET role='admin' WHERE email='admin@edge5g.local';"
   ```

---

## 3. Accessing the PeerSight Web UI

For security reasons, we do not expose ports to the Public Internet. Instead, access is routed through an SSH Tunnel (Port Forwarding).

1. **On your local computer**, create an SSH Tunnel:
   ```bash
   ssh -i <your-key.pem> -N \
     -L 4000:10.8.0.1:4000 \
     -L 5173:10.8.0.1:5173 \
     ec2-user@<elastic-ip>
   ```
2. **Open your Web Browser**:
   Navigate to [http://127.0.0.1:5173](http://127.0.0.1:5173). Log in using the `admin@edge5g.local` account you just created.

---

## 4. Creating New Hosts & Retrieving Tokens from UI

For the Agents (on Cloud and Edge) to report to the API, you must create a profile for them in the PeerSight UI:

1. Log in to the Web UI.
2. Navigate to the **Hosts** section.
3. Click **Create Host**.
4. Create a Host for the Cloud (e.g., name: `cloud-gateway`). Save the **Host ID (UUID)** and **Agent Token**.
5. Click **Create Host** again.
6. Create a Host for the Edge (e.g., name: `edge-orangepi-01`). Save the **Host ID (UUID)** and **Agent Token** specific to this Edge node.

---

## 5. Installing the PeerSight Agent

You need to install the `peersight-agent` on both the Cloud Server and the Edge Node devices. The agent source code is located in the `peersight/peersight-agent` directory.

### 5.1 Installation on Cloud Gateway (x86_64 / amd64 architecture)

1. **Compile the Agent:**
   ```bash
   cd ~/wireguard-edge-cloud-5g/peersight
   make agent
   sudo cp peersight-agent /usr/local/bin/peersight-agent
   ```
2. **Install using the Automation script:**
   Use the Host ID and Token retrieved from the Web UI (for `cloud-gateway`) to run the installation script:
   ```bash
   cd ~/wireguard-edge-cloud-5g
   sudo PEERSIGHT_API_URL="http://127.0.0.1:4000" \
        PEERSIGHT_HOST_ID="<your-cloud-host-uuid>" \
        PEERSIGHT_TOKEN="<your-cloud-agent-jwt>" \
        ./peersight/install-agent.sh
   ```
3. **Check the status:**
   ```bash
   sudo systemctl status peersight-agent
   ```

### 5.2 Installation on Edge Node (ARM64 architecture)

1. **Cross-compile from the Cloud Server (or your local PC):**
   ```bash
   cd ~/wireguard-edge-cloud-5g/peersight/peersight-agent
   GOOS=linux GOARCH=arm64 go build -ldflags="-s -w" -o peersight-agent-arm64 ./cmd/agent
   ```
2. **Transfer the binary to the Edge Node (via the WireGuard IP):**
   ```bash
   rsync -avzP peersight-agent-arm64 user@10.8.0.2:/tmp/peersight-agent
   ```
3. **SSH into the Edge Node (`ssh user@10.8.0.2`) and Install:**
   ```bash
   # Move the binary to the correct location
   sudo mv /tmp/peersight-agent /usr/local/bin/peersight-agent
   sudo chmod +x /usr/local/bin/peersight-agent

   # Clone the repository (if not already present)
   git clone https://github.com/<your-repo>/wireguard-edge-cloud-5g.git ~/wireguard-edge-cloud-5g
   
   cd ~/wireguard-edge-cloud-5g
   chmod +x peersight/install-agent.sh

   # Install using the Host ID and Token for the Edge Node
   sudo PEERSIGHT_API_URL="http://10.8.0.1:4000" \
        PEERSIGHT_HOST_ID="<your-edge-host-uuid>" \
        PEERSIGHT_TOKEN="<your-edge-agent-jwt>" \
        ./peersight/install-agent.sh
   ```

Return to the PeerSight Web UI, and both `cloud-gateway` and `edge-orangepi-01` should now display their status as **Online**.

---

## 6. (Advanced) Integrating Event Logs into Loki

The PeerSight Broker automatically exports events/alerts to the `/var/log/peersight/events.jsonl` log file on the Cloud Server. The system is already configured to parse these logs through Grafana Alloy.

To enable the alert log collection system:

1. Log in to the Web UI, and create a **Broker Token** from the API (or use the admin token).
2. Set `PEERSIGHT_BROKER_TOKEN` in the `.env` file on the Cloud Server.
3. Restart the PeerSight Broker:
   ```bash
   cd ~/wireguard-edge-cloud-5g/peersight
   sudo docker compose up -d broker
   ```
4. Restart the Grafana Alloy process on the Cloud to fetch the latest SIEM Bridge Pipeline configuration file:
   ```bash
   sudo systemctl restart alloy
   ```

From this point onwards, you can navigate to Grafana UI -> Explore -> select the **Loki** source and query using LogQL:
```logql
{job="peersight-alerts"}
```
This allows you to view all changes across the WireGuard network (e.g., Adding a new peer, changing AllowedIPs, Endpoint roaming...).
