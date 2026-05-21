# peersight

**🇬🇧 [English](#english) | 🇻🇳 [Tiếng Việt](#tiếng-việt)**

---

<a id="english"></a>

## 🇬🇧 English

**WireGuard Monitoring & Orchestration Tracker** — a platform for deploying, managing, and monitoring WireGuard VPN networks at scale.

### Architecture

```
┌──────────────┐       ┌──────────────┐       ┌──────────────┐
│  peersight-app│       │ peersight-api │       │  PostgreSQL  │
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

### Modules

| Module | Language | Description |
|---|---|---|
| `peersight-api` | Go (Gin) | Central REST API — manages DB, authenticates agents and users |
| `peersight-app` | Vue.js 3 | Admin dashboard for managing hosts, peers, and alerts |
| `peersight-agent` | Go | Daemon on each WireGuard host — syncs state with the API |
| `peersight-broker` | Go | Pulls events from the API, pushes to SIEM (syslog / file) |

### Quick Start

#### Prerequisites

- Go 1.22+
- Docker & Docker Compose v2
- Node.js 18+ (for app development)

#### Run with Docker Compose

```bash
cp .env.example .env
# Edit .env with your values
docker compose up -d
```

This starts PostgreSQL, the API server, and the App UI:

- **API**: http://localhost:4000
- **App UI**: http://localhost:5173
- **Health**: http://localhost:4000/health

#### Build from Source

```bash
make all     # Build all 3 Go binaries
make app     # Build the Vue.js frontend
make test    # Run all unit tests
```

Or build each module individually:

```bash
cd peersight-api   && go build -o peersight-api   ./cmd/api
cd peersight-agent && go build -o peersight-agent ./cmd/agent
cd peersight-broker && go build -o peersight-broker ./cmd/broker
```

### Configuration

#### API Server

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | `postgres://peersight:peersight@localhost:5432/peersight?sslmode=disable` | PostgreSQL connection string |
| `JWT_SECRET` | `change-me-in-production` | JWT signing key (required in production) |
| `PORT` | `4000` | HTTP listen port |
| `ENV` | `development` | `development` or `production` |
| `ALLOWED_ORIGINS` | `http://localhost:5173` | CORS allowed origins |

#### Agent

| Variable | Default | Description |
|---|---|---|
| `PEERSIGHT_API_URL` | — | API server URL |
| `PEERSIGHT_HOST_ID` | — | UUID of this host in the API |
| `PEERSIGHT_TOKEN` | — | JWT token for authentication |
| `PEERSIGHT_LOOP_INTERVAL` | `30` | Seconds between heartbeats |
| `PEERSIGHT_READ_ONLY` | `false` | Report only, do not execute changes |
| `PEERSIGHT_REDACT_SECRETS` | `false` | Strip private keys before sending |
| `PEERSIGHT_WG_BINARY` | `wg` | Path to WireGuard CLI |
| `PEERSIGHT_UNMANAGED_INTERFACES` | — | Comma-separated interfaces to skip |

#### Broker

| Variable | Default | Description |
|---|---|---|
| `PEERSIGHT_API_URL` | — | API server URL |
| `PEERSIGHT_BROKER_ID` | — | Broker identifier |
| `PEERSIGHT_TOKEN` | — | JWT token for authentication |
| `PEERSIGHT_LOOP_INTERVAL` | `30` | Seconds between polls |
| `PEERSIGHT_PIPE_1_TO` | `file` | Pipe destination: `file` or `syslog` |
| `PEERSIGHT_PIPE_1_FROM` | `alerts` | Event types to subscribe (comma-separated) |
| `PEERSIGHT_PIPE_1_FILE` | `/var/log/peersight/events.jsonl` | Output file path |

See [.env.example](.env.example) for the full list of variables.

### API Endpoints

#### Public (no auth)
- `GET /health` — Health check (uptime, db stats)
- `GET /version` — API version info
- `POST /sessions` — Login (email + password → JWT access/refresh tokens)
- `POST /sessions/refresh` — Refresh access token
- `POST /accounts/signup` — Create a new account (default: operator)

#### Hosts (auth required)
- `GET /hosts` — List all hosts
- `GET /hosts/:id` — Get host details
- `GET /hosts/:id/interfaces` — List interfaces per host
- `GET /hosts/:id/endpoints` — List endpoints per host
- `GET /hosts/:id/changes` — List desired changes

#### Agent (agent auth required)
- `POST /hosts/:host_id/ping/:version` — Agent heartbeat

#### Peers (auth required)
- `GET /peers` — List all peers

#### Alerts & Events (auth required)
- `GET /alerts` — List alerts
- `POST /alerts/:id/resolve` — Resolve an alert
- `GET /events/stream` — SSE realtime events (token via query)

#### Queues (auth required, used by broker)
- `POST /queues/:type/next` — Poll next batch of events
- `POST /queues/:type/ack` — Ack processed events

#### Admin (RequireAdmin middleware)
- `POST /admin/users` — Create user with any role
- `DELETE /peers/:id` — Remove a peer
- `POST /hosts/:id/changes` — Push a desired change to a host

### Data Flow

1. **Admin** uses the App UI to configure a new peer
2. **API** stores the config as a `DesiredChange` in PostgreSQL
3. **Agent** sends a heartbeat via `POST /hosts/:id/ping/:version`
4. **API** responds with the pending `DesiredChange`
5. **Agent** executes `wg set` on the local machine and reports the result
6. **API** records the change and generates an alert event
7. **Broker** polls `POST /queues/alerts/next` and receives the event
8. **Broker** writes to syslog or a JSON Lines file for SIEM

### Project Structure

```
peersight/
├── .env.example / .gitignore / Makefile / docker-compose.yml
├── peersight-api/          # Go backend (Gin + pgx + JWT)
│   ├── cmd/api/main.go
│   ├── internal/{config, models, repository, middleware, handlers}
│   └── migrations/001_init.sql
├── peersight-agent/        # Go daemon (WireGuard sync)
│   ├── cmd/agent/main.go
│   └── internal/{config, wg, api, agent}
├── peersight-broker/       # Go daemon (SIEM bridge)
│   ├── cmd/broker/main.go
│   └── internal/{config, api, pipe, broker}
└── peersight-app/          # Vue.js 3 frontend
    ├── src/{pages, components, stores, plugins, styles}
    ├── nginx.conf
    └── Dockerfile
```

### License

MIT

---

<a id="tiếng-việt"></a>

## 🇻🇳 Tiếng Việt

**WireGuard Monitoring & Orchestration Tracker** — nền tảng triển khai, quản lý và giám sát mạng VPN WireGuard ở quy mô lớn.

Đây là phiên bản viết lại bằng Go, lấy cảm hứng từ kiến trúc [Procustodibus](https://www.procustodibus.com/), thay thế Python (Agent/Broker) và Elixir (API) bằng Go cho toàn bộ backend.

### Kiến Trúc

```
┌──────────────┐       ┌──────────────┐       ┌──────────────┐
│  peersight-app│       │ peersight-api │       │  PostgreSQL  │
│  (Vue.js 3)  │◄─────►│   (Go/Gin)   │◄─────►│  Cơ sở DL   │
│  Cổng: 5173  │  HTTP │  Cổng: 4000  │  SQL  │  Cổng: 5432  │
└──────────────┘       └──────┬───────┘       └──────────────┘
                              │ REST
            ┌─────────────────┼─────────────────┐
            ▼                 ▼                 ▼
   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
   │peersight-agent│  │peersight-agent│  │peersight-broker│
   │ (Go daemon)  │  │ (Go daemon)  │  │ (Go daemon)   │
   │  Máy chủ A   │  │  Máy chủ B   │  │  Cầu nối SIEM │
   └──────────────┘  └──────────────┘  └───────┬───────┘
         │                  │                   │
    ┌────┴────┐        ┌────┴────┐         ┌───┴────┐
    │WireGuard│        │WireGuard│         │Syslog/ │
    │  Kernel │        │  Kernel │         │  File  │
    └─────────┘        └─────────┘         └────────┘
```

### Các Module

| Module | Ngôn ngữ | Mô tả |
|---|---|---|
| `peersight-api` | Go (Gin) | API REST trung tâm — quản lý DB, xác thực agent và người dùng |
| `peersight-app` | Vue.js 3 | Bảng điều khiển quản trị: hosts, peers, cảnh báo |
| `peersight-agent` | Go | Daemon trên mỗi máy WireGuard — đồng bộ trạng thái với API |
| `peersight-broker` | Go | Kéo sự kiện từ API, đẩy sang SIEM (syslog / file) |

### Bắt Đầu Nhanh

#### Yêu cầu

- Go 1.22+
- Docker & Docker Compose v2
- Node.js 18+ (cho phát triển giao diện)

#### Chạy bằng Docker Compose

```bash
cp .env.example .env
# Chỉnh sửa .env với giá trị thực tế
docker compose up -d
```

Lệnh này khởi động PostgreSQL, API server, và giao diện App:

- **API**: http://localhost:4000
- **Giao diện**: http://localhost:5173
- **Kiểm tra sức khỏe**: http://localhost:4000/health

#### Build từ mã nguồn

```bash
make all     # Build cả 3 file nhị phân Go
make app     # Build giao diện Vue.js
make test    # Chạy tất cả unit test
```

Hoặc từng module riêng lẻ:

```bash
cd peersight-api   && go build -o peersight-api   ./cmd/api
cd peersight-agent && go build -o peersight-agent ./cmd/agent
cd peersight-broker && go build -o peersight-broker ./cmd/broker
```

### Cấu Hình

#### API Server

| Biến | Mặc định | Mô tả |
|---|---|---|
| `DATABASE_URL` | `postgres://peersight:peersight@localhost:5432/peersight?sslmode=disable` | Chuỗi kết nối PostgreSQL |
| `JWT_SECRET` | `change-me-in-production` | Khóa ký JWT (bắt buộc trong production) |
| `PORT` | `4000` | Cổng HTTP |
| `ENV` | `development` | `development` hoặc `production` |
| `ALLOWED_ORIGINS` | `http://localhost:5173` | CORS origins được phép |

#### Agent

| Biến | Mặc định | Mô tả |
|---|---|---|
| `PEERSIGHT_API_URL` | — | URL của API server |
| `PEERSIGHT_HOST_ID` | — | UUID của máy chủ này trên API |
| `PEERSIGHT_TOKEN` | — | Token JWT để xác thực |
| `PEERSIGHT_LOOP_INTERVAL` | `30` | Giây giữa các lần gửi heartbeat |
| `PEERSIGHT_READ_ONLY` | `false` | Chỉ báo cáo, không thực thi thay đổi |
| `PEERSIGHT_REDACT_SECRETS` | `false` | Loại bỏ private key trước khi gửi |
| `PEERSIGHT_WG_BINARY` | `wg` | Đường dẫn tới lệnh WireGuard |
| `PEERSIGHT_UNMANAGED_INTERFACES` | — | Các interface bỏ qua (cách bằng dấu phẩy) |

#### Broker

| Biến | Mặc định | Mô tả |
|---|---|---|
| `PEERSIGHT_API_URL` | — | URL của API server |
| `PEERSIGHT_BROKER_ID` | — | Định danh broker |
| `PEERSIGHT_TOKEN` | — | Token JWT để xác thực |
| `PEERSIGHT_LOOP_INTERVAL` | `30` | Giây giữa các lần poll |
| `PEERSIGHT_PIPE_1_TO` | `file` | Đích xuất: `file` hoặc `syslog` |
| `PEERSIGHT_PIPE_1_FROM` | `alerts` | Loại sự kiện đăng ký (cách bằng dấu phẩy) |
| `PEERSIGHT_PIPE_1_FILE` | `/var/log/peersight/events.jsonl` | Đường dẫn file đầu ra |

Xem [.env.example](.env.example) để biết đầy đủ danh sách biến.

### API Endpoints

#### Công khai (không cần xác thực)
- `GET /health` — Kiểm tra sức khỏe hệ thống (thời gian chạy, trạng thái DB)
- `GET /version` — Thông tin phiên bản API
- `POST /sessions` — Đăng nhập (email + mật khẩu → JWT access/refresh)
- `POST /sessions/refresh` — Làm mới access token
- `POST /accounts/signup` — Tạo tài khoản mới (mặc định: operator)

#### Hosts (cần xác thực)
- `GET /hosts` — Danh sách tất cả hosts
- `GET /hosts/:id` — Chi tiết một host
- `GET /hosts/:id/interfaces` — Danh sách các interfaces của host
- `GET /hosts/:id/endpoints` — Danh sách các endpoints của host
- `GET /hosts/:id/changes` — Danh sách các thay đổi mong muốn (desired changes)

#### Agent (cần xác thực agent)
- `POST /hosts/:host_id/ping/:version` — Heartbeat từ agent

#### Peers (cần xác thực)
- `GET /peers` — Danh sách tất cả peers

#### Cảnh báo & Sự kiện (cần xác thực)
- `GET /alerts` — Danh sách cảnh báo
- `POST /alerts/:id/resolve` — Đánh dấu đã xử lý
- `GET /events/stream` — Sự kiện realtime qua SSE (truyền token qua query)

#### Hàng đợi (cần xác thực, broker sử dụng)
- `POST /queues/:type/next` — Lấy batch sự kiện tiếp theo
- `POST /queues/:type/ack` — Xác nhận sự kiện đã được xử lý thành công

#### Quản trị viên (middleware RequireAdmin)
- `POST /admin/users` — Tạo người dùng với quyền tuỳ chỉnh
- `DELETE /peers/:id` — Xoá một peer
- `POST /hosts/:id/changes` — Tạo lệnh thay đổi mới gửi cho host

### Luồng Dữ Liệu

1. **Quản trị viên** dùng giao diện App để cấu hình peer mới
2. **API** lưu cấu hình dưới dạng `DesiredChange` trong PostgreSQL
3. **Agent** gửi heartbeat qua `POST /hosts/:id/ping/:version`
4. **API** trả về danh sách `DesiredChange` đang chờ
5. **Agent** thực thi `wg set` trên máy local và báo cáo kết quả
6. **API** ghi nhận thay đổi và tạo sự kiện cảnh báo
7. **Broker** poll `POST /queues/alerts/next` và nhận sự kiện
8. **Broker** ghi vào syslog hoặc file JSON Lines cho SIEM

### Cấu Trúc Dự Án

```
peersight/
├── .env.example / .gitignore / Makefile / docker-compose.yml
├── peersight-api/          # Backend Go (Gin + pgx + JWT)
│   ├── cmd/api/main.go
│   ├── internal/{config, models, repository, middleware, handlers}
│   └── migrations/001_init.sql
├── peersight-agent/        # Daemon Go (đồng bộ WireGuard)
│   ├── cmd/agent/main.go
│   └── internal/{config, wg, api, agent}
├── peersight-broker/       # Daemon Go (cầu nối SIEM)
│   ├── cmd/broker/main.go
│   └── internal/{config, api, pipe, broker}
└── peersight-app/          # Giao diện Vue.js 3
    ├── src/{pages, components, stores, plugins, styles}
    ├── nginx.conf
    └── Dockerfile
```

### So Sánh Procustodibus ↔ peersight

| Thành phần | Procustodibus | peersight |
|---|---|---|
| API Backend | Elixir / Phoenix | **Go / Gin** |
| Agent | Python | **Go** |
| Broker | Python | **Go** |
| Xác thực | Ed25519 Challenge-Signature | **JWT Bearer Token** |
| Build output | Python wheel + Mix release | **Single binary** |
| Docker image | ~150 MB (Python runtime) | **~15 MB (Alpine)** |
| Bộ nhớ Agent | ~30–50 MB | **~5–10 MB** |
| Cross-compile | Phức tạp (Python C deps) | **`GOOS=linux GOARCH=arm64 go build`** |
| Frontend | Vue.js 3 (Oruga / Bulma) | **Vue.js 3 (dark theme tùy chỉnh)** |

### Giấy Phép

MIT
