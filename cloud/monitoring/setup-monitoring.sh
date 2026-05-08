#!/bin/bash
# Wrapper to start the monitoring stack.
# Resolves .env (cloud/monitoring/.env or project root .env), applies
# ALLOW_MONITORING_OVER_WIREGUARD logic, validates required vars,
# then delegates to docker compose.
#
# Usage:
#   sudo ./setup-monitoring.sh              # start (up -d)
#   sudo ./setup-monitoring.sh down         # stop
#   sudo ./setup-monitoring.sh logs -f      # follow logs
#   sudo ./setup-monitoring.sh <args>       # any docker compose subcommand
#
# Override env file:
#   sudo ENV_FILE=/path/to/.env ./setup-monitoring.sh

set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
WG_SERVER_IP="${WG_SERVER_IP:-10.8.0.1}"

# ---------------------------------------------------------------------------
# 1. Resolve .env file — prefer cloud/monitoring/.env, fall back to project root
# ---------------------------------------------------------------------------
find_env_file() {
  local candidates=(
    "$SCRIPT_DIR/.env"
    "$SCRIPT_DIR/../../.env"
  )
  for f in "${candidates[@]}"; do
    [[ -f "$f" ]] && { echo "$f"; return; }
  done
}

ENV_FILE="${ENV_FILE:-$(find_env_file)}"

if [[ -z "$ENV_FILE" || ! -f "$ENV_FILE" ]]; then
  echo "ERROR: No .env file found. Create cloud/monitoring/.env or set ENV_FILE=." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Source .env to evaluate ALLOW_MONITORING_OVER_WIREGUARD, then set
#    MONITORING_BIND_ADDRESS before docker compose reads the file again.
# ---------------------------------------------------------------------------
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

if [[ "${ALLOW_MONITORING_OVER_WIREGUARD:-false}" == "true" ]]; then
  export MONITORING_BIND_ADDRESS="$WG_SERVER_IP"
else
  export MONITORING_BIND_ADDRESS="${MONITORING_BIND_ADDRESS:-127.0.0.1}"
fi

# ---------------------------------------------------------------------------
# 3. Validate required variables
# ---------------------------------------------------------------------------
if [[ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
  echo "ERROR: GRAFANA_ADMIN_PASSWORD is not set." >&2
  echo "  Add it to $ENV_FILE or pass: GRAFANA_ADMIN_PASSWORD=<pw> $0" >&2
  exit 1
fi

if [[ "${GRAFANA_ADMIN_PASSWORD}" == "CHANGE_ME_BEFORE_DEPLOYMENT" ]]; then
  echo "ERROR: GRAFANA_ADMIN_PASSWORD is still the placeholder value." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 4. Run docker compose — pass --env-file so compose uses the same file
#    regardless of working directory
# ---------------------------------------------------------------------------
cd "$SCRIPT_DIR"

ARGS=("${@}")
[[ ${#ARGS[@]} -eq 0 ]] && ARGS=(up -d)

echo "env file   : $ENV_FILE"
echo "bind addr  : $MONITORING_BIND_ADDRESS"
echo "loki       : $MONITORING_BIND_ADDRESS:${LOKI_PORT:-3100}"
echo "prometheus : $MONITORING_BIND_ADDRESS:${PROMETHEUS_PORT:-9090}"
echo "grafana    : $MONITORING_BIND_ADDRESS:${GRAFANA_PORT:-3000}"
echo ""

exec docker compose --env-file "$ENV_FILE" "${ARGS[@]}"
