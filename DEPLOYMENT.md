# Deployment Guide

This document describes the recommended deployment workflow for the `wireguard-edge-cloud-5g` project in a production-oriented setup.

The repository assumes:
- WireGuard overlay network: `10.8.0.0/24`
- WireGuard server interface: `10.8.0.1/24`
- Each edge node uses a unique `/32` client address, for example `10.8.0.2/32`
- Registration API is disabled by default and should only be exposed behind TLS and restricted CIDR rules

## 1. Prerequisites

Prepare the following before deployment:
- An AWS account with permission to create EC2, IAM, EIP, Security Group, and Secrets Manager resources
- An existing AWS EC2 key pair for SSH access
- A public subnet and VPC where the EC2 instance will run
- A DNS record for the registration API, for example `vpn-api.example.com`
- An edge device with:
  - Linux
  - WireGuard support
  - Quectel-compatible WWAN/QMI stack if using the 5G automation scripts

Install locally:
- `terraform >= 1.9`
- `docker` and `docker compose` or `docker-compose`
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
- `TF_VAR_wg_api_token`
- `TF_VAR_grafana_admin_password`
- `TF_VAR_admin_ssh_cidr`
- `TF_VAR_enable_registration_api`
- `TF_VAR_wg_api_cidr`
- `TF_VAR_registration_api_domain`
- `TF_VAR_wireguard_network`
- `TF_VAR_wireguard_client_cidr`
- `GRAFANA_ADMIN_PASSWORD`

Recommended values:
- `TF_VAR_wireguard_network=10.8.0.0/24`
- `TF_VAR_wireguard_client_cidr=10.8.0.2/32`
- `TF_VAR_enable_registration_api=false` until DNS and access policy are ready
- `TF_VAR_admin_ssh_cidr='["<your-public-ip>/32"]'`
- `TF_VAR_wg_api_cidr=<trusted-edge-egress-ip>/32`

## 3. Configure Terraform Inputs

Review [cloud/terraform/ec2/terraform.tfvars.example](/home/hiengyen/CODE/wireguard-edge-cloud-5g/cloud/terraform/ec2/terraform.tfvars.example:1) and provide the required values either through:
- exported `TF_VAR_*` environment variables from `.env`
- or a local non-committed `terraform.tfvars`

Required infrastructure values:
- `vpc_id`
- `subnet_id`
- `key_name`
- optionally `instance_type`

## 4. Provision the Cloud Node

Run:

```bash
set -a && . ./.env && set +a
cd cloud/terraform/ec2
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Capture the outputs:
- EC2 public IP
- WireGuard endpoint
- Security group ID
- registration API endpoint, if enabled

What Terraform sets up:
- Amazon Linux 2023 EC2 instance
- encrypted root volume
- Elastic IP
- IAM role for Secrets Manager access
- WireGuard server bootstrap
- registration API application bound to `127.0.0.1`
- optional TLS reverse proxy with NGINX

## 5. Configure DNS for the Registration API

If you want to use auto-registration:

1. Set `TF_VAR_enable_registration_api=true`
2. Set `TF_VAR_registration_api_domain` to your real DNS name
3. Point that DNS record to the EC2 Elastic IP
4. Restrict `TF_VAR_wg_api_cidr` to the known edge egress IP or another trusted CIDR
5. Re-apply Terraform if needed

Current bootstrap behavior:
- NGINX terminates TLS on the public port
- the backend registration API listens only on `127.0.0.1:${TF_VAR_wg_api_port:-5000}`
- the generated certificate is self-signed

Production note:
- replace the bootstrap self-signed certificate with a trusted certificate before public use

## 6. Verify the Cloud Node

SSH to the instance:

```bash
ssh -i <your-key.pem> ec2-user@<elastic-ip>
```

Check services:

```bash
sudo systemctl status wg-quick@wg0
sudo systemctl status wg-api
sudo systemctl status nginx
```

Check WireGuard:

```bash
sudo wg show
sudo cat /etc/wireguard/wg0.conf
```

Check the API listener:

```bash
sudo ss -lntp | grep -E '5000|443'
```

Expected behavior:
- `wg0` is active
- `wg-api` is active and bound to localhost
- `nginx` is active only if registration API exposure is enabled

## 7. Start Monitoring on the Cloud Node

On the cloud host:

```bash
set -a && . ./.env && set +a
cd cloud/monitoring
sudo docker-compose up -d
```

Verify:

```bash
sudo docker ps
curl http://127.0.0.1:9090/-/healthy
curl http://127.0.0.1:3000/api/health
```

Notes:
- Prometheus and Grafana bind to `127.0.0.1` by default in this repository
- Use SSH tunnel or a separate reverse proxy if you need remote operator access

## 8. Prepare the Edge Node

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
sudo docker-compose up -d
```

