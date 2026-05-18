# Deployment Guide

This document describes the recommended deployment workflow for the `wireguard-edge-cloud-5g` project in a production-oriented setup.
For a compact command reference, see [COMMANDS.md](./COMMANDS.md).

The repository assumes:

- WireGuard overlay network: `10.8.0.0/24`
- WireGuard server interface: `10.8.0.1/24`
- Each edge node uses a unique `/32` client address, for example `10.8.0.2/32`
- Peer registration is done manually for maximum security.

## 1. Prerequisites

Prepare the following before deployment:

- An AWS account with permission to create EC2, IAM, EIP, Security Group, and Secrets Manager resources
- An existing AWS EC2 key pair for SSH access
- A public subnet and VPC where the EC2 instance will run
- Optionally, a DNS record for the Registration API, for example `vpn-api.example.com`
- An edge device with:
  - Linux
  - WireGuard support
  - Quectel-compatible WWAN/QMI stack if using the 5G automation scripts

Install locally:

- `terraform >= 1.9`
- `docker` and Docker Compose v2
- `bash`

## 2. Prepare Environment Variables

Create the deployment environment file:

```bash
cp .env.example .env
```

Load the variables into the current shell:

```bash
set -a && . ./.env && set +a
```

Update `.env` with your real values:

- `TF_VAR_admin_ssh_cidr`
- `TF_VAR_wireguard_port`
- `TF_VAR_wireguard_network`
- `TF_VAR_wireguard_client_cidr`
- `GRAFANA_ADMIN_PASSWORD`
- `PROMETHEUS_VERSION`
- `GRAFANA_VERSION`
- `LOKI_VERSION`
- `LOKI_PORT`
- `ALLOY_LOKI_URL`
- `ALLOY_HTTP_LISTEN_ADDR`
- `MONITORING_BIND_ADDRESS`
- `ALLOW_MONITORING_OVER_WIREGUARD`
- `WIREGUARD_PORT`
- `WIREGUARD_ALLOWED_IPS`

- `EDGE_EXTRA_TCP_PORTS`

Recommended base values:

- `TF_VAR_wireguard_network=10.8.0.0/24`
- `TF_VAR_wireguard_client_cidr=10.8.0.2/32`
- `TF_VAR_wireguard_port=51820`
- `WIREGUARD_PORT=51820`
- `WIREGUARD_ALLOWED_IPS=10.8.0.0/24`

- `MONITORING_BIND_ADDRESS=127.0.0.1`
- `LOKI_PORT=3100`
- `ALLOY_LOKI_URL=http://10.8.0.1:3100/loki/api/v1/push`
- `ALLOY_HTTP_LISTEN_ADDR=0.0.0.0:12345`
- `ALLOW_MONITORING_OVER_WIREGUARD=false`
- `EDGE_EXTRA_TCP_PORTS='443 5201'`
- `TF_VAR_admin_ssh_cidr='["<your-public-ip>/32"]'`

## 3. Configure Terraform Inputs

Review [cloud/terraform/ec2/terraform.tfvars.example](/home/hiengyen/CODE/wireguard-edge-cloud-5g/cloud/terraform/ec2/terraform.tfvars.example:1) and provide the required values either through:

- exported `TF_VAR_*` environment variables from `.env`
- or a local non-committed `terraform.tfvars`

Required infrastructure values:

- `vpc_id`
- `subnet_id`
- `key_name`
- optionally `instance_type`

Current repository default:

- `instance_type=t3.medium`
- Use a larger type if you expect Prometheus, Grafana, Docker, and WireGuard to run together under sustained load

## 4. Provision the Cloud Node

Run:

```bash
set -a && . ./.env && set +a
cd cloud/terraform/ec2
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

If you are increasing RAM on an existing deployment, review the plan carefully because changing `instance_type` updates the EC2 instance shape.

Capture the outputs:

- EC2 public IP
- WireGuard endpoint
- Security group ID

Useful commands:

```bash
terraform output public_ip
terraform output wireguard_endpoint

```

What Terraform sets up:

- Amazon Linux 2023 EC2 instance
- encrypted root volume
- Elastic IP
- IAM role for Secrets Manager access
- WireGuard server bootstrap

- Base operator packages on the cloud node: `curl`, `rsync`, `iperf3`, `git`, `tmux`, `stow`, `vim`, `wget`, `docker`, and Docker Compose v2

## 5. Verify the Cloud Node

SSH to the instance:

```bash
ssh -i <your-key.pem> ec2-user@<elastic-ip>
```

Check services:

```bash
sudo systemctl status wg-quick@wg0

