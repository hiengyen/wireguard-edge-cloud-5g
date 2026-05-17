# 📊 WireGuard 5G Edge Observability Dashboard Blueprint

This document details the newly designed **Grafana Loki Dashboard** specifically customized to monitor your WireGuard Edge-Cloud 5G overlay network, system hardening, and 5G Quectel cellular modem logs.

> [!IMPORTANT]
> **Zero-Touch Provisioning Enabled!**  
> We have automated the loading of this dashboard. It is configured directly inside the Grafana provisioning directory:
> - Config Provider: `cloud/monitoring/grafana/provisioning/dashboards/dashboards.yml`
> - Dashboard JSON: `cloud/monitoring/grafana/provisioning/dashboards/loki_edge_5g.json`
>
> When you start or restart your monitoring Docker containers, Grafana will **automatically import and configure** this dashboard for you. No manual JSON copy-pasting is required.

---

## 🏗️ Dashboard Layout & Panel Blueprints

The dashboard is structured into 4 dedicated rows matching the lifecycle of your Edge nodes:

### 1. 📊 System Overview & Logs Rate
*   **Total Logs Count (Stat Panel):** Shows the absolute volume of logs received during the selected time range.
    *   *LogQL Query:* `sum(count_over_time({job="$job", host=~"$host"}[$__range]))`
*   **Donut Breakdown (Pie Chart):** Visually identifies which Systemd units are logging the most, using regular expression matching to parse the process name.
    *   *LogQL Query:* `sum by (unit) (count_over_time({job="$job", host=~"$host"} | regexp "^.*? (?P<unit>[a-zA-Z0-9\-_.]+)(?:\[\d+\])?:" [$__interval]))`

### 2. 🌐 5G Cellular Status & WireGuard VPN Overlay
*   **5G Modem & QMI Connection (Logs Panel):** Isolates cellular network events (Quectel dynamic detection, raw IP configuration, APN handshake, cellular disconnects/reconnects).
    *   *LogQL Query:* `{job="$job", host=~"$host"} |~ "(?i)(wwan|quectel|qmi|cdc-wdm|apn|sim|signal|disconnect|reconnect|cm)"`
*   **WireGuard Overlay VPN (Logs Panel):** Focuses entirely on WireGuard health, handshake status, and network reachability.
    *   *LogQL Query:* `{job="$job", host=~"$host"} |~ "(?i)(wireguard|wg0|handshake|peer|keepalive|endpoint)"`

### 3. 🛡️ System Hardening & Security (SSH / UFW / Fail2Ban)
*   **Security Logs (Logs Panel):** Captures unauthorized access attempts, SSH login failures, brute-force bans from Fail2Ban, and packets blocked by the UFW/Firewalld firewalls.
    *   *LogQL Query:* `{job="$job", host=~"$host"} |~ "(?i)(sshd.*(Failed|Accepted|invalid)|fail2ban.*Ban|ufw.*BLOCK|firewall)"`
*   **Intrusion Attempts Blocked (Stat Panel):** Displays a red alarming counter if security systems are active and blocking attacks.
    *   *LogQL Query:* `sum(count_over_time({job="$job", host=~"$host"} |~ "(?i)(sshd.*Failed|fail2ban.*Ban)" [$__range]))`

### 4. 🚨 Critical Systems & Kernel Alarms
*   **Hardware & Memory Crash Alarms (Logs Panel):** Dedicated panel to isolate OOM (Out Of Memory) kills, kernel panics, segment faults, or systemd services that failed to start.
    *   *LogQL Query:* `{job="$job", host=~"$host"} |~ "(?i)(oom|panic|hardware error|segfault|kill|aborted|critical|exception|failed to start)"`

---

## 🚀 How to Load and Access

### Step 1: Restart your Cloud Monitoring stack
To force Grafana to read the new provisioning config:

```bash
cd cloud/monitoring
sudo -E docker compose --env-file ../../.env down
sudo -E docker compose --env-file ../../.env up -d
```

### Step 2: Access Grafana via SSH Tunnel (or directly over WireGuard)
If monitoring over WireGuard is enabled:
- Open your browser to: `http://10.8.0.1:3000`

If accessing via SSH Tunnel:
```bash
ssh -i <your-key.pem> -N -L 3000:10.8.0.1:3000 ec2-user@<EC2_PUBLIC_IP>
# Then open http://127.0.0.1:3000
```

### Step 3: Open the Dashboard
1. Log in to Grafana.
2. Go to **Dashboards** in the left menu.
3. You will see a folder named **Edge Monitoring**.
4. Click on **WireGuard 5G Edge Log Dashboard**.

---

## 🛠️ Dynamic Variables Explained
At the top of the dashboard, you will find two drop-down selectors:
*   **`Job`**: Automatically populated with available jobs (defaults to `edge-journal`).
*   **`Edge Host`**: Automatically dynamically lists all Edge hosts sending logs to Loki. If you deploy to 10 Orange Pi devices, they will all automatically appear in this drop-down list! You can select "All" or filter down to a single device.
