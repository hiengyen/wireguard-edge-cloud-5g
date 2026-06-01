#!/bin/bash
# ==============================================================
# PeerSight Cloud Gateway — Full Automated Deployment
# Run on the Cloud Gateway after WireGuard is configured.
#
# What this script does (in order):
#   1. Validates environment variables
#   2. Ensures Go is installed (via install-go.sh)
#   3. Builds all Go binaries (API, Agent, Broker)
#   4. Creates /var/log/peersight log directory
#   5. Launches the Docker Compose stack (DB, API, UI, Broker)
#   6. Waits for API health check to pass
#   7. Installs and enables the peersight-agent systemd service
#   8. Prints endpoint summary
#
# Usage:
#   sudo -E ./peersight/deploy-cloud.sh
# ==============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"
API_HEALTH_RETRIES=15
API_HEALTH_INTERVAL=4

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── 1. Root check ──────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "This script must be run as root. Please use: sudo -E $0"

# ── 2. Load .env ───────────────────────────────────────────────
[[ -f "$ENV_FILE" ]] || die ".env not found at ${ENV_FILE}. Copy .env.example → .env and fill in values."
set -a
# shellcheck source=/dev/null
. "$ENV_FILE"
set +a

# ── 3. Required variable checks ────────────────────────────────
: "${PEERSIGHT_DB_PASSWORD:?'PEERSIGHT_DB_PASSWORD is not set in .env'}"
: "${PEERSIGHT_JWT_SECRET:?'PEERSIGHT_JWT_SECRET is not set in .env'}"
: "${PEERSIGHT_API_PORT:=4000}"
: "${PEERSIGHT_APP_PORT:=5173}"
: "${MONITORING_BIND_ADDRESS:=10.8.0.1}"

API_BASE_URL="http://${MONITORING_BIND_ADDRESS}:${PEERSIGHT_API_PORT}"

# ── 4. Install Go if missing ───────────────────────────────────
info "Checking Go installation..."
if ! command -v go &>/dev/null; then
    warn "'go' not found — running install-go.sh..."
    bash "${SCRIPT_DIR}/install-go.sh"
    # Activate PATH in current session
    # shellcheck source=/dev/null
    source /etc/profile.d/go.sh 2>/dev/null || export PATH="/usr/local/go/bin:${PATH}"
else
    success "Go $(go version | awk '{print $3}') already installed."
fi

# ── 5. Build agent binary ──────────────────────────────────────
info "Building peersight-agent binary..."
(
    cd "${SCRIPT_DIR}/peersight-agent"
    CGO_ENABLED=0 go build -buildvcs=false -ldflags="-s -w" -o peersight-agent ./cmd/agent
)
# Copy the built binary to /usr/local/bin
cp "${SCRIPT_DIR}/peersight-agent/peersight-agent" /usr/local/bin/peersight-agent
chmod +x /usr/local/bin/peersight-agent
success "peersight-agent binary installed at /usr/local/bin/peersight-agent."

# ── 6. Prepare log directory ───────────────────────────────────
info "Creating /var/log/peersight log directory..."
mkdir -p /var/log/peersight
chmod 755 /var/log/peersight
success "Log directory ready."

# ── 7. Launch Docker Compose stack ────────────────────────────
info "Starting PeerSight Docker Compose stack..."
(
    cd "${SCRIPT_DIR}"
    docker compose --env-file "${ENV_FILE}" up -d --build --remove-orphans
)
success "Docker stack started."

# ── 8. Wait for API health check ──────────────────────────────
info "Waiting for API to be healthy at ${API_BASE_URL}/health ..."
for i in $(seq 1 $API_HEALTH_RETRIES); do
    if curl -fs "${API_BASE_URL}/health" -o /dev/null 2>&1; then
        success "API is healthy."
        break
    fi
    if [[ $i -eq $API_HEALTH_RETRIES ]]; then
        die "API did not become healthy after $((API_HEALTH_RETRIES * API_HEALTH_INTERVAL))s. Check: docker compose logs"
    fi
    warn "Attempt ${i}/${API_HEALTH_RETRIES} — retrying in ${API_HEALTH_INTERVAL}s..."
    sleep $API_HEALTH_INTERVAL
done

# ── 9. Install peersight-agent systemd service ────────────────
if [[ -z "${PEERSIGHT_HOST_ID:-}" || -z "${PEERSIGHT_TOKEN:-}" ]]; then
    warn "PEERSIGHT_HOST_ID or PEERSIGHT_TOKEN is not set."
    warn "Skipping agent service setup."
    warn "After creating a Host in the Web UI, run:"
    warn "  sudo -E PEERSIGHT_API_URL=\"http://${MONITORING_BIND_ADDRESS}:${PEERSIGHT_API_PORT}\" PEERSIGHT_HOST_ID=<uuid> PEERSIGHT_TOKEN=<jwt> bash ${SCRIPT_DIR}/install-agent.sh"
else
    info "Installing peersight-agent systemd service..."
    PEERSIGHT_API_URL="http://${MONITORING_BIND_ADDRESS}:${PEERSIGHT_API_PORT}" \
    PEERSIGHT_HOST_ID="${PEERSIGHT_HOST_ID}" \
    PEERSIGHT_TOKEN="${PEERSIGHT_TOKEN}" \
    bash "${SCRIPT_DIR}/install-agent.sh"
    success "peersight-agent service enabled and running."
fi

# ── 10. Summary ────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     PeerSight Cloud Deployment Complete!         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  API (over WireGuard):  ${CYAN}http://${MONITORING_BIND_ADDRESS}:${PEERSIGHT_API_PORT}${NC}"
echo -e "  App UI (via SSH tunnel): ${CYAN}http://127.0.0.1:${PEERSIGHT_APP_PORT}${NC}"
echo -e "  Health check:           ${CYAN}${API_BASE_URL}/health${NC}"
echo ""
echo -e "  ${YELLOW}Next step:${NC} Create a Host profile in the Web UI."
echo -e "  SSH tunnel command:"
echo -e "  ${CYAN}ssh -N -L ${PEERSIGHT_API_PORT}:${MONITORING_BIND_ADDRESS}:${PEERSIGHT_API_PORT} -L ${PEERSIGHT_APP_PORT}:${MONITORING_BIND_ADDRESS}:${PEERSIGHT_APP_PORT} ec2-user@<ELASTIC_IP>${NC}"
echo ""