Check WWAN state:

```bash
ip addr
systemctl status wwan.service
systemctl status wwan-monitor.service
```

## 9. Join the Edge Node to WireGuard

Run the client setup:

```bash
set -a && . ./.env && set +a
sudo ./edge/vpn/setup-wg-client.sh
```

Recommended client values:
- Client IP: `10.8.0.2/32`
- Allowed IPs: `10.8.0.0/24`
- API scheme: `https`

If auto-registration is disabled:
- enter the server public key manually
- configure the client
- add the peer manually on the server

If auto-registration is enabled:
- use the TLS domain, not the raw IP
- provide the registration token from your secure deployment inputs

## 10. Manual Peer Registration

If you do not use the registration API, add a peer manually on the server:

```bash
sudo wg set wg0 peer <client-public-key> allowed-ips 10.8.0.2/32
sudo wg-quick save wg0
```

The server-side peer must use a unique `/32` address for each edge node.

## 11. Validate End-to-End Connectivity

From the edge node:

```bash
sudo wg show
ping -c 3 10.8.0.1
```

From the cloud node:

```bash
sudo wg show
ping -c 3 10.8.0.2
curl http://10.8.0.2:9100/metrics
```

Expected results:
- WireGuard handshake is present on both sides
- the cloud node reaches the edge node via `10.8.0.2`
- Prometheus can scrape Node Exporter over the overlay network

## 12. Apply Shared Hardening

Run on both cloud and edge nodes:

```bash
set -a && . ./.env && set +a
sudo ./shared/scripts/hardening.sh
sudo ./shared/scripts/install-node-exporter.sh
```

Use `SSH_ADMIN_PORT` or `WIREGUARD_PORT` from `.env` if you need non-default ports.

Before running hardening:
- confirm that SSH key-based access works
- confirm that your admin CIDR is correct

## 13. Post-Deployment Checklist

Verify all of the following:
- EC2 has the expected Elastic IP
- DNS for `registration_api_domain` resolves correctly
- the registration API is disabled unless explicitly needed
- if enabled, API access is restricted to trusted CIDRs
- TLS is active on the public registration endpoint
- the self-signed TLS bootstrap certificate has been replaced for production
- `wg0` is active on server and edge
- each peer has a unique `/32` address
- Grafana admin password is not default
- monitoring is only reachable through trusted access paths

## 14. Scaling to More Edge Nodes

For each additional node:
- assign a new `/32` client address
- example: `10.8.0.3/32`, `10.8.0.4/32`, `10.8.0.5/32`
- keep client-side `AllowedIPs = 10.8.0.0/24` unless you want full-tunnel routing
- register or add peers on the server with unique `/32` `AllowedIPs`

Example:

```ini
[Peer]
PublicKey = <edge-2-pubkey>
AllowedIPs = 10.8.0.3/32
```

Do not assign the same `/32` to multiple peers.

## 15. Operational Recommendations

Recommended next steps for a real production rollout:
- replace the self-signed NGINX certificate with a trusted certificate
- put the registration API behind an audited DNS/TLS setup
- rotate the registration token and WireGuard keys on a schedule
- maintain an inventory of edge node names mapped to peer IPs
