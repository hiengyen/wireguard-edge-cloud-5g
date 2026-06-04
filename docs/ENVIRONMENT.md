# Environment Files

This project has one full reference file and four role-specific environment templates.

Use the role-specific files for real deployments. Keep [`.env.example`](../.env.example) as the complete inventory/reference.

| Template | Copy To | Use For |
|----------|---------|---------|
| [`.env.cloud.example`](../.env.cloud.example) | `.env.cloud` | Terraform, cloud monitoring, cloud hardening, PeerSight cloud |
| [`.env.edge.example`](../.env.edge.example) | `.env.edge` | Edge WireGuard, WWAN, Alloy, PeerSight agent |
| [`.env.benchmark.example`](../.env.benchmark.example) | `.env.benchmark` | Benchmark targets, service URLs, thresholds |
| [`.env.peersight-local.example`](../.env.peersight-local.example) | `.env.peersight-local` | Local PeerSight API/app/agent/broker development |

The real files are ignored by Git. Do not put real passwords, private paths, tokens, or public IP allowlists into `*.example` files.

## Load Pattern

Load only the file needed by the component you are running:

```bash
set -a
. ./.env.cloud
set +a
```

For commands executed with `sudo`, preserve the loaded variables:

```bash
sudo -E bash shared/scripts/hardening.sh
```

For Docker Compose, pass the matching env file explicitly:

```bash
cd cloud/monitoring
sudo -E docker compose --env-file ../../.env.cloud up -d --force-recreate
```

## Cloud Deployment

```bash
cp .env.cloud.example .env.cloud
nano .env.cloud
set -a && . ./.env.cloud && set +a

cd cloud/terraform/ec2
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Cloud monitoring:

```bash
set -a && . ./.env.cloud && set +a
sudo -E bash shared/scripts/hardening.sh

cd cloud/monitoring
sudo -E docker compose --env-file ../../.env.cloud up -d --force-recreate
```

PeerSight cloud:

```bash
set -a && . ./.env.cloud && set +a
sudo -E bash peersight/deploy-cloud.sh
```

## Edge Deployment

```bash
cp .env.edge.example .env.edge
nano .env.edge
set -a && . ./.env.edge && set +a

sudo -E bash edge/5g-wwan/install.sh
sudo -E bash edge/vpn/setup-wg-client.sh
sudo -E bash edge/observability/alloy/install-alloy.sh
```

PeerSight edge agent:

```bash
set -a && . ./.env.edge && set +a
sudo -E bash peersight/deploy-edge.sh
```

Each edge node must use its own `WG_CLIENT_IP`, `PEERSIGHT_HOST_ID`, and `PEERSIGHT_TOKEN`.

## Benchmark

```bash
cp .env.benchmark.example .env.benchmark
nano .env.benchmark
set -a && . ./.env.benchmark && set +a

bash benchmark/run_all.sh
```

Root-required benchmark suites need `sudo -E`:

```bash
sudo -E bash benchmark/run_all.sh --allow-destructive
```

## PeerSight Local Development

```bash
cp .env.peersight-local.example .env.peersight-local
nano .env.peersight-local
set -a && . ./.env.peersight-local && set +a
```

Use this only for local development outside the cloud Docker deployment.

---

# Các File Môi Trường

Dự án có một file tham chiếu đầy đủ và bốn template theo vai trò.

Nên dùng các file theo vai trò khi triển khai thật. Giữ [`.env.example`](../.env.example) làm danh sách tham chiếu tổng hợp.

| Template | Copy Thành | Dùng Cho |
|----------|------------|----------|
| [`.env.cloud.example`](../.env.cloud.example) | `.env.cloud` | Terraform, monitoring cloud, hardening cloud, PeerSight cloud |
| [`.env.edge.example`](../.env.edge.example) | `.env.edge` | WireGuard edge, WWAN, Alloy, PeerSight agent |
| [`.env.benchmark.example`](../.env.benchmark.example) | `.env.benchmark` | Target, URL dịch vụ và ngưỡng benchmark |
| [`.env.peersight-local.example`](../.env.peersight-local.example) | `.env.peersight-local` | Phát triển PeerSight local |

Các file thật đã được Git ignore. Không ghi mật khẩu, token, đường dẫn private key thật, hoặc CIDR public IP thật vào file `*.example`.

## Cách Nạp

Chỉ nạp file cần cho thành phần đang chạy:

```bash
set -a
. ./.env.cloud
set +a
```

Với lệnh chạy qua `sudo`, dùng `sudo -E`:

```bash
sudo -E bash shared/scripts/hardening.sh
```

Với Docker Compose, truyền env file tương ứng:

```bash
cd cloud/monitoring
sudo -E docker compose --env-file ../../.env.cloud up -d --force-recreate
```

## Triển Khai Cloud

```bash
cp .env.cloud.example .env.cloud
nano .env.cloud
set -a && . ./.env.cloud && set +a

cd cloud/terraform/ec2
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Monitoring cloud:

```bash
set -a && . ./.env.cloud && set +a
sudo -E bash shared/scripts/hardening.sh

cd cloud/monitoring
sudo -E docker compose --env-file ../../.env.cloud up -d --force-recreate
```

PeerSight cloud:

```bash
set -a && . ./.env.cloud && set +a
sudo -E bash peersight/deploy-cloud.sh
```

## Triển Khai Edge

```bash
cp .env.edge.example .env.edge
nano .env.edge
set -a && . ./.env.edge && set +a

sudo -E bash edge/5g-wwan/install.sh
sudo -E bash edge/vpn/setup-wg-client.sh
sudo -E bash edge/observability/alloy/install-alloy.sh
```

PeerSight edge agent:

```bash
set -a && . ./.env.edge && set +a
sudo -E bash peersight/deploy-edge.sh
```

Mỗi edge node phải có `WG_CLIENT_IP`, `PEERSIGHT_HOST_ID`, và `PEERSIGHT_TOKEN` riêng.

## Benchmark

```bash
cp .env.benchmark.example .env.benchmark
nano .env.benchmark
set -a && . ./.env.benchmark && set +a

bash benchmark/run_all.sh
```

Các suite cần quyền root phải chạy với `sudo -E`:

```bash
sudo -E bash benchmark/run_all.sh --allow-destructive
```

## Phát Triển PeerSight Local

```bash
cp .env.peersight-local.example .env.peersight-local
nano .env.peersight-local
set -a && . ./.env.peersight-local && set +a
```

Chỉ dùng file này khi phát triển local ngoài Docker deployment trên cloud.