```

Check WireGuard:

```bash
sudo wg show
sudo cat /etc/wireguard/wg0.conf
sudo cat /etc/wireguard/server_public.key
```

Check listeners:

```bash
sudo ss -lntp | grep 51820
```

Expected behavior:

- `wg0` is active

Important note:

- The bootstrap `user_data.sh` creates a sample peer using `10.8.0.2/32`
- If your first real edge node also uses `10.8.0.2/32`, remove or replace that sample peer before registering a different client key

## 6. Harden the Cloud Node

Before starting the monitoring stack, secure the cloud node and install the metrics exporter:

```bash
set -a && . ./.env && set +a
sudo -E ./shared/scripts/hardening.sh
sudo -E ./shared/scripts/install-node-exporter.sh
```

Verify Node Exporter on the cloud host:

```bash
sudo systemctl status node_exporter --no-pager
curl http://127.0.0.1:9100/metrics | head
```

## 7. Start Monitoring on the Cloud Node

On the cloud host:

```bash
cd cloud/monitoring
```

The monitoring stack includes a **Unified Edge & Cloud Dashboard** for a single-pane-of-glass operational view.

To start the stack:

```bash
# Use -E to preserve environment variables loaded from .env
sudo -E docker compose --env-file ../../.env up -d --force-recreate
```

Alternatively, use the wrapper script which automatically applies `ALLOW_MONITORING_OVER_WIREGUARD` and validates required variables:

```bash
sudo ./cloud/monitoring/setup-monitoring.sh
```

Verify:

```bash
sudo docker ps
curl http://127.0.0.1:9090/-/healthy
curl http://127.0.0.1:3100/ready
curl http://127.0.0.1:3000/api/health
```

Notes:

- Prometheus, Loki, and Grafana bind to `127.0.0.1` by default. To reach them through WireGuard instead of SSH tunneling, set `ALLOW_MONITORING_OVER_WIREGUARD=true` in `.env` before running `hardening.sh` and starting the stack. The wrapper script applies this automatically; with the direct `docker compose` command, export `MONITORING_BIND_ADDRESS=10.8.0.1` first.
- Grafana provisions the Prometheus and Loki data sources from `cloud/monitoring/grafana/provisioning/datasources/datasources.yml`.

To access the web UIs through SSH tunneling from your local machine:

> The addresses below assume `ALLOW_MONITORING_OVER_WIREGUARD=true` (`MONITORING_BIND_ADDRESS=10.8.0.1`).
> If your stack binds to `127.0.0.1` instead, replace `10.8.0.1` with `127.0.0.1` in the cloud `-L` flags.

```bash
# -N keeps the tunnel open without opening a shell
ssh -i <your-key.pem> -N \
  -L 3000:10.8.0.1:3000 \
  -L 9090:10.8.0.1:9090 \
  -L 3100:10.8.0.1:3100 \
  -L 9100:10.8.0.1:9100 \
  -L 12345:10.8.0.2:12345 \
  ec2-user@<elastic-ip>
```

Then open:

- Grafana: `http://127.0.0.1:3000`
- Prometheus: `http://127.0.0.1:9090`
- Loki readiness: `http://127.0.0.1:3100/ready`
- Node Exporter (cloud): `http://127.0.0.1:9100/metrics`
- Alloy UI (edge): `http://127.0.0.1:12345`

> **Alloy UI prerequisite:** `install-alloy.sh` sets `CUSTOM_ARGS="--server.http.listen-addr=0.0.0.0:12345"` so
> the UI is reachable over WireGuard. Also open the port on the edge UFW (one-time):
> `sudo ufw allow in on wg0 to any port 12345 proto tcp`

## 8. Prepare the Edge Node

On the edge device:

```bash
set -a && . ./.env && set +a
cd edge/5g-wwan
sudo -E ./install.sh
```

If you use the Docker-based WWAN mode:

```bash
set -a && . ./.env && set +a
cd edge/5g-wwan/docker
sudo -E docker compose up -d
```

Check WWAN state:

```bash
ip addr
systemctl status wwan.service
systemctl status wwan-monitor.service
```

The edge installer also provisions:

- `curl`, `rsync`, `iperf3`, `git`, `tmux`, `stow`, `vim`, `wget`, `docker`, and Docker Compose v2
- `ufw` on apt-based edge systems, and on dnf-based edge systems when the package exists in the enabled repositories

## 9. Join the VPN Network

Requirements:

- You can SSH to the cloud node
- You have the cloud server public key from `/etc/wireguard/server_public.key`

Run the client setup on the edge node:

```bash
set -a && . ./.env && set +a
sudo -E ./edge/vpn/setup-wg-client.sh
```

Recommended answers:

- `Server endpoint IP/Domain`: the EC2 Elastic IP or public DNS name
- `Server port`: `51820`
- `Server public key`: output of `sudo cat /etc/wireguard/server_public.key`
- `Client IP`: a unique `/32`, for example `10.8.0.3/32` if `10.8.0.2/32` is already occupied by the bootstrap sample peer
- `Allowed IPs`: `10.8.0.0/24`

