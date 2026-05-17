# WireGuard 5G Edge Observability Dashboard Blueprint

This document details the newly designed, high-performance **Grafana Loki Dashboard** specifically customized to monitor your WireGuard Edge-Cloud 5G overlay network, system hardening, and 5G Quectel cellular modem logs.

> [!IMPORTANT]
> **Zero-Touch Provisioning Enabled!**  
> We have automated the loading of this dashboard. It is configured directly inside the Grafana provisioning directory:
> - Config Provider: `cloud/monitoring/grafana/provisioning/dashboards/dashboards.yml`
> - Dashboard JSON: `cloud/monitoring/grafana/provisioning/dashboards/definitions/loki_edge_5g.json`
>
> When you start or restart your monitoring Docker containers, Grafana will **automatically import and configure** this dashboard for you. No manual JSON copy-pasting is required.

---

## 🏗️ Dashboard Layout & Panel Blueprints

The dashboard is structured into a clean, **100% full-width vertically stacked layout** (`w: 24`) designed for high-density log reading without side-by-side splits. The rows use a flat, modern typography aesthetic:

### 1. SYSTEM OVERVIEW & LOGS RATE
*   **Total Logs Received (Stat Panel):** Shows the total logs received across all nodes.
    *   *LogQL Query:* `sum(count_over_time({job="$job", host=~"$host"}[$__range]))`
*   **Log Distribution by Service / Systemd Unit (Donut Chart):** Shows which services are generating the most logs.
    *   *Layout Optimization:* Donut slice labels are disabled (`displayLabels: []`) to keep the visual clean and uncluttered. It relies on the interactive **Table Legend** on the right, which displays absolute log count and percentages.
    *   *LogQL Query:* `sum by (unit) (count_over_time({job="$job", host=~"$host"} | regexp "^.*? (?P<unit>[a-zA-Z0-9\-_.]+)(?:\[\d+\])?:" [$__interval]))`

### 2. 5G CELLULAR & WIREGUARD VPN OVERLAY MONITORING
*   **5G Modem & Cellular Connection Logs (Logs Panel):** Focuses on cellular dynamic detection, raw IP configuration, APN handshakes, and WWAN disconnect/reconnect signals.
    *   *LogQL Query:* `{job="$job", host=~"$host"} |~ "(?i)(wwan|quectel|qmi|cdc-wdm|apn|sim|signal|disconnect|reconnect|cm)"`
*   **WireGuard Secure VPN Overlay Logs (Logs Panel):** Tracks secure VPN tunnel health, keepalives, and peer handshakes.
    *   *LogQL Query:* `{job="$job", host=~"$host"} |~ "(?i)(\bwireguard\b|wg0|handshake|peer|keepalive|endpoint)"`

### 3. SYSTEM SECURITY & HARDENING (SSH & FIREWALL)
*   **Blocked Intrusion Attempts per Node (Stat Panel):** Displays an alarming red card counting failed SSH logins or Fail2Ban bans, grouped automatically by host.
    *   *LogQL Query:* `sum by (host) (count_over_time({job="$job", host=~"$host"} |~ "(?i)(sshd.*Failed|fail2ban.*Ban)" [$__range]))`
*   **Security History & Blocked Attacks (Logs Panel):** Aggregates direct unauthorized SSH attempts, UFW/Firewalld block alerts, and iptables warnings.
    *   *LogQL Query:* `{job="$job", host=~"$host"} |~ "(?i)(sshd.*(Failed|Accepted|invalid)|fail2ban.*Ban|ufw.*BLOCK|firewall)"`

### 4. SYSTEM ALERTS & KERNEL PANICS
*   **Critical System & Kernel Logs (Logs Panel):** Isolates critical system issues like Out-Of-Memory (OOM) kills, kernel panics, hardware errors, segment faults, or crashed Systemd units.
    *   *LogQL Query:* `{job="$job", host=~"$host"} |~ "(?i)(oom|panic|hardware error|segfault|kill|aborted|critical|exception|failed to start)"`

---

## 🛡️ Production Hardening: Docker Log Rotation

To prevent container logs (from Loki, Prometheus, and Grafana) from consuming all available disk space over long runtimes, we have implemented automated **Docker Log Rotation** inside `cloud/monitoring/docker-compose.yml`:

```yaml
    logging:
      driver: "json-file"
      options:
        max-size: "50m" # Keep each log file under 50MB
        max-file: "3"   # Maintain at most 3 historical files per container (max 150MB total)
```

---

## 🧪 Simulating and Testing Critical Alarms

Because your systems operate healthily under normal circumstances, the **SYSTEM ALERTS & KERNEL PANICS** panel will naturally display `"No data"`.

To safely test this panel and verify that the monitoring pipeline is working, you can simulate a critical crash event by writing to system logs:

### Option A: Trigger on the Cloud Gateway (or Edge) via CLI
Log in to your host and execute:
```bash
logger "TEST ALERT: segfault crash in user-app, critical exception triggered"
```

### Option B: Trigger a Service Failure Simulation
```bash
logger "TEST: systemd-hostfailed failed to start wireguard service critical exception"
```

Within **5 to 10 seconds**, Grafana will pick up these logs, and they will immediately appear inside your **Critical System & Kernel Logs** panel in bold!

---

## 🚀 How to Apply and Run

### Step 1: Apply the configuration
Run the command below in the cloud gateway workspace:

```bash
cd cloud/monitoring
sudo -E docker compose --env-file ../../.env up -d --force-recreate
```

### Step 2: Access Grafana UIs
If using a WireGuard overlay, access directly at: `http://10.8.0.1:3000`  
Otherwise, set up an SSH tunnel:
```bash
ssh -i <your-key.pem> -N -L 3000:10.8.0.1:3000 ec2-user@<EC2_PUBLIC_IP>
```
Open your browser to `http://127.0.0.1:3000`.

---

## 🛠️ Dynamic Variables Explained
At the top of the dashboard, you will find two drop-down selectors:
*   **`Job`**: Set of jobs (defaults to `edge-journal`).
*   **`Node / Host`**: Automatically dynamically lists all Cloud and Edge hosts pushing logs. If you select "All", statistics are aggregated; or you can filter down to one specific host.
