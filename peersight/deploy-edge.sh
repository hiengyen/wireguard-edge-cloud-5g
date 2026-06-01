#!/bin/bash
# ==============================================================
# PeerSight Edge Node — Full Automated Agent Deployment
# Run on the Edge Node after WireGuard is connected.
#
# Build modes:
#   native   — compile Go directly on this device (slower, no extra tools on PC)
#   transfer — copy a pre-compiled binary from Cloud/PC via rsync (recommended)
#
# What this script does (in order):
#   1. Validates required environment variables
#   2. [native mode] Installs Go and builds the agent on-device
#   3. [transfer mode] Verifies binary is already at /usr/local/bin/peersight-agent
#   4. Installs and enables the peersight-agent systemd service
#   5. Prints status summary
#
# Usage:
#   # Native build (on the Edge device):
#   sudo -E BUILD_MODE=native PEERSIGHT_API_URL=http://10.8.0.1:4000 \
#        PEERSIGHT_HOST_ID=<uuid> PEERSIGHT_TOKEN=<jwt> \
#        ./peersight/deploy-edge.sh
#
#   # Pre-built binary transfer (on the Cloud/PC, then run on Edge):
#   rsync -avzP peersight/peersight-agent user@10.8.0.2:/tmp/peersight-agent
#   ssh user@10.8.0.2 "sudo mv /tmp/peersight-agent /usr/local/bin/ && \
#       sudo chmod +x /usr/local/bin/peersight-agent && \
#       sudo -E BUILD_MODE=transfer PEERSIGHT_API_URL=http://10.8.0.1:4000 \
#       PEERSIGHT_HOST_ID=<uuid> PEERSIGHT_TOKEN=<jwt> \
#       ~/wireguard-edge-cloud-5g/peersight/deploy-edge.sh"
# ==============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_MODE="${BUILD_MODE:-native}"
AGENT_BINARY="/usr/local/bin/peersight-agent"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── 1. Root check ──────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "This script must be run as root. Please use: sudo -E $0"

# ── 2. Required variable checks ────────────────────────────────
: "${PEERSIGHT_API_URL:?'PEERSIGHT_API_URL is required (e.g. http://10.8.0.1:4000)'}"
: "${PEERSIGHT_HOST_ID:?'PEERSIGHT_HOST_ID is required — create a Host in the Web UI first'}"
: "${PEERSIGHT_TOKEN:?'PEERSIGHT_TOKEN is required — copy the Agent Token from the Web UI'}"

# ── 3. Build or validate binary ───────────────────────────────
if [[ "$BUILD_MODE" == "native" ]]; then
    info "Build mode: NATIVE (compiling on this device)"

    # 3a. Install Go if missing
    if ! command -v go &>/dev/null; then
        warn "'go' not found — running install-go.sh..."
        bash "${SCRIPT_DIR}/install-go.sh"
        # Activate PATH in current session
        # shellcheck source=/dev/null
        source /etc/profile.d/go.sh 2>/dev/null || export PATH="/usr/local/go/bin:${PATH}"
    else
        success "Go $(go version | awk '{print $3}') already installed."
    fi

    # 3b. Ensure build utilities exist
    command -v git  &>/dev/null || die "'git' not found. Install with: sudo apt-get install -y git"
    command -v make &>/dev/null || die "'make' not found. Install with: sudo apt-get install -y make"

    # 3c. Build agent binary
    info "Building peersight-agent ($(uname -m))..."
    (
        cd "${SCRIPT_DIR}/peersight-agent"
        CGO_ENABLED=0 go build -buildvcs=false -ldflags="-s -w" -o "${SCRIPT_DIR}/peersight-agent-built" ./cmd/agent
    )
    mv "${SCRIPT_DIR}/peersight-agent-built" "${AGENT_BINARY}"
    chmod +x "${AGENT_BINARY}"
    success "peersight-agent built and installed at ${AGENT_BINARY}."

elif [[ "$BUILD_MODE" == "transfer" ]]; then
    info "Build mode: TRANSFER (using pre-compiled binary)"

    [[ -f "$AGENT_BINARY" ]] || die \
        "Binary not found at ${AGENT_BINARY}. Transfer it first:\n" \
        "  rsync -avzP ./peersight/peersight-agent user@10.8.0.2:/tmp/peersight-agent\n" \
        "  ssh user@10.8.0.2 'sudo mv /tmp/peersight-agent ${AGENT_BINARY} && sudo chmod +x ${AGENT_BINARY}'"

    success "Binary found at ${AGENT_BINARY}."
else
    die "Unknown BUILD_MODE '${BUILD_MODE}'. Use 'native' or 'transfer'."
fi

# ── 4. Install systemd service ─────────────────────────────────
info "Installing peersight-agent systemd service..."
bash "${SCRIPT_DIR}/install-agent.sh"
success "Service installed."

# ── 5. Summary ─────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    PeerSight Edge Agent Deployment Complete!     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Reporting to: ${CYAN}${PEERSIGHT_API_URL}${NC}"
echo -e "  Host ID:      ${CYAN}${PEERSIGHT_HOST_ID}${NC}"
echo ""
echo -e "  Service status:  ${CYAN}sudo systemctl status peersight-agent${NC}"
echo -e "  Live logs:       ${CYAN}sudo journalctl -u peersight-agent -f${NC}"
echo ""
