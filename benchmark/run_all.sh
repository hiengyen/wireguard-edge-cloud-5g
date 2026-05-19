#!/usr/bin/env bash
# Master benchmark runner — executes all test suites and produces a combined report
set -euo pipefail
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${BENCH_DIR}/config.sh"

# ─── CLI flags ─────────────────────────────────────────────────────────────────
SUITES=("01" "02" "03" "04" "05")          # run all by default
SKIP_DESTRUCTIVE="${SKIP_DESTRUCTIVE:-1}"   # skip tests that disrupt connectivity
VERBOSE="${VERBOSE:-0}"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [SUITES...]

Run benchmark suites for wireguard-edge-cloud-5g.

SUITES (default: all):
  01   Connectivity (ping, WireGuard tunnel, 5G signal)
  02   Bandwidth (iperf3 TCP/UDP, rsync, WireGuard overhead)
  03   Services (Prometheus, Loki, Grafana, Node Exporter)
  04   Load (sustained bandwidth, monitoring load, WWAN reconnect)
  05   End-to-end (full stack, failover)

OPTIONS:
  --suite 01,03         Run only specified suites (comma-separated)
  --skip-destructive    Skip tests that disrupt network (default: on)
  --allow-destructive   Enable reconnect/failover tests (needs root)
  --iperf3-server IP    Override iperf3/WireGuard server IP
  --duration N          Override iperf3 duration in seconds (default: 10)
  --sustained N         Override sustained test duration in seconds (default: 60)
  -v, --verbose         Pass through full test output
  -h, --help            Show this help

ENV vars (override config.sh defaults):
  WG_SERVER_IP          WireGuard server overlay IP   [${WG_SERVER_IP}]
  CLOUD_PUBLIC_IP       EC2 public IP for overhead test []
  GRAFANA_ADMIN_PASSWORD Grafana admin password        [admin]
  SSH_USER              SSH user for rsync tests       [ec2-user]
  SSH_KEY               Path to SSH private key        [~/.ssh/id_rsa]

Examples:
  $0                              # Run all non-destructive suites
  $0 --suite 01,02                # Connectivity + bandwidth only
  $0 --allow-destructive          # Include reconnect/failover (needs sudo)
  IPERF3_DURATION=30 $0 02        # 30s iperf3 runs
EOF
    exit 0
}

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)              usage ;;
        --suite)                IFS=',' read -ra SUITES <<< "$2"; shift 2 ;;
        --skip-destructive)     SKIP_DESTRUCTIVE=1; shift ;;
        --allow-destructive)    SKIP_DESTRUCTIVE=0; shift ;;
        --iperf3-server)        export IPERF3_SERVER="$2"; shift 2 ;;
        --duration)             export IPERF3_DURATION="$2"; shift 2 ;;
        --sustained)            export SUSTAINED_DURATION="$2"; shift 2 ;;
        -v|--verbose)           VERBOSE=1; shift ;;
        [0-9]*)                 IFS=',' read -ra SUITES <<< "$1"; shift ;;
        *)                      echo "Unknown option: $1"; usage ;;
    esac
done

GLOBAL_PASS=0; GLOBAL_FAIL=0; GLOBAL_WARN=0
RUN_LOG="${REPORT_DIR}/run_all_$(date '+%Y%m%d_%H%M%S').log"
mkdir -p "$REPORT_DIR"

run_script() {
    local script="$1" label="$2"
    local log_out="${REPORT_DIR}/$(basename "${script%.sh}")_$(date '+%H%M%S').log"

    log "Running: ${label}"
    local start; start=$(date +%s)

    local exit_code=0
    if [[ "$VERBOSE" == "1" ]]; then
        bash "$script" 2>&1 | tee "$log_out" || exit_code=$?
    else
        bash "$script" > "$log_out" 2>&1 || exit_code=$?
        # Always show PASS/FAIL/WARN lines
        grep -E '✔ PASS|✘ FAIL|⚠ WARN|ℹ INFO|══' "$log_out" | sed 's/^/  /' || true
    fi

    local elapsed=$(( $(date +%s) - start ))
    local pass fail warn
    pass=$(grep -c '✔ PASS' "$log_out" || true)
    fail=$(grep -c '✘ FAIL' "$log_out" || true)
    warn=$(grep -c '⚠ WARN' "$log_out" || true)

    (( GLOBAL_PASS += pass )) || true
    (( GLOBAL_FAIL += fail )) || true
    (( GLOBAL_WARN += warn )) || true

    if (( fail == 0 )); then
        echo -e "${GRN}  ✔ ${label}: PASS${RST} (${pass}P ${warn}W in ${elapsed}s)"
    else
        echo -e "${RED}  ✘ ${label}: ${fail} FAIL${RST} (${pass}P ${warn}W in ${elapsed}s) → ${log_out}"
    fi

    echo "${label}: P=${pass} F=${fail} W=${warn} t=${elapsed}s" >> "$RUN_LOG"
}

