# Common Commands

This file groups the commands most commonly used while deploying and operating `wireguard-edge-cloud-5g`.

## Environment

```bash
cp .env.example .env
set -a && . ./.env && set +a
```

## Terraform Cloud Provisioning

```bash
cd cloud/terraform/ec2
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output public_ip
terraform output wireguard_endpoint

```

## Cloud Access

```bash
ssh -i <your-key.pem> ec2-user@<EC2_PUBLIC_IP>
```

## Edge WWAN

Native install:

```bash
cd edge/5g-wwan
sudo ./install.sh
sudo systemctl status wwan.service
sudo systemctl status wwan-monitor.service
```

Docker mode:

```bash
cd edge/5g-wwan/docker
sudo docker compose up -d
```

## WireGuard Client Join

```bash
set -a && . ./.env && set +a
sudo ./edge/vpn/setup-wg-client.sh
```

Manual peer registration on the cloud node:

```bash
sudo wg set wg0 peer <client-public-key> allowed-ips 10.8.0.3/32
sudo wg-quick save wg0
sudo wg show
```

Remove the local WireGuard client setup from the edge node:

```bash
sudo ./edge/vpn/uninstall-wg-client.sh
```

Remove the local key pair too:

```bash
sudo REMOVE_WG_KEYS=true ./edge/vpn/uninstall-wg-client.sh
```

## Monitoring Stack

Start monitoring on the cloud node:

```bash
set -a && . ./.env && set +a
cd cloud/monitoring
sudo docker compose up -d
sudo docker ps
curl http://127.0.0.1:9090/-/healthy
curl http://127.0.0.1:3100/ready
curl http://127.0.0.1:3000/api/health
```

Grafana loads Prometheus and Loki from `cloud/monitoring/grafana/provisioning/datasources/datasources.yml`.

Expose Grafana, Prometheus, and Loki through WireGuard only:

```bash
set -a && . ./.env && set +a
export MONITORING_BIND_ADDRESS=10.8.0.1
export ALLOW_MONITORING_OVER_WIREGUARD=true
export WIREGUARD_NETWORK=10.8.0.0/24
sudo -E ./shared/scripts/hardening.sh
cd cloud/monitoring
sudo docker compose down
sudo docker compose up -d
```

## SSH Tunnels For Web UI

Grafana, Prometheus, Loki, and Node Exporter:

```bash
ssh -i <your-key.pem> \
  -L 3000:127.0.0.1:3000 \
  -L 9090:127.0.0.1:9090 \
  -L 3100:127.0.0.1:3100 \
  -L 9100:127.0.0.1:9100 \
  ec2-user@<EC2_PUBLIC_IP>
```

Open locally:
- `http://127.0.0.1:3000`
- `http://127.0.0.1:9090`
- `http://127.0.0.1:3100/ready`
- `http://127.0.0.1:9100/metrics`

## Edge Alloy

Install Alloy on the edge node after WireGuard can reach the cloud overlay address:
the default `ALLOY_LOKI_URL` expects cloud Loki to be reachable at `10.8.0.1:3100`.

```bash
set -a && . ./.env && set +a
sudo -E ./edge/observability/alloy/install-alloy.sh
sudo systemctl status alloy --no-pager
sudo journalctl -u alloy --no-pager
```

Override the Loki push endpoint if the cloud overlay IP or port is different:

```bash
sudo ALLOY_LOKI_URL=http://10.8.0.1:3100/loki/api/v1/push ./edge/observability/alloy/install-alloy.sh
```

Uninstall local Alloy service/config:

```bash
sudo ./edge/observability/alloy/uninstall-alloy.sh
```

## Node Exporter

Install:

```bash
sudo ./shared/scripts/install-node-exporter.sh
```

Install with a specific version:

```bash
sudo NODE_EXPORTER_VERSION=1.11.1 ./shared/scripts/install-node-exporter.sh
```

Verify:

```bash
sudo systemctl status node_exporter --no-pager
ss -lntp | grep 9100
curl http://127.0.0.1:9100/metrics | head
```

Scrape edge metrics from the cloud node:

```bash
curl http://10.8.0.3:9100/metrics | head
```

## Hardening

Default:

```bash
sudo ./shared/scripts/hardening.sh
```

With custom WireGuard port:

```bash
sudo WIREGUARD_PORT=51821 ./shared/scripts/hardening.sh
```

With monitoring access over WireGuard:

```bash
sudo ALLOW_MONITORING_OVER_WIREGUARD=true WIREGUARD_NETWORK=10.8.0.0/24 ./shared/scripts/hardening.sh
```

With custom extra edge TCP ports:

```bash
sudo EDGE_EXTRA_TCP_PORTS='443 5201' ./shared/scripts/hardening.sh
```

## File Transfer Tests

Create a sample dataset:

```bash
mkdir -p ~/dataset/sample-set
fallocate -l 1G ~/dataset/sample-set/blob-1g.bin
for i in $(seq 1 100); do
  head -c 1048576 /dev/urandom > ~/dataset/sample-set/file-${i}.bin
done
du -sh ~/dataset/sample-set
```

Rsync over WireGuard:

```bash
rsync -avhP --partial --append-verify \
  ~/dataset/sample-set/ \
  ec2-user@10.8.0.1:/home/ec2-user/dataset/sample-set/
```

Quick SCP test:

```bash
echo "wireguard test $(date -Iseconds)" > /tmp/wg-test.txt
scp /tmp/wg-test.txt ec2-user@10.8.0.1:/tmp/
ssh ec2-user@10.8.0.1 'cat /tmp/wg-test.txt'
```

## Troubleshooting

Cloud:

```bash
sudo journalctl -u wg-quick@wg0 -f
sudo wg show
sudo systemctl status docker --no-pager
sudo docker ps
sudo systemctl status node_exporter --no-pager
curl http://127.0.0.1:9100/metrics | head
curl http://127.0.0.1:3100/ready
```

Edge:

```bash
sudo journalctl -u wwan.service -u wwan-monitor.service -f
sudo journalctl -u alloy -f
sudo wg show
ip addr
```
