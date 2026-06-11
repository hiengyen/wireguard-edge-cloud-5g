#!/bin/bash
# ==============================================================
# Cloud Gateway Services Uninstaller
# Stops and removes PeerSight, Monitoring Stack (Prometheus/Loki/Grafana),
# Node Exporter, and reverts system hardening.
# ==============================================================

set -euo pipefail

# 1. Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] This script must be run as root. Please use sudo."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=== Uninstalling Cloud Gateway Services ==="

# 2. Stop and remove monitoring stack (Docker compose)
MONITORING_DIR="${REPO_DIR}/cloud/monitoring"
if [[ -d "${MONITORING_DIR}" ]]; then
    echo "[INFO] Stopping and cleaning Cloud Monitoring Docker containers & volumes..."
    if command -v docker &>/dev/null; then
        (cd "${MONITORING_DIR}" && docker compose down -v || true)
        echo "[OK] Cloud monitoring stack removed."
    else
        echo "[WARN] Docker not found. Skipping docker compose down."
    fi
fi

# 3. Stop and remove PeerSight Docker stack (Cloud Gateway)
PEERSIGHT_DIR="${REPO_DIR}/peersight"
if [[ -d "${PEERSIGHT_DIR}" ]]; then
    if [[ -f "${PEERSIGHT_DIR}/docker-compose.yml" ]]; then
        echo "[INFO] Stopping and cleaning PeerSight Docker containers & volumes..."
        if command -v docker &>/dev/null; then
            (cd "${PEERSIGHT_DIR}" && docker compose down -v || true)
            echo "[OK] PeerSight Docker stack removed."
        else
            echo "[WARN] Docker not found. Skipping docker compose down."
        fi
    fi
fi

# 4. Uninstall PeerSight Agent
PEERSIGHT_AGENT_UNINSTALL="${REPO_DIR}/peersight/uninstall_agent.sh"
if [[ -f "${PEERSIGHT_AGENT_UNINSTALL}" ]]; then
    echo "[INFO] Running PeerSight Agent uninstaller..."
    bash "${PEERSIGHT_AGENT_UNINSTALL}" || true
fi

# 5. Uninstall Node Exporter
NODE_EXP_UNINSTALL="${REPO_DIR}/shared/scripts/uninstall-node-exporter.sh"
if [[ -f "${NODE_EXP_UNINSTALL}" ]]; then
    echo "[INFO] Running Node Exporter uninstaller..."
    bash "${NODE_EXP_UNINSTALL}" || true
fi

# 6. Undo Hardening
UNDO_HARDENING="${REPO_DIR}/shared/scripts/undo-hardening.sh"
if [[ -f "${UNDO_HARDENING}" ]]; then
    echo "[INFO] Reverting system hardening..."
    bash "${UNDO_HARDENING}" || true
fi

echo "======================================"
echo "  Cloud Services Cleaned Up Successfully"
echo "======================================"