# ─── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLD}${BLU}╔════════════════════════════════════════════════╗${RST}"
echo -e "${BLD}${BLU}║   wireguard-edge-cloud-5g  Benchmark Suite     ║${RST}"
echo -e "${BLD}${BLU}║   $(date '+%Y-%m-%d %H:%M:%S')   Suites: ${SUITES[*]}${RST}"
echo -e "${BLD}${BLU}╚════════════════════════════════════════════════╝${RST}"
echo ""
info "WireGuard server:  ${WG_SERVER_IP}"
info "iperf3 server:     ${IPERF3_SERVER}"
info "Prometheus:        ${PROMETHEUS_URL}"
info "Loki:              ${LOKI_URL}"
info "Grafana:           ${GRAFANA_URL}"
info "Destructive tests: $([ "$SKIP_DESTRUCTIVE" = "1" ] && echo "SKIPPED" || echo "ENABLED")"
echo ""

# ─── Suite 01: Connectivity ───────────────────────────────────────────────────
if printf '%s\n' "${SUITES[@]}" | grep -q '^01$'; then
    section "Suite 01 — Connectivity"
    run_script "${BENCH_DIR}/01-connectivity/test_ping_latency.sh"  "01-A Ping Latency"
    run_script "${BENCH_DIR}/01-connectivity/test_wg_tunnel.sh"     "01-B WireGuard Tunnel"
    run_script "${BENCH_DIR}/01-connectivity/test_5g_signal.sh"     "01-C 5G Signal Quality"
fi

# ─── Suite 02: Bandwidth ──────────────────────────────────────────────────────
if printf '%s\n' "${SUITES[@]}" | grep -q '^02$'; then
    section "Suite 02 — Bandwidth"
    run_script "${BENCH_DIR}/02-bandwidth/test_iperf3_tcp.sh"       "02-A TCP Bandwidth"
    run_script "${BENCH_DIR}/02-bandwidth/test_iperf3_udp.sh"       "02-B UDP Bandwidth & Jitter"
    run_script "${BENCH_DIR}/02-bandwidth/test_rsync_transfer.sh"   "02-C rsync File Transfer"
    run_script "${BENCH_DIR}/02-bandwidth/test_wg_overhead.sh"      "02-D WireGuard Overhead"
fi

# ─── Suite 03: Services ───────────────────────────────────────────────────────
if printf '%s\n' "${SUITES[@]}" | grep -q '^03$'; then
    section "Suite 03 — Services"
    run_script "${BENCH_DIR}/03-services/test_prometheus.sh"        "03-A Prometheus"
    run_script "${BENCH_DIR}/03-services/test_loki.sh"              "03-B Loki"
    run_script "${BENCH_DIR}/03-services/test_grafana.sh"           "03-C Grafana"
    run_script "${BENCH_DIR}/03-services/test_node_exporter.sh"     "03-D Node Exporter"
fi

# ─── Suite 04: Load ───────────────────────────────────────────────────────────
if printf '%s\n' "${SUITES[@]}" | grep -q '^04$'; then
    section "Suite 04 — Load"
    run_script "${BENCH_DIR}/04-load/test_sustained_bandwidth.sh"   "04-A Sustained Bandwidth"
    run_script "${BENCH_DIR}/04-load/test_monitoring_load.sh"       "04-B Monitoring Load"

    if [[ "$SKIP_DESTRUCTIVE" == "0" ]]; then
        if [[ $EUID -ne 0 ]]; then
            warn "04-C WWAN Reconnect requires root — run with sudo to enable"
        else
            run_script "${BENCH_DIR}/04-load/test_wwan_reconnect.sh" "04-C WWAN Reconnect"
        fi
    else
        warn "04-C WWAN Reconnect skipped (use --allow-destructive to enable)"
    fi
fi

# ─── Suite 05: End-to-End ─────────────────────────────────────────────────────
if printf '%s\n' "${SUITES[@]}" | grep -q '^05$'; then
    section "Suite 05 — End-to-End"
    run_script "${BENCH_DIR}/05-e2e/test_full_stack.sh"             "05-A Full Stack"

    if [[ "$SKIP_DESTRUCTIVE" == "0" ]]; then
        if [[ $EUID -ne 0 ]]; then
            warn "05-B Failover test requires root — run with sudo to enable"
        else
            run_script "${BENCH_DIR}/05-e2e/test_failover.sh"       "05-B Failover Recovery"
        fi
    else
        warn "05-B Failover test skipped (use --allow-destructive to enable)"
    fi
fi

# ─── Final summary ────────────────────────────────────────────────────────────
echo ""
echo -e "${BLD}${BLU}╔════════════════════════════════════════════════╗${RST}"
echo -e "${BLD}  GLOBAL RESULTS"
echo -e "  ${GRN}PASS: ${GLOBAL_PASS}${RST}  |  ${RED}FAIL: ${GLOBAL_FAIL}${RST}  |  ${YLW}WARN: ${GLOBAL_WARN}${RST}"
echo -e "${BLD}${BLU}╚════════════════════════════════════════════════╝${RST}"
echo ""
info "All logs in: ${REPORT_DIR}/"
info "Run log:     ${RUN_LOG}"

[[ $GLOBAL_FAIL -eq 0 ]]
