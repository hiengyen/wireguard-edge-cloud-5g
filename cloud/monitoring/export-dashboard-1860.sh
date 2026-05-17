#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# export-dashboard-1860.sh
# Export the manually-imported "Node Exporter Full" (template 1860)
# from the running Grafana instance, customise it for WireGuard 5G
# Edge-Cloud provisioning, and save it so Grafana auto-loads it on
# every restart.
#
# Usage (run on the Cloud gateway):
#   cd /home/hiengyen/CODE/wireguard-edge-cloud-5g/cloud/monitoring
#   bash export-dashboard-1860.sh
#
# After running, recreate the containers:
#   sudo -E docker compose --env-file ../../.env up -d --force-recreate
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────
GRAFANA_URL="${GRAFANA_URL:-http://10.8.0.1:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-admin}"

# The UID Grafana assigned to the imported dashboard.
# Default for template 1860 rev 37. Adjust if yours differs.
# You can find it in the browser URL: /d/<UID>/...
DASHBOARD_UID="${DASHBOARD_UID:-rYdddlPWk}"

# Where to save the provisioned dashboard JSON
DEST_DIR="$(cd "$(dirname "$0")" && pwd)/grafana/provisioning/dashboards/definitions"
DEST_FILE="${DEST_DIR}/node_exporter_1860.json"

# New metadata for the provisioned version
NEW_TITLE="WireGuard 5G Edge-Cloud — Node Exporter Full"
NEW_UID="wireguard_5g_node_exporter"

# ── Step 1: Export from Grafana API ──────────────────────────────────
echo "📥 Exporting dashboard ${DASHBOARD_UID} from ${GRAFANA_URL}..."

RAW_JSON=$(curl -sf \
  -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
  "${GRAFANA_URL}/api/dashboards/uid/${DASHBOARD_UID}" \
) || {
  echo "❌ Failed to export dashboard. Check:"
  echo "   - Is Grafana running at ${GRAFANA_URL}?"
  echo "   - Is the UID correct? (check the browser URL bar)"
  echo "   - Are the credentials correct?"
  echo ""
  echo "   You can override settings with environment variables:"
  echo "     GRAFANA_URL=http://... DASHBOARD_UID=... bash $0"
  exit 1
}

# The API returns { "meta": {...}, "dashboard": {...} }.
# We only need the "dashboard" object.
DASHBOARD_JSON=$(echo "${RAW_JSON}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
dash = data['dashboard']

# ── Step 2: Customise for provisioning ──────────────────────────────
# Set a stable UID and title so Grafana treats it as our own dashboard
dash['uid']   = '${NEW_UID}'
dash['title'] = '${NEW_TITLE}'
dash['id']    = None          # Let Grafana assign its own internal ID
dash['version'] = 1           # Reset version counter
dash['editable'] = True

# Remove import-only metadata that is not needed for provisioning
dash.pop('__inputs',   None)
dash.pop('__elements', None)
dash.pop('__requires', None)
dash.pop('gnetId',     None)

# ── Step 3: Fix datasource references ───────────────────────────────
# Template 1860 uses a variable called \"\${DS_PROMETHEUS}\" which is
# only set during the interactive import wizard.  For provisioning we
# need to point every datasource reference to our provisioned
# Prometheus datasource (uid = 'prometheus').

def fix_datasources(obj):
    \"\"\"Recursively walk the JSON tree and fix datasource references.\"\"\"
    if isinstance(obj, dict):
        # Fix datasource objects
        if 'datasource' in obj and isinstance(obj['datasource'], dict):
            ds = obj['datasource']
            if ds.get('uid') in ('000000001', '\${DS_PROMETHEUS}', '\${ds_prometheus}', None):
                ds['uid']  = 'prometheus'
                ds['type'] = 'prometheus'
            # Remove the 'name' key from datasource references for provisioning
            ds.pop('name', None)
        # Fix string-based datasource references
        if obj.get('uid') in ('000000001', '\${DS_PROMETHEUS}', '\${ds_prometheus}'):
            obj['uid'] = 'prometheus'
        for v in obj.values():
            fix_datasources(v)
    elif isinstance(obj, list):
        for item in obj:
            fix_datasources(item)

fix_datasources(dash)

# ── Step 4: Fix template variables ──────────────────────────────────
# The 'datasource' template variable is only needed for the import
# wizard. For provisioning we can either remove it or set its default.
if 'templating' in dash and 'list' in dash['templating']:
    new_list = []
    for var in dash['templating']['list']:
        name = var.get('name', '')
        if name in ('datasource', 'ds_prometheus', 'DS_PROMETHEUS'):
            # Replace datasource variable with a fixed hidden variable
            var['type'] = 'constant'
            var['query'] = 'prometheus'
            var['current'] = {'text': 'Prometheus', 'value': 'prometheus'}
            var['hide'] = 2  # Hide completely from the UI
        # Fix query-type variables that reference the datasource variable
        if 'datasource' in var and isinstance(var['datasource'], dict):
            ds = var['datasource']
            if ds.get('uid') in ('000000001', '\${DS_PROMETHEUS}', '\${ds_prometheus}', None):
                ds['uid']  = 'prometheus'
                ds['type'] = 'prometheus'
            ds.pop('name', None)
        new_list.append(var)
    dash['templating']['list'] = new_list

# ── Step 5: Add project-specific tags ───────────────────────────────
existing_tags = set(dash.get('tags', []))
existing_tags.update(['wireguard', 'edge', '5g', 'node-exporter'])
dash['tags'] = sorted(existing_tags)

# ── Step 6: Update links ────────────────────────────────────────────
dash['links'] = [
    {
        'icon': 'external link',
        'tags': [],
        'targetBlank': True,
        'title': 'Project GitHub',
        'type': 'link',
        'url': 'https://github.com/hiengyen/wireguard-edge-cloud-5g'
    },
    {
        'icon': 'external link',
        'tags': [],
        'targetBlank': True,
        'title': 'Original Template 1860',
        'type': 'link',
        'url': 'https://grafana.com/grafana/dashboards/1860'
    }
]

# Pretty-print the result
print(json.dumps(dash, indent=2, ensure_ascii=False))
")

# ── Step 7: Save to provisioning directory ───────────────────────────
mkdir -p "${DEST_DIR}"
echo "${DASHBOARD_JSON}" > "${DEST_FILE}"

echo ""
echo "✅ Dashboard exported and customised successfully!"
echo "   📄 Saved to: ${DEST_FILE}"
echo "   📛 Title:    ${NEW_TITLE}"
echo "   🆔 UID:      ${NEW_UID}"
echo ""
echo "🔄 Now recreate the monitoring stack to load it:"
echo "   cd $(cd "$(dirname "$0")" && pwd)"
echo "   sudo -E docker compose --env-file ../../.env up -d --force-recreate"
echo ""
echo "   Then open Grafana → Dashboards → Edge Monitoring"
echo "   and look for '${NEW_TITLE}'"
