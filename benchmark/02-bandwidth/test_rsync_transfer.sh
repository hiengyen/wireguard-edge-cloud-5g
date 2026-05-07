#!/usr/bin/env bash
# Test 02-C: Real-world file transfer benchmark via rsync over WireGuard
# Measures effective application-layer throughput including encryption overhead
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

section "02-C  File Transfer Benchmark (rsync over WireGuard)"
require_cmd rsync ssh bc

SSH_USER="${SSH_USER:-ec2-user}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa}"
REMOTE_HOST="${WG_SERVER_IP}"
REMOTE_TMP="${REMOTE_TMP:-/tmp/benchmark_rx}"
LOCAL_TMP="${LOCAL_TMP:-/tmp/benchmark_tx}"
MIN_RSYNC_MBPS="${MIN_RSYNC_MBPS:-2}"

mkdir -p "$LOCAL_TMP" "$REPORT_DIR"

# SSH shorthand
ssh_cmd() { ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=10 "${SSH_USER}@${REMOTE_HOST}" "$@"; }

check_ssh() {
    log "Checking SSH access to ${REMOTE_HOST} as ${SSH_USER}"
    if ! ssh_cmd "echo ok" &>/dev/null; then
        fail "Cannot SSH to ${REMOTE_HOST} — check SSH key and WireGuard tunnel"
        print_summary "02-rsync-transfer"; exit 1
    fi
    pass "SSH to ${REMOTE_HOST} succeeded"
    ssh_cmd "mkdir -p ${REMOTE_TMP}" 2>/dev/null || true
}

# Generate test file of given size (MiB)
make_file() {
    local name="$1" size_mb="$2"
    local path="${LOCAL_TMP}/${name}"
    if [[ ! -f "$path" ]]; then
        dd if=/dev/urandom of="$path" bs=1M count="$size_mb" status=none
    fi
    echo "$path"
}

run_rsync() {
    local label="$1" file="$2" direction="${3:-up}"
    local size_bytes; size_bytes=$(stat -c%s "$file")
    local size_mb; size_mb=$(echo "scale=2; $size_bytes/1048576" | bc)

    local start end elapsed mbps
    start=$(date +%s%N)

    if [[ "$direction" == "up" ]]; then
        rsync -a --no-compress -e "ssh -i ${SSH_KEY} -o StrictHostKeyChecking=accept-new" \
            "$file" "${SSH_USER}@${REMOTE_HOST}:${REMOTE_TMP}/" 2>/dev/null
    else
        local remote_file="${REMOTE_TMP}/$(basename "$file")"
        # Create remote file if missing
        ssh_cmd "test -f ${remote_file} || dd if=/dev/urandom of=${remote_file} bs=1M count=$(echo "$size_mb" | cut -d. -f1) status=none" 2>/dev/null
        rsync -a --no-compress -e "ssh -i ${SSH_KEY} -o StrictHostKeyChecking=accept-new" \
            "${SSH_USER}@${REMOTE_HOST}:${remote_file}" "${LOCAL_TMP}/rx_$(basename "$file")" 2>/dev/null
    fi

    end=$(date +%s%N)
    elapsed=$(echo "scale=3; ($end - $start)/1000000000" | bc)
    mbps=$(echo "scale=2; ($size_bytes * 8) / ($elapsed * 1000000)" | bc)

    info "${label}: ${size_mb} MiB in ${elapsed}s = ${mbps} Mbps"

    (( $(echo "$mbps < $MIN_RSYNC_MBPS" | bc -l) )) \
        && fail "${label}: ${mbps} Mbps below threshold ${MIN_RSYNC_MBPS} Mbps" \
        || pass "${label}: ${mbps} Mbps"

    echo "${label}: ${size_mb}MiB ${elapsed}s ${mbps}Mbps" >> "${REPORT_DIR}/rsync_$(date '+%Y%m%d').txt"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
check_ssh

# Small file (1 MiB) — tests connection setup overhead
f1=$(make_file "test_1MB.bin"   1)
run_rsync "rsync-up   1MiB"  "$f1" "up"
run_rsync "rsync-down 1MiB"  "$f1" "down"

# Medium file (10 MiB) — realistic dataset chunk
f2=$(make_file "test_10MB.bin"  10)
run_rsync "rsync-up  10MiB"  "$f2" "up"
run_rsync "rsync-down 10MiB" "$f2" "down"

# Large file (50 MiB) — tests sustained throughput
f3=$(make_file "test_50MB.bin"  50)
run_rsync "rsync-up  50MiB"  "$f3" "up"
run_rsync "rsync-down 50MiB" "$f3" "down"

# Multi-file transfer (many small files simulate IoT data upload)
log "Creating multi-file dataset (50 × 100KB)"
MULTI_DIR="${LOCAL_TMP}/multi"
mkdir -p "$MULTI_DIR"
for i in $(seq 1 50); do
    dd if=/dev/urandom of="${MULTI_DIR}/file_${i}.dat" bs=1K count=100 status=none
done
start=$(date +%s%N)
rsync -a --no-compress -e "ssh -i ${SSH_KEY} -o StrictHostKeyChecking=accept-new" \
    "${MULTI_DIR}/" "${SSH_USER}@${REMOTE_HOST}:${REMOTE_TMP}/multi/" 2>/dev/null
end=$(date +%s%N)
elapsed=$(echo "scale=3; ($end - $start)/1000000000" | bc)
total_bytes=$(( 50 * 100 * 1024 ))
mbps=$(echo "scale=2; ($total_bytes * 8) / ($elapsed * 1000000)" | bc)
info "multi-file 50×100KB: ${elapsed}s = ${mbps} Mbps"
pass "Multi-file rsync: ${mbps} Mbps"

# Cleanup remote
ssh_cmd "rm -rf ${REMOTE_TMP}" 2>/dev/null || true
rm -rf "$LOCAL_TMP"

print_summary "02-rsync-transfer"
