# Deployment Guide

This document describes the recommended deployment workflow for the `wireguard-edge-cloud-5g` project in a production-oriented setup.
For a compact command reference, see [COMMANDS.md](/home/hiengyen/CODE/wireguard-edge-cloud-5g/COMMANDS.md:1).

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

## 6. Start Monitoring on the Cloud Node

On the cloud host:

```bash
set -a && . ./.env && set +a
cd cloud/monitoring
sudo docker compose up -d
```

Verify:

```bash
sudo docker ps
curl http://127.0.0.1:9090/-/healthy
curl http://127.0.0.1:3100/ready
curl http://127.0.0.1:3000/api/health
```

Notes:
- Prometheus, Loki, and Grafana bind to `127.0.0.1` by default in this repository
- To reach them through WireGuard, set `MONITORING_BIND_ADDRESS=10.8.0.1` before starting the stack
- Use SSH tunnel or a separate reverse proxy if you need remote operator access
- Grafana provisions the Prometheus and Loki data sources from `cloud/monitoring/grafana/provisioning/datasources/datasources.yml`
- The repository currently pins Prometheus `v3.11.2`, Grafana `13.0.1`, and Loki `3.7.0`
- AWS Security Groups do not need additional `3000/tcp`, `9090/tcp`, or `3100/tcp` ingress for WireGuard-only access, because the traffic arrives as encrypted UDP on the WireGuard port and is decrypted locally on the EC2 instance

To access the web UIs through SSH tunneling from your local machine:

```bash
ssh -i <your-key.pem> \
  -L 3000:127.0.0.1:3000 \
  -L 9090:127.0.0.1:9090 \
  -L 3100:127.0.0.1:3100 \
  -L 9100:127.0.0.1:9100 \
  ec2-user@<elastic-ip>
```

Then open:
- Grafana: `http://127.0.0.1:3000`
- Prometheus: `http://127.0.0.1:9090`
- Loki readiness: `http://127.0.0.1:3100/ready`
- Node Exporter metrics: `http://127.0.0.1:9100/metrics`

## 7. Prepare the Edge Node

On the edge device:

```bash
set -a && . ./.env && set +a
cd edge/5g-wwan
sudo ./install.sh
```

If you use the Docker-based WWAN mode:

```bash
set -a && . ./.env && set +a
cd edge/5g-wwan/docker
sudo docker compose up -d
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

## 8. Join the VPN Network

Requirements:
- You can SSH to the cloud node
- You have the cloud server public key from `/etc/wireguard/server_public.key`

Run the client setup on the edge node:

```bash
set -a && . ./.env && set +a
sudo ./edge/vpn/setup-wg-client.sh
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
sudo ./edge/vpn/uninstall-wg-client.sh
```

To remove the local key pair too:

```bash
sudo REMOVE_WG_KEYS=true ./edge/vpn/uninstall-wg-client.sh
```

This only removes the local edge setup. Remove the peer on the cloud server separately if it was previously registered.



## 9. Validate End-to-End Connectivity

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
- Prometheus can scrape Node Exporter over the overlay network

## 10. Edge Log Forwarding with Alloy

Run Alloy on the edge node after the WireGuard tunnel can reach the cloud overlay address.
The default Alloy config reads journald and pushes logs to Loki at `http://10.8.0.1:3100/loki/api/v1/push`.
For this default endpoint to work, start the cloud monitoring stack with `MONITORING_BIND_ADDRESS=10.8.0.1` and allow monitoring over WireGuard in `hardening.sh`.

```bash
set -a && . ./.env && set +a
sudo -E ./edge/observability/alloy/install-alloy.sh
```

Override the push endpoint if your cloud WireGuard IP or Loki port differs:

```bash
sudo ALLOY_LOKI_URL=http://10.8.0.1:3100/loki/api/v1/push ./edge/observability/alloy/install-alloy.sh
```

Verify Alloy:

```bash
sudo systemctl status alloy --no-pager
sudo journalctl -u alloy --no-pager
```

In Grafana, open Explore and select the provisioned `Loki` data source.
A useful first query is:

```logql
{job="edge-journal"}
```

## 11. Shared Hardening and Monitoring Agents

Run the shared scripts on both environments as needed:

```bash
sudo ./shared/scripts/hardening.sh
sudo ./shared/scripts/install-node-exporter.sh
```

To pin or override the Node Exporter version during installation:

```bash
sudo NODE_EXPORTER_VERSION=1.11.1 ./shared/scripts/install-node-exporter.sh
```

Verify Node Exporter on the target host:

```bash
sudo systemctl status node_exporter --no-pager
ss -lntp | grep 9100
curl http://127.0.0.1:9100/metrics | head
```

Operational notes:
- On edge hosts using `ufw`, `hardening.sh` also opens the extra inbound TCP ports listed in `EDGE_EXTRA_TCP_PORTS`, default `443 5201`
- To expose Grafana, Prometheus, Loki, and Node Exporter only through the overlay, set `ALLOW_MONITORING_OVER_WIREGUARD=true` and `WIREGUARD_NETWORK=10.8.0.0/24` before running `hardening.sh`
- The cloud Security Group also allows `ICMPv4` so you can test reachability with `ping`

## 12. Quick Troubleshooting

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
