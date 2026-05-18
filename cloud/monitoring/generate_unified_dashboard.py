import json
import os

dashboard = {
  "title": "WireGuard 5G Unified Overview (Edge & Cloud)",
  "uid": "unified_edge_cloud_overview",
  "tags": ["edge", "cloud", "unified"],
  "timezone": "browser",
  "schemaVersion": 38,
  "refresh": "5s",
  "panels": [
    {
      "type": "stat",
      "title": "Nodes Online",
      "gridPos": {"x": 0, "y": 0, "w": 4, "h": 5},
      "targets": [
        {
          "expr": "up{job=~\"cloud-node|edge-nodes\"}",
          "legendFormat": "{{host}}",
          "datasource": {"type": "prometheus", "uid": "prometheus"}
        }
      ],
      "options": {
        "colorMode": "background",
        "graphMode": "none",
        "justifyMode": "auto",
        "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
        "textMode": "auto"
      },
      "fieldConfig": {
        "defaults": {
          "mappings": [
            {"options": {"0": {"color": "red", "text": "OFFLINE"}, "1": {"color": "green", "text": "ONLINE"}}, "type": "value"}
          ]
        }
      }
    },
    {
      "type": "timeseries",
      "title": "CPU Usage - All Nodes (%)",
      "gridPos": {"x": 4, "y": 0, "w": 10, "h": 8},
      "targets": [
        {
          "expr": "100 - (avg by (host) (irate(node_cpu_seconds_total{mode=\"idle\", job=~\"cloud-node|edge-nodes\"}[5m])) * 100)",
          "legendFormat": "{{host}}",
          "datasource": {"type": "prometheus", "uid": "prometheus"}
        }
      ],
      "options": {
        "tooltip": {"mode": "multi"},
        "legend": {"displayMode": "table", "placement": "bottom", "calcs": ["last", "mean", "max"]}
      },
      "fieldConfig": {
        "defaults": {"custom": {"lineWidth": 2, "fillOpacity": 15, "gradientMode": "opacity"}, "unit": "percent"}
      }
    },
    {
      "type": "timeseries",
      "title": "Memory Usage - All Nodes (%)",
      "gridPos": {"x": 14, "y": 0, "w": 10, "h": 8},
      "targets": [
        {
          "expr": "100 * (1 - (node_memory_MemAvailable_bytes{job=~\"cloud-node|edge-nodes\"} / node_memory_MemTotal_bytes{job=~\"cloud-node|edge-nodes\"}))",
          "legendFormat": "{{host}}",
          "datasource": {"type": "prometheus", "uid": "prometheus"}
        }
      ],
      "options": {
        "tooltip": {"mode": "multi"},
        "legend": {"displayMode": "table", "placement": "bottom", "calcs": ["last", "max"]}
      },
      "fieldConfig": {
        "defaults": {"custom": {"lineWidth": 2, "fillOpacity": 15, "gradientMode": "opacity"}, "unit": "percent"}
      }
    },
    {
      "type": "timeseries",
      "title": "WireGuard Traffic (wg0) - Mbps",
      "gridPos": {"x": 0, "y": 8, "w": 12, "h": 7},
      "targets": [
        {
          "expr": "irate(node_network_receive_bytes_total{device=\"wg0\", job=~\"cloud-node|edge-nodes\"}[5m]) * 8 / 1000000",
          "legendFormat": "{{host}} - Inbound",
          "datasource": {"type": "prometheus", "uid": "prometheus"}
        },
        {
          "expr": "irate(node_network_transmit_bytes_total{device=\"wg0\", job=~\"cloud-node|edge-nodes\"}[5m]) * 8 / 1000000",
          "legendFormat": "{{host}} - Outbound",
          "datasource": {"type": "prometheus", "uid": "prometheus"}
        }
      ],
      "options": {"tooltip": {"mode": "multi"}, "legend": {"displayMode": "table", "placement": "right", "calcs": ["last"]}},
      "fieldConfig": {"defaults": {"custom": {"lineWidth": 2, "fillOpacity": 10}, "unit": "Mbps"}}
    },
    {
      "type": "timeseries",
      "title": "Physical / 5G Traffic (eth0, wwan) - Mbps",
      "gridPos": {"x": 12, "y": 8, "w": 12, "h": 7},
      "targets": [
        {
          "expr": "irate(node_network_receive_bytes_total{device=~\"eth0|wwan.*|rmnet.*\", job=~\"cloud-node|edge-nodes\"}[5m]) * 8 / 1000000",
          "legendFormat": "{{host}} ({{device}}) - Inbound",
          "datasource": {"type": "prometheus", "uid": "prometheus"}
        },
        {
          "expr": "irate(node_network_transmit_bytes_total{device=~\"eth0|wwan.*|rmnet.*\", job=~\"cloud-node|edge-nodes\"}[5m]) * 8 / 1000000",
          "legendFormat": "{{host}} ({{device}}) - Outbound",
          "datasource": {"type": "prometheus", "uid": "prometheus"}
        }
      ],
      "options": {"tooltip": {"mode": "multi"}, "legend": {"displayMode": "table", "placement": "right", "calcs": ["last"]}},
      "fieldConfig": {"defaults": {"custom": {"lineWidth": 2, "fillOpacity": 10}, "unit": "Mbps"}}
    }
  ]
}

os.makedirs("/home/hiengyen/CODE/wireguard-edge-cloud-5g/cloud/monitoring/grafana/provisioning/dashboards/definitions", exist_ok=True)
with open("/home/hiengyen/CODE/wireguard-edge-cloud-5g/cloud/monitoring/grafana/provisioning/dashboards/definitions/unified_edge_cloud.json", "w") as f:
    json.dump(dashboard, f, indent=2)

print("Unified dashboard generated.")
