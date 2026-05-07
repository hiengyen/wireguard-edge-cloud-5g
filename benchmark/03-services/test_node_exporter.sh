#!/usr/bin/env bash
# Test 03-D: Node Exporter metrics from both cloud gateway and edge node
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

section "03-D  Node Exporter Metrics"
require_cmd curl

TIMEOUT="$HTTP_TIMEOUT"

check_node_exporter() {
    local label="$1" url="$2"
    log "Checking Node Exporter: ${label} at ${url}"

    # 1. Metrics endpoint reachable
    if ! metrics=$(curl -sf --max-time "$TIMEOUT" "${url}/metrics" 2>/dev/null); then
        fail "${label}: metrics endpoint unreachable (${url}/metrics)"
        return 1
    fi
    pass "${label}: metrics endpoint reachable"

    # 2. Count metric families
    local metric_count
    metric_count=$(echo "$metrics" | grep -c '^# HELP' || true)
    info "${label}: ${metric_count} metric families"
    (( metric_count > 50 )) && pass "${label}: rich metrics (${metric_count} families)" \
                             || warn "${label}: low metric count (${metric_count}) — check collectors"

    # 3. CPU
    if echo "$metrics" | grep -q 'node_cpu_seconds_total'; then
        local idle_pct
        idle_pct=$(echo "$metrics" | grep 'node_cpu_seconds_total{.*mode="idle"' | head -1 | awk '{print $2}')
        info "${label}: CPU idle counter=${idle_pct} (cumulative seconds)"
        pass "${label}: CPU metrics present"
    else
        fail "${label}: node_cpu_seconds_total missing"
    fi

    # 4. Memory
    if echo "$metrics" | grep -q 'node_memory_MemAvailable_bytes'; then
        local mem_avail
        mem_avail=$(echo "$metrics" | grep '^node_memory_MemAvailable_bytes ' | awk '{print $2}')
        local mem_mb; mem_mb=$(echo "scale=0; $mem_avail / 1048576" | bc 2>/dev/null || echo "?")
        info "${label}: free memory = ${mem_mb} MiB"
        pass "${label}: memory metrics present"
    else
        fail "${label}: node_memory_MemAvailable_bytes missing"
    fi

    # 5. Disk
    if echo "$metrics" | grep -q 'node_filesystem_avail_bytes'; then
        local disk_avail
        disk_avail=$(echo "$metrics" | grep 'node_filesystem_avail_bytes{.*mountpoint="/"' | head -1 | awk '{print $2}')
        local disk_gb; disk_gb=$(echo "scale=1; ${disk_avail:-0} / 1073741824" | bc 2>/dev/null || echo "?")
        info "${label}: root disk available = ${disk_gb} GiB"
        pass "${label}: disk metrics present"
    else
        fail "${label}: node_filesystem_avail_bytes missing"
    fi

    # 6. Network
    if echo "$metrics" | grep -q 'node_network_receive_bytes_total'; then
        local ifaces
        ifaces=$(echo "$metrics" | grep '^node_network_receive_bytes_total' | grep -oP 'device="\K[^"]+' | tr '\n' ' ')
        info "${label}: network interfaces = ${ifaces}"
        pass "${label}: network metrics present (${ifaces})"
    else
        fail "${label}: node_network_receive_bytes_total missing"
    fi

    # 7. WireGuard interface present in network metrics
    if echo "$metrics" | grep -q "device=\"${WG_INTERFACE}\""; then
        local wg_rx wg_tx
        wg_rx=$(echo "$metrics" | grep "node_network_receive_bytes_total{.*device=\"${WG_INTERFACE}\"" | awk '{print $2}')
        wg_tx=$(echo "$metrics" | grep "node_network_transmit_bytes_total{.*device=\"${WG_INTERFACE}\"" | awk '{print $2}')
        info "${label}: WireGuard ${WG_INTERFACE} RX=${wg_rx}B TX=${wg_tx}B"
        pass "${label}: WireGuard interface visible in metrics"
    else
        warn "${label}: WireGuard interface ${WG_INTERFACE} not found in network metrics"
    fi

    # 8. System uptime
    if echo "$metrics" | grep -q 'node_boot_time_seconds'; then
        local boot_ts now uptime_h
        boot_ts=$(echo "$metrics" | grep '^node_boot_time_seconds ' | awk '{print $2}' | cut -d. -f1)
        now=$(date +%s)
        uptime_h=$(echo "scale=1; ($now - $boot_ts) / 3600" | bc 2>/dev/null || echo "?")
        info "${label}: uptime = ${uptime_h}h"
    fi
}

# Cloud gateway (over WireGuard overlay)
check_node_exporter "cloud-gateway" "$NODE_EXPORTER_CLOUD"

echo ""

# Edge node (localhost)
check_node_exporter "edge-node (local)" "$NODE_EXPORTER_EDGE"

print_summary "03-node-exporter"