The client script will print the client public key. Add that peer manually on the cloud node:

```bash
sudo wg set wg0 peer <client-public-key> allowed-ips 10.8.0.3/32
sudo wg-quick save wg0
```

Verify from the cloud node:

```bash
sudo wg show
```

If you need to remove the local WireGuard client setup from the edge node later:

```bash
sudo -E ./edge/vpn/uninstall-wg-client.sh
```

To remove the local key pair too:

```bash
sudo -E REMOVE_WG_KEYS=true ./edge/vpn/uninstall-wg-client.sh
```

This only removes the local edge setup. Remove the peer on the cloud server separately if it was previously registered.

## 10. Harden the Edge Node

Now that the edge node is connected to the VPN, secure it and install Node Exporter:

```bash
set -a && . ./.env && set +a
sudo -E ./shared/scripts/hardening.sh
sudo -E ./shared/scripts/install-node-exporter.sh
```

If the edge node does not have an `authorized_keys` file yet, the script will **skip SSH hardening** and print a warning:

```
[WARN] No authorized_keys file found. Skipping SSH hardening (password login remains enabled).
[WARN] Run this script again after setting up SSH key authentication.
```

Firewall (UFW) and Fail2Ban are still configured normally. Password-based SSH login remains enabled until you complete the next step.

### 10.1. Set Up SSH Key Authentication and Re-Harden

To complete SSH hardening, set up key-based authentication first.

If you are already connected to the edge node via password-based SSH, keep that session open as a safety net throughout this process.

**On your local machine**, copy your public key to the edge node:

```bash
ssh-copy-id <user>@<edge-ip>
```

Or manually — get your public key on the local machine:

```bash
cat ~/.ssh/id_ed25519.pub
```

Then paste it on the edge node (in your existing SSH session):

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "ssh-ed25519 AAAA..." >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

If you do not have an SSH key pair yet, generate one first on your local machine:

```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
```

**Verify key-based login works** by opening a **new terminal** (keep the old session open):

```bash
ssh -o PasswordAuthentication=no <user>@<edge-ip>
```

Once key-based login is confirmed, re-run the hardening script to disable password authentication:

```bash
set -a && . ./.env && set +a
sudo -E ./shared/scripts/hardening.sh
```

Verify Node Exporter on the edge host:

```bash
sudo systemctl status node_exporter --no-pager
curl http://127.0.0.1:9100/metrics | head
```

## 11. Edge Log Forwarding with Alloy

Run Alloy on the edge node after the WireGuard tunnel can reach the cloud overlay address.
The default Alloy config reads journald and pushes logs to Loki at `http://10.8.0.1:3100/loki/api/v1/push`.
For this default endpoint to work, you must have started the cloud monitoring stack with `MONITORING_BIND_ADDRESS=10.8.0.1` and allowed monitoring over WireGuard in `hardening.sh`.

> [!WARNING]
> **Edge Time Synchronization Required!**  
> Since embedded ARM SBCs (like Orange Pi) do not have a hardware RTC battery, their clock can be completely wrong (e.g. out of sync by days) after a reboot or power loss. Loki automatically rejects logs that are too far behind the active ingestion window, and Grafana will hide them from current time queries.
>
> **Always verify and sync the Edge clock before running Alloy:**
>
> ```bash
> date
> # Sync using NTP if it's incorrect:
> sudo timedatectl set-ntp true
> sudo systemctl restart systemd-timesyncd
> # Or set manually:
> sudo date -s "2026-05-18 00:20:00"
> ```

```bash
set -a && . ./.env && set +a
sudo -E ./edge/observability/alloy/install-alloy.sh
```

Override the push endpoint if your cloud WireGuard IP or Loki port differs:

```bash
sudo -E ALLOY_LOKI_URL=http://10.8.0.1:3100/loki/api/v1/push ./edge/observability/alloy/install-alloy.sh
```

Verify Alloy:

```bash
sudo systemctl status alloy --no-pager
sudo journalctl -u alloy --no-pager

# Confirm Alloy UI is listening on all interfaces
ss -lntp | grep 12345

# Quick local check
curl http://127.0.0.1:12345
```

### Accessing the Alloy Web UI

Alloy exposes a pipeline graph and component status UI on port `12345`.
`install-alloy.sh` configures `CUSTOM_ARGS="--server.http.listen-addr=0.0.0.0:12345"` so the UI
is reachable from the WireGuard overlay.

Before using the SSH tunnel, open the port on the edge UFW (one-time):

```bash
sudo ufw allow in on wg0 to any port 12345 proto tcp
```

