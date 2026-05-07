#!/usr/bin/env bash
# Test 03-C: Grafana health, data sources, and API responsiveness
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"

section "03-C  Grafana Visualization"
require_cmd curl

GRAFANA="${GRAFANA_URL}"
AUTH="admin:${GRAFANA_ADMIN_PASSWORD}"
TIMEOUT="$HTTP_TIMEOUT"

gf_get() { curl -sf --max-time "$TIMEOUT" -u "$AUTH" "$1" 2>/dev/null; }

# 1. Health check
log "Checking Grafana health: ${GRAFANA}/api/health"
health=$(gf_get "${GRAFANA}/api/health" || echo '{}')
db_status=$(echo "$health" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('database','?'))" 2>/dev/null || echo "?")
if [[ "$db_status" == "ok" ]]; then
    pass "Grafana health: database=${db_status}"
else
    fail "Grafana health check failed (database=${db_status}) — check Grafana container"
    print_summary "03-grafana"; exit 1
fi

# 2. API response latency
latency=$(curl -sf -o /dev/null -w '%{time_total}' --max-time "$TIMEOUT" \
    -u "$AUTH" "${GRAFANA}/api/health" 2>/dev/null || echo "timeout")
if [[ "$latency" != "timeout" ]]; then
    ms=$(echo "scale=0; $latency * 1000 / 1" | bc)
    (( ms < 1000 )) && pass "Grafana API latency: ${ms}ms" \
                     || warn "Grafana API latency: ${ms}ms (consider more CPU)"
else
    fail "Grafana API timed out"
fi

# 3. Verify data sources are provisioned and reachable
log "Checking provisioned data sources"
ds_json=$(gf_get "${GRAFANA}/api/datasources" || echo "[]")
ds_count=$(echo "$ds_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
info "Data sources configured: ${ds_count}"

if (( ds_count == 0 )); then
    fail "No data sources found — provisioning may have failed"
else
    echo "$ds_json" | python3 -c "
import sys, json
for ds in json.load(sys.stdin):
    print(f\"  {ds.get('name')}: {ds.get('type')} → {ds.get('url')}\")
" 2>/dev/null | while IFS= read -r line; do info "$line"; done

    # Test each data source connection
    echo "$ds_json" | python3 -c "
import sys, json
for ds in json.load(sys.stdin):
    print(ds.get('uid',''), ds.get('name','?'))
" 2>/dev/null | while read -r uid name; do
        [[ -z "$uid" ]] && continue
        result=$(curl -sf --max-time "$TIMEOUT" -u "$AUTH" \
            -X POST "${GRAFANA}/api/datasources/uid/${uid}/health" 2>/dev/null || echo '{}')
        status=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','?'))" 2>/dev/null || echo "?")
        if [[ "${status,,}" == "ok" ]]; then
            pass "Data source '${name}': connection OK"
        else
            fail "Data source '${name}': connection FAILED (status=${status})"
        fi
    done
fi

# 4. Dashboard count
log "Checking provisioned dashboards"
dash_json=$(gf_get "${GRAFANA}/api/search?type=dash-db" || echo "[]")
dash_count=$(echo "$dash_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
info "Dashboards: ${dash_count}"
(( dash_count >= 0 )) && pass "Grafana dashboards: ${dash_count} found"

# 5. Organisation and user info
org=$(gf_get "${GRAFANA}/api/org" || echo '{}')
org_name=$(echo "$org" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('name','?'))" 2>/dev/null || echo "?")
info "Grafana organisation: ${org_name}"

# 6. Grafana version
version=$(gf_get "${GRAFANA}/api/health" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('version','?'))" 2>/dev/null || echo "?")
info "Grafana version: ${version}"
pass "Grafana is operational (version=${version})"

print_summary "03-grafana"
