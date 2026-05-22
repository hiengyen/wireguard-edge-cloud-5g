#!/bin/bash
# ==============================================================
# PeerSight — Full Automated Uninstaller
# Run on Cloud Gateway or Edge Nodes to completely remove PeerSight.
#
# Usage:
#   sudo ./peersight/uninstall.sh
# ==============================================================

set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "This script must be run as root. Please use: sudo $0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info "Starting PeerSight Uninstaller..."

# ── 1. Stop and remove Docker Compose stack (Cloud Gateway) ───
if [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
    if command -v docker &>/dev/null; then
        info "Stopping and removing PeerSight Docker containers (volumes are preserved)..."
        # Use || true to prevent failure if containers are already gone
        (cd "${SCRIPT_DIR}" && docker compose down || true)
        success "Docker stack removed (Data intact)."
    fi
fi

# ── 2. Stop and disable systemd service (Cloud & Edge) ────────
if systemctl is-active --quiet peersight-agent.service 2>/dev/null || systemctl is-enabled --quiet peersight-agent.service 2>/dev/null; then
    info "Stopping peersight-agent service..."
    systemctl stop peersight-agent.service || true
    systemctl disable peersight-agent.service || true
    rm -f /etc/systemd/system/peersight-agent.service
    systemctl daemon-reload
    success "Systemd service removed."
else
    info "No running peersight-agent service found."
fi

# ── 3. Remove binaries ─────────────────────────────────────────
if [[ -f "/usr/local/bin/peersight-agent" ]]; then
    info "Removing peersight-agent binary..."
    rm -f "/usr/local/bin/peersight-agent"
    success "Binary removed."
fi

# ── 4. Remove config directory ─────────────────────────────────
if [[ -d "/etc/peersight" ]]; then
    info "Removing configuration directory (/etc/peersight)..."
    rm -rf "/etc/peersight"
    success "Configuration removed."
fi

# ── 5. Remove log directory ────────────────────────────────────
if [[ -d "/var/log/peersight" ]]; then
    info "Removing log directory (/var/log/peersight)..."
    rm -rf "/var/log/peersight"
    success "Logs removed."
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        PeerSight Successfully Uninstalled!       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