Then from your local machine, add the Alloy line to the SSH tunnel:

```bash
ssh -i <your-key.pem> -N \
  -L 12345:10.8.0.2:12345 \
  ec2-user@<elastic-ip>
```

Open `http://127.0.0.1:12345` in a browser. The UI shows:

- **Graph** — live pipeline component graph
- **Components** — status of `loki.source.journal`, `loki.write.cloud`, etc.

In Grafana, open Explore and select the provisioned `Loki` data source.
A useful first query is:

```logql
{job="edge-journal"}
```

## 12. Validate End-to-End Connectivity

From the edge node:

```bash
sudo wg show
ping -c 3 10.8.0.1
ssh ec2-user@10.8.0.1
```

From the cloud node:

```bash
sudo wg show
ping -c 3 10.8.0.3
curl http://10.8.0.3:9100/metrics
```

Expected results:

- WireGuard handshake is present on both sides
- The cloud node reaches the edge node over the overlay address
- Prometheus can scrape Node Exporter from the edge node over the overlay network

## 13. Quick Troubleshooting

Useful checks on the cloud node:

```bash
sudo journalctl -u wg-quick@wg0 -f
sudo wg show
sudo systemctl status docker --no-pager
sudo docker ps
sudo systemctl status node_exporter --no-pager
curl http://127.0.0.1:9100/metrics | head
curl http://127.0.0.1:3100/ready
```

Useful checks on the edge node:

```bash
sudo journalctl -u wwan.service -u wwan-monitor.service -f
sudo journalctl -u alloy -f
sudo wg show
ip addr
```

Common causes of failure:

- Reusing `10.8.0.2/32` while the bootstrap sample peer still exists
- Starting Alloy before Loki is reachable at `ALLOY_LOKI_URL`
- Changing `ALLOW_MONITORING_OVER_WIREGUARD` in `.env` without restarting the Docker stack

### Loki not reachable on `10.8.0.1:3100`

**Symptom:** `curl http://10.8.0.1:3100/ready` fails but `curl http://127.0.0.1:3100/ready` succeeds.

**Cause:** The monitoring containers are still bound to `127.0.0.1` from a previous run. The new `MONITORING_BIND_ADDRESS` value only takes effect after the stack is restarted.

Check which address Loki is actually bound to:

```bash
sudo ss -lntp | grep 3100
```

Fix — restart the stack so Docker picks up the updated bind address:

```bash
cd cloud/monitoring
sudo -E docker compose --env-file ../../.env down
sudo -E docker compose --env-file ../../.env up -d --force-recreate
curl http://10.8.0.1:3100/ready
```

### Alloy crash loop — corrupted positions file

**Symptom:** `alloy.service` enters a crash loop (`Start request repeated too quickly`) with this error in the journal:

```
invalid yaml positions file [.../loki.source.journal.system/positions.yml]: yaml: control characters are not allowed
```

**Cause:** Alloy's journal read-position tracking file got corrupted (contains binary/control characters). Alloy cannot start until the file is removed; it will recreate it cleanly on the next start.

Fix on the edge node:

```bash
sudo rm /var/lib/alloy/data/loki.source.journal.system/positions.yml
sudo systemctl reset-failed alloy
sudo systemctl start alloy
sudo systemctl status alloy --no-pager
sudo journalctl -u alloy -n 20 --no-pager
```

After recovery, Alloy replays up to `max_age` (default `1h`) of journald entries and begins forwarding to Loki.

### Clearing "Ghost" Jobs in Grafana & Prometheus (No Data / N/A showing on Gauges)

If you change a `job_name` in `prometheus.yml` (e.g. from `cloud-gateway` to `cloud-node`), the old name will still appear in Grafana dropdowns for 15 days, causing "N/A" values if selected. To wipe the old data immediately:

```bash
cd cloud/monitoring
set -a && source ../../.env && set +a
sudo docker compose stop prometheus
sudo docker compose rm -f prometheus
sudo docker volume rm monitoring_prometheus_data
sudo docker compose up -d
```
*(Similarly, if a provisioned dashboard is stuck in Grafana, stop grafana, remove `monitoring_grafana_data` volume or delete `/var/lib/grafana/grafana.db`, and restart).*

### Testing SWAP and CPU Load via `stress-ng` on Edge Nodes

To verify the dashboard metrics spike correctly under heavy load, install and run `stress-ng`:

```bash
sudo apt update && sudo apt install stress-ng -y
# Spike CPU (100% on 4 cores for 60s)
stress-ng --cpu 4 --timeout 60s
# Spike RAM and Force SWAP (allocate 120% of RAM, respawn if OOM killed, for 300s)
stress-ng --vm 4 --vm-bytes 120% --vm-keep --oomable --timeout 300s
```
