#!/usr/bin/env bash
# Shared configuration and helpers for all benchmark scripts
set -euo pipefail

# ─── Environment & Auto-detection ─────────────────────────────────────────────
SCRIPT_DIR_FOR_ENV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
load_env_file() {
    local env_file="$1"
    [[ -f "$env_file" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Ignore comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        # Extract key and value
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            # Strip outer single/double quotes if present
            val="${val%\"}"
            val="${val#\"}"
            val="${val%\'}"
            val="${val#\'}"
            # Only set and export if not already set in environment
            if [[ -z "${!key:-}" ]]; then
                export "$key"="$val"
            fi
        fi
    done < "$env_file"
}

# Load project-wide env first, then benchmark-specific values for keys that
# are still unset. Explicitly exported shell variables keep highest priority.
load_env_file "${SCRIPT_DIR_FOR_ENV}/../.env"
load_env_file "${SCRIPT_DIR_FOR_ENV}/../.env.benchmark"

# Auto-detect Cloud Public IP from Terraform state if not set
if [[ -z "${CLOUD_PUBLIC_IP:-}" ]]; then
    STATE_FILE="${SCRIPT_DIR_FOR_ENV}/../cloud/terraform/ec2/terraform.tfstate"
    if [[ -f "$STATE_FILE" ]]; then
        CLOUD_PUBLIC_IP=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('outputs', {}).get('public_ip', {}).get('value', ''))" 2>/dev/null || echo "")
        if [[ -n "$CLOUD_PUBLIC_IP" ]]; then
            export CLOUD_PUBLIC_IP
        fi
    fi
fi

# Auto-detect SSH key location
if [[ -z "${SSH_KEY:-}" ]]; then
    # Try user's home directory if run via sudo
    REAL_HOME="${HOME}"
    if [[ -n "${SUDO_USER:-}" ]]; then
        REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6 || echo "/home/${SUDO_USER}")
    fi
    
    # Check common SSH key paths
    for key_path in \
        "${REAL_HOME}/.ssh/id_rsa" \
        "${REAL_HOME}/.ssh/id_ed25519" \
        "${REAL_HOME}/.ssh/id_ecdsa" \
        "${REAL_HOME}/.ssh/wg-key-pair" \
        "${REAL_HOME}/.ssh/wg-key-pair.pem"; do
        if [[ -f "$key_path" ]]; then
            export SSH_KEY="$key_path"
            break
        fi
    done
fi

# Expand a leading ~ when SSH_KEY came from the local .env parser instead of
# shell evaluation.
if [[ "${SSH_KEY:-}" == "~/"* ]]; then
    export SSH_KEY="${HOME}/${SSH_KEY#"~/"}"
fi


# ─── Network topology ─────────────────────────────────────────────────────────
WG_SERVER_IP="${WG_SERVER_IP:-10.8.0.1}"          # Cloud gateway WireGuard IP
WG_CLIENT_IP="${WG_CLIENT_IP:-10.8.0.2}"          # This edge node WireGuard IP
WG_INTERFACE="${WG_INTERFACE:-wg0}"               # WireGuard interface name
WG_PORT="${WG_PORT:-51820}"                        # WireGuard UDP port

CLOUD_PUBLIC_IP="${CLOUD_PUBLIC_IP:-}"             # EC2 public IP (set via env)
WWAN_INTERFACE="${WWAN_INTERFACE:-}"               # Auto-detected if empty

# ─── Service endpoints (accessed over WireGuard overlay) ──────────────────────
PROMETHEUS_URL="${PROMETHEUS_URL:-http://${WG_SERVER_IP}:9090}"
LOKI_URL="${LOKI_URL:-http://${WG_SERVER_IP}:3100}"
GRAFANA_URL="${GRAFANA_URL:-http://${WG_SERVER_IP}:3000}"
NODE_EXPORTER_CLOUD="${NODE_EXPORTER_CLOUD:-http://${WG_SERVER_IP}:9100}"
NODE_EXPORTER_EDGE="${NODE_EXPORTER_EDGE:-http://127.0.0.1:9100}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}"

# ─── iperf3 targets ───────────────────────────────────────────────────────────
IPERF3_SERVER="${IPERF3_SERVER:-${WG_SERVER_IP}}"
IPERF3_PORT="${IPERF3_PORT:-5201}"

# ─── Test parameters ──────────────────────────────────────────────────────────
PING_COUNT="${PING_COUNT:-20}"
PING_INTERVAL="${PING_INTERVAL:-0.2}"             # seconds between pings
IPERF3_DURATION="${IPERF3_DURATION:-10}"          # seconds per iperf3 run
IPERF3_PARALLEL="${IPERF3_PARALLEL:-4}"           # parallel streams
SUSTAINED_DURATION="${SUSTAINED_DURATION:-60}"    # seconds for sustained load test
HTTP_TIMEOUT="${HTTP_TIMEOUT:-10}"                # curl timeout in seconds
REPORT_DIR="${REPORT_DIR:-$(dirname "$0")/reports}"

# ─── ANSI colours ─────────────────────────────────────────────────────────────
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[0;33m'
BLU='\033[0;34m'
CYN='\033[0;36m'
BLD='\033[1m'
RST='\033[0m'

# ─── Helpers ──────────────────────────────────────────────────────────────────
PASS=0; FAIL=0; WARN=0
RESULTS=()

log()  { echo -e "${BLU}[$(date '+%H:%M:%S')]${RST} $*"; }
pass() { echo -e "${GRN}  ✔ PASS${RST}  $*"; ((PASS++)) || true; RESULTS+=("PASS: $*"); }
fail() { echo -e "${RED}  ✘ FAIL${RST}  $*"; ((FAIL++)) || true; RESULTS+=("FAIL: $*"); }
warn() { echo -e "${YLW}  ⚠ WARN${RST}  $*"; ((WARN++)) || true; RESULTS+=("WARN: $*"); }
info() { echo -e "${CYN}  ℹ INFO${RST}  $*"; }
section() {
    echo ""
    echo -e "${BLD}${BLU}══════════════════════════════════════════════${RST}"
    echo -e "${BLD}  $*${RST}"
    echo -e "${BLD}${BLU}══════════════════════════════════════════════${RST}"
}

require_cmd() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            warn "Command not found: $cmd  (some tests will be skipped)"
        fi
    done
}

# Auto-detect WWAN interface (ww*)
detect_wwan() {
    if [[ -n "$WWAN_INTERFACE" ]]; then return; fi
    local iface
    iface=$(ip link show 2>/dev/null | awk -F': ' '/ww/{print $2; exit}')
    WWAN_INTERFACE="${iface:-}"
}

# Print final summary and write to report file
print_summary() {
    local suite="${1:-benchmark}"
    local ts; ts=$(date '+%Y%m%d_%H%M%S')
    local report_file="${REPORT_DIR}/${suite}_${ts}.txt"

    section "SUMMARY — ${suite}"
    echo -e "  ${GRN}PASS: ${PASS}${RST}  |  ${RED}FAIL: ${FAIL}${RST}  |  ${YLW}WARN: ${WARN}${RST}"
    echo ""

    mkdir -p "$REPORT_DIR"
    {
        echo "=== ${suite} — $(date) ==="
        echo "PASS=${PASS}  FAIL=${FAIL}  WARN=${WARN}"
        echo ""
        for r in "${RESULTS[@]}"; do echo "  $r"; done
    } > "$report_file"

    info "Report saved: $report_file"
    [[ $FAIL -eq 0 ]]  # exit 0 only when no failures
}
