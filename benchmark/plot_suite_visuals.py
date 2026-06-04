#!/usr/bin/env python3
"""Generate visual summary figures for every benchmark suite."""

from __future__ import annotations

import csv
import glob
import os
import re
from collections import defaultdict
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


ROOT = Path(__file__).resolve().parent
REPORTS = ROOT / "reports"
OUT = REPORTS / "suite_visuals"

COLORS = {
    "pass": "#2E8B57",
    "warn": "#F2A541",
    "fail": "#C43C39",
    "info": "#6C7A89",
    "blue": "#2E75B6",
    "light_blue": "#8FAADC",
    "red": "#E24A35",
    "yellow": "#FBC15E",
    "green": "#467821",
    "purple": "#7A68A6",
    "gray": "#E6E8EB",
}


def setup_style() -> None:
    plt.rcParams["font.family"] = "DejaVu Sans"
    plt.rcParams["font.size"] = 10
    plt.rcParams["axes.edgecolor"] = "#CCCCCC"
    plt.rcParams["axes.linewidth"] = 0.8
    plt.rcParams["grid.color"] = "#EEEEEE"
    plt.rcParams["grid.linewidth"] = 0.6
    plt.rcParams["legend.edgecolor"] = "#E0E0E0"
    plt.rcParams["legend.fancybox"] = True


def strip_ansi(text: str) -> str:
    return re.sub(r"\x1b\[[0-9;]*m", "", text)


def latest(pattern: str) -> Path | None:
    files = [Path(p) for p in glob.glob(str(REPORTS / pattern))]
    return max(files, key=lambda p: p.stat().st_mtime) if files else None


def read_latest(pattern: str) -> str:
    path = latest(pattern)
    if not path:
        return ""
    return strip_ansi(path.read_text(errors="ignore"))


def annotate_bars(ax, rects, fmt="{:.1f}", suffix=""):
    for rect in rects:
        height = rect.get_height()
        if height == 0:
            continue
        ax.annotate(
            fmt.format(height) + suffix,
            xy=(rect.get_x() + rect.get_width() / 2, height),
            xytext=(0, 4),
            textcoords="offset points",
            ha="center",
            va="bottom",
            fontsize=8,
            color="#333333",
        )


def save(fig, name: str) -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    fig.savefig(path, dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved {path}")
    return path


def parse_run_all():
    text = read_latest("run_all_*.log")
    rows = []
    for line in text.splitlines():
        m = re.match(r"(?P<label>.+): P=(?P<p>\d+) F=(?P<f>\d+) W=(?P<w>\d+) t=(?P<t>\d+)s", line)
        if not m:
            continue
        label = m.group("label")
        suite = label[:2]
        rows.append(
            {
                "suite": suite,
                "label": label,
                "pass": int(m.group("p")),
                "fail": int(m.group("f")),
                "warn": int(m.group("w")),
                "time": int(m.group("t")),
            }
        )
    return rows


def plot_overview(rows):
    setup_style()
    suites = ["01", "02", "03", "04", "05"]
    names = ["01\nConnectivity", "02\nBandwidth", "03\nServices", "04\nLoad", "05\nE2E"]
    agg = {s: {"pass": 0, "warn": 0, "fail": 0, "time": 0} for s in suites}
    for row in rows:
        if row["suite"] in agg:
            for key in ["pass", "warn", "fail", "time"]:
                agg[row["suite"]][key] += row[key]

    x = np.arange(len(suites))
    p = np.array([agg[s]["pass"] for s in suites])
    w = np.array([agg[s]["warn"] for s in suites])
    f = np.array([agg[s]["fail"] for s in suites])
    times = np.array([agg[s]["time"] for s in suites])

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5), gridspec_kw={"width_ratios": [1.3, 1]})
    ax1.bar(x, p, label="PASS", color=COLORS["pass"])
    ax1.bar(x, w, bottom=p, label="WARN", color=COLORS["warn"])
    ax1.bar(x, f, bottom=p + w, label="FAIL", color=COLORS["fail"])
    ax1.set_title("Tổng quan kết quả theo suite", fontweight="bold")
    ax1.set_ylabel("Số kiểm tra")
    ax1.set_xticks(x)
    ax1.set_xticklabels(names)
    ax1.grid(True, axis="y", alpha=0.7)
    ax1.legend(loc="upper center", bbox_to_anchor=(0.5, -0.16), ncol=3, frameon=True)
    for i, total in enumerate(p + w + f):
        ax1.text(i, total + 0.8, f"{int(total)}", ha="center", fontsize=9)

    rects = ax2.bar(x, times, color=COLORS["blue"])
    ax2.set_title("Thời gian chạy suite", fontweight="bold")
    ax2.set_ylabel("Giây")
    ax2.set_xticks(x)
    ax2.set_xticklabels([s for s in suites])
    ax2.grid(True, axis="y", alpha=0.7)
    annotate_bars(ax2, rects, fmt="{:.0f}", suffix="s")

    fig.suptitle("Benchmark run_all.sh - PASS/WARN/FAIL và thời gian chạy", fontsize=14, fontweight="bold")
    fig.tight_layout(rect=[0, 0.08, 1, 0.95])
    save(fig, "suite_00_overview.png")


def extract_ping_values():
    text = read_latest("test_ping_latency_*.log")
    rows = []
    for label, pattern in [
        ("WireGuard overlay", r"WG-overlay.*?avg=([\d.]+)ms.*?jitter=([\d.]+)ms.*?loss=([\d.]+)%"),
        ("5G uplink", r"5G-uplink.*?avg=([\d.]+)ms.*?jitter=([\d.]+)ms.*?loss=([\d.]+)%"),
    ]:
        m = re.search(pattern, text)
        if m:
            rows.append((label, float(m.group(1)), float(m.group(2)), float(m.group(3))))
    return rows


def plot_suite_01():
    setup_style()
    ping_rows = extract_ping_values()
    wg_text = read_latest("test_wg_tunnel_*.log")
    signal_text = read_latest("test_5g_signal_*.log")

    handshake = re.search(r"last handshake (\d+)s ago", wg_text)
    traffic = re.search(r"Traffic flowing: RX=(\d+)B TX=(\d+)B", wg_text)
    ip_addr = re.search(r"WWAN interface has IP: ([^\n]+)", signal_text)
    data_bytes = re.search(r"Data session: TX=(\d+)B RX=(\d+)B", signal_text)

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5), gridspec_kw={"width_ratios": [1.2, 1]})

    if ping_rows:
        labels = [r[0] for r in ping_rows]
        latency = [r[1] for r in ping_rows]
        jitter = [r[2] for r in ping_rows]
        x = np.arange(len(labels))
        width = 0.35
        b1 = ax1.bar(x - width / 2, latency, width, label="RTT avg", color=COLORS["blue"])
        b2 = ax1.bar(x + width / 2, jitter, width, label="Jitter", color=COLORS["yellow"])
        ax1.set_title("Độ trễ kết nối 5G và WireGuard", fontweight="bold")
        ax1.set_ylabel("ms")
        ax1.set_xticks(x)
        ax1.set_xticklabels(labels)
        ax1.grid(True, axis="y", alpha=0.7)
        ax1.legend(loc="upper center", bbox_to_anchor=(0.5, -0.14), ncol=2, frameon=True)
        annotate_bars(ax1, b1, suffix="ms")
        annotate_bars(ax1, b2, suffix="ms")
    else:
        ax1.text(0.5, 0.5, "Không có dữ liệu ping", ha="center", va="center")
        ax1.axis("off")

    metrics = []
    if handshake:
        metrics.append(("WG handshake age", float(handshake.group(1)), "s"))
    if traffic:
        metrics.append(("WG RX", int(traffic.group(1)) / 1048576, "MiB"))
        metrics.append(("WG TX", int(traffic.group(2)) / 1048576, "MiB"))
    if data_bytes:
        metrics.append(("WWAN TX", int(data_bytes.group(1)) / 1048576, "MiB"))
        metrics.append(("WWAN RX", int(data_bytes.group(2)) / 1048576, "MiB"))

    if metrics:
        labels = [m[0] for m in metrics]
        vals = [m[1] for m in metrics]
        rects = ax2.barh(labels, vals, color=[COLORS["green"], COLORS["blue"], COLORS["light_blue"], COLORS["purple"], COLORS["yellow"]][: len(labels)])
        ax2.set_title("Trạng thái tunnel và WWAN", fontweight="bold")
        ax2.grid(True, axis="x", alpha=0.7)
        for rect, (_, val, unit) in zip(rects, metrics):
            ax2.text(rect.get_width() * 1.01, rect.get_y() + rect.get_height() / 2, f"{val:.1f} {unit}", va="center", fontsize=8)
    else:
        ax2.text(0.5, 0.5, "Không có dữ liệu trạng thái", ha="center", va="center")
        ax2.axis("off")

    subtitle = f"WWAN IP: {ip_addr.group(1)}" if ip_addr else "WWAN IP: n/a"
    fig.suptitle(f"Suite 01 - Connectivity: ICMP, WireGuard tunnel, 5G signal\n{subtitle}", fontsize=14, fontweight="bold")
    fig.tight_layout(rect=[0, 0.08, 1, 0.9])
    save(fig, "suite_01_connectivity.png")


def parse_tcp_rows():
    text = read_latest("test_iperf3_tcp_*.log")
    rows = []
    for m in re.finditer(r"INFO\s+(TCP-[^:]+):\s+([\d.]+)\s+Mbps\s+retransmits=(\d+|\?)", text):
        label = m.group(1).strip()
        rows.append((label, float(m.group(2)), 0 if m.group(3) == "?" else int(m.group(3))))
    return rows


def parse_udp_rows():
    text = read_latest("test_iperf3_udp_*.log")
    rows = []
    for m in re.finditer(r"INFO\s+(UDP-[^:]+):\s+([\d.]+)\s+Mbps\s+jitter=([\d.]+)ms\s+loss=([\d.]+)%", text):
        rows.append((m.group(1).strip(), float(m.group(2)), float(m.group(3)), float(m.group(4))))
    return rows


def plot_suite_02():
    setup_style()
    tcp = parse_tcp_rows()
    udp = parse_udp_rows()
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 8), gridspec_kw={"height_ratios": [1, 1.2]})

    if tcp:
        labels = [r[0].replace("TCP-", "") for r in tcp]
        vals = [r[1] for r in tcp]
        retrans = [r[2] for r in tcp]
        x = np.arange(len(labels))
        colors = [COLORS["blue"] if r <= 100 else COLORS["warn"] for r in retrans]
        rects = ax1.bar(x, vals, color=colors)
        ax1.set_title("TCP throughput qua WireGuard", fontweight="bold")
        ax1.set_ylabel("Mbps")
        ax1.set_xticks(x)
        ax1.set_xticklabels(labels, rotation=12, ha="right")
        ax1.grid(True, axis="y", alpha=0.7)
        annotate_bars(ax1, rects, suffix=" Mbps")
        for i, r in enumerate(retrans):
            ax1.text(i, vals[i] * 0.08, f"reTX={r}", ha="center", color="white", fontsize=8, fontweight="bold")
    else:
        ax1.text(0.5, 0.5, "Không có dữ liệu TCP", ha="center", va="center")
        ax1.axis("off")

    if udp:
        labels = [r[0].replace("UDP-", "") for r in udp]
        mbps = [r[1] for r in udp]
        jitter = [r[2] for r in udp]
        loss = [r[3] for r in udp]
        x = np.arange(len(labels))
        rects = ax2.bar(x, mbps, color=COLORS["green"], label="Throughput")
        ax2.set_title("UDP throughput, jitter và loss", fontweight="bold")
        ax2.set_ylabel("Mbps")
        ax2.set_xticks(x)
        ax2.set_xticklabels(labels, rotation=20, ha="right")
        ax2.grid(True, axis="y", alpha=0.7)
        annotate_bars(ax2, rects, suffix=" Mbps")
        ax3 = ax2.twinx()
        ax3.plot(x, jitter, color=COLORS["red"], marker="o", linewidth=2, label="Jitter")
        ax3.plot(x, loss, color=COLORS["purple"], marker="s", linewidth=2, label="Loss")
        ax3.set_ylabel("Jitter ms / Loss %")
        h1, l1 = ax2.get_legend_handles_labels()
        h2, l2 = ax3.get_legend_handles_labels()
        ax2.legend(h1 + h2, l1 + l2, loc="upper center", bbox_to_anchor=(0.5, -0.32), ncol=3, frameon=True)
    else:
        ax2.text(0.5, 0.5, "Không có dữ liệu UDP", ha="center", va="center")
        ax2.axis("off")

    fig.suptitle("Suite 02 - Bandwidth: TCP/UDP iperf3, rsync, WireGuard overhead", fontsize=14, fontweight="bold")
    fig.tight_layout(rect=[0, 0.06, 1, 0.95])
    save(fig, "suite_02_bandwidth.png")


def parse_summary_reports(prefix: str):
    rows = []
    for path in sorted(REPORTS.glob(f"{prefix}-*.txt")):
        text = path.read_text(errors="ignore")
        m = re.search(r"PASS=(\d+)\s+FAIL=(\d+)\s+WARN=(\d+)", text)
        if not m:
            continue
        name = path.stem
        name = re.sub(r"_\d{8}_\d{6}$", "", name)
        name = re.sub(r"^\d+-", "", name)
        rows.append((name, int(m.group(1)), int(m.group(2)), int(m.group(3))))
    return rows


def plot_suite_03():
    setup_style()
    rows = parse_summary_reports("03")
    prom = read_latest("test_prometheus_*.log")
    latencies = []
    for name, pattern in [
        ("Prometheus query", r"Query API latency: (\d+)ms"),
        ("Loki ready", r"Loki ready latency: (\d+)ms"),
        ("Grafana API", r"Grafana API latency: (\d+)ms"),
    ]:
        source = prom if name.startswith("Prometheus") else read_latest("test_loki_*.log" if name.startswith("Loki") else "test_grafana_*.log")
        m = re.search(pattern, source)
        if m:
            latencies.append((name, int(m.group(1))))

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5), gridspec_kw={"width_ratios": [1.1, 1]})

    if latencies:
        labels = [r[0] for r in latencies]
        vals = [r[1] for r in latencies]
        rects = ax1.bar(labels, vals, color=[COLORS["blue"], COLORS["purple"], COLORS["green"]][: len(labels)])
        ax1.set_title("Độ trễ API dịch vụ giám sát", fontweight="bold")
        ax1.set_ylabel("ms")
        ax1.set_xticks(np.arange(len(labels)))
        ax1.set_xticklabels(labels, rotation=15, ha="right")
        ax1.grid(True, axis="y", alpha=0.7)
        annotate_bars(ax1, rects, fmt="{:.0f}", suffix="ms")
    else:
        ax1.text(0.5, 0.5, "Không có dữ liệu latency", ha="center", va="center")
        ax1.axis("off")

    if rows:
        labels = [r[0] for r in rows]
        p = np.array([r[1] for r in rows])
        f = np.array([r[2] for r in rows])
        w = np.array([r[3] for r in rows])
        x = np.arange(len(labels))
        ax2.bar(x, p, color=COLORS["pass"], label="PASS")
        ax2.bar(x, w, bottom=p, color=COLORS["warn"], label="WARN")
        ax2.bar(x, f, bottom=p + w, color=COLORS["fail"], label="FAIL")
        ax2.set_title("Kết quả từng dịch vụ", fontweight="bold")
        ax2.set_ylabel("Số kiểm tra")
        ax2.set_xticks(x)
        ax2.set_xticklabels(labels, rotation=15, ha="right")
        ax2.grid(True, axis="y", alpha=0.7)
        ax2.legend(loc="upper center", bbox_to_anchor=(0.5, -0.24), ncol=3, frameon=True)
    else:
        ax2.text(0.5, 0.5, "Không có summary service", ha="center", va="center")
        ax2.axis("off")

    fig.suptitle("Suite 03 - Services: Prometheus, Loki, Grafana, Node Exporter", fontsize=14, fontweight="bold")
    fig.tight_layout(rect=[0, 0.08, 1, 0.94])
    save(fig, "suite_03_services.png")


def parse_sustained_csv():
    path = latest("sustained_*.csv")
    data = defaultdict(list)
    if not path:
        return data
    for row in csv.reader(path.read_text(errors="ignore").splitlines()):
        if len(row) != 3 or row[0] == "label":
            continue
        try:
            data[row[0].strip()].append((float(row[1]), float(row[2])))
        except ValueError:
            continue
    return data


def parse_monitoring_load():
    text = read_latest("test_monitoring_load_*.log")
    rows = []
    for m in re.finditer(r"INFO\s+([^:]+): n=\d+ fail=\d+ mean=(\d+)ms .*?p95=(\d+)ms", text):
        rows.append((m.group(1), int(m.group(2)), int(m.group(3))))
    return rows


def plot_suite_04():
    setup_style()
    sustained = parse_sustained_csv()
    load = parse_monitoring_load()
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 5), gridspec_kw={"width_ratios": [1.3, 1]})

    if sustained:
        palette = [COLORS["blue"], COLORS["red"], COLORS["green"]]
        for idx, (label, points) in enumerate(sustained.items()):
            xs = [p[0] for p in points]
            ys = [p[1] for p in points]
            ax1.plot(xs, ys, marker="o", linewidth=2, label=label, color=palette[idx % len(palette)])
        ax1.set_title("Sustained bandwidth 60s", fontweight="bold")
        ax1.set_xlabel("Giây")
        ax1.set_ylabel("Mbps")
        ax1.grid(True, alpha=0.7)
        ax1.legend(loc="upper center", bbox_to_anchor=(0.5, -0.16), ncol=1, frameon=True)
    else:
        ax1.text(0.5, 0.5, "Không có dữ liệu sustained bandwidth", ha="center", va="center")
        ax1.axis("off")

    if load:
        labels = [r[0] for r in load]
        p95 = [r[2] for r in load]
        colors = [COLORS["blue"] if v < 300 else COLORS["warn"] for v in p95]
        x = np.arange(len(labels))
        rects = ax2.bar(x, p95, color=colors)
        ax2.set_title("Monitoring load p95 latency", fontweight="bold")
        ax2.set_ylabel("ms")
        ax2.set_xticks(x)
        ax2.set_xticklabels(labels, rotation=30, ha="right")
        ax2.grid(True, axis="y", alpha=0.7)
        annotate_bars(ax2, rects, fmt="{:.0f}", suffix="ms")
    else:
        ax2.text(0.5, 0.5, "Không có dữ liệu monitoring load", ha="center", va="center")
        ax2.axis("off")

    fig.suptitle("Suite 04 - Load: sustained bandwidth và monitoring API load", fontsize=14, fontweight="bold")
    fig.tight_layout(rect=[0, 0.1, 1, 0.94])
    save(fig, "suite_04_load.png")


def parse_phase_statuses():
    text = read_latest("test_full_stack_*.log")
    phases = {
        "P1": {"label": "5G physical", "status": "info", "detail": ""},
        "P2": {"label": "WireGuard", "status": "info", "detail": ""},
        "P3": {"label": "Services", "status": "info", "detail": ""},
        "P4": {"label": "Metrics", "status": "info", "detail": ""},
        "P5": {"label": "Logs", "status": "info", "detail": ""},
        "P6": {"label": "Bandwidth", "status": "info", "detail": ""},
        "P7": {"label": "SSH", "status": "info", "detail": "skipped"},
    }
    priority = {"pass": 1, "info": 2, "warn": 3, "fail": 4}
    for line in text.splitlines():
        m = re.search(r"(PASS|WARN|FAIL|INFO)\s+(P[1-7]):\s+(.+)", line)
        if not m:
            continue
        status = m.group(1).lower()
        phase = m.group(2)
        detail = m.group(3)
        if priority[status] >= priority[phases[phase]["status"]]:
            phases[phase]["status"] = status
            phases[phase]["detail"] = detail
    return phases


def plot_suite_05():
    setup_style()
    phases = parse_phase_statuses()
    fig, ax = plt.subplots(figsize=(13, 4.8))
    xs = np.arange(len(phases))
    y = np.zeros(len(phases))
    status_colors = {
        "pass": COLORS["pass"],
        "warn": COLORS["warn"],
        "fail": COLORS["fail"],
        "info": COLORS["info"],
    }

    ax.plot(xs, y, color="#B8C2CC", linewidth=3, zorder=1)
    for i, (phase, item) in enumerate(phases.items()):
        color = status_colors[item["status"]]
        ax.scatter(i, 0, s=950, color=color, edgecolor="white", linewidth=2, zorder=2)
        ax.text(i, 0, phase, ha="center", va="center", color="white", fontweight="bold", fontsize=11, zorder=3)
        ax.text(i, -0.22, item["label"], ha="center", va="top", fontsize=9, fontweight="bold")
        detail = item["detail"]
        detail = re.sub(r"\s+", " ", detail)
        if len(detail) > 42:
            detail = detail[:39] + "..."
        ax.text(i, 0.24, detail, ha="center", va="bottom", fontsize=8, color="#333333", rotation=10)

    ax.set_xlim(-0.6, len(phases) - 0.4)
    ax.set_ylim(-0.45, 0.55)
    ax.axis("off")
    legend_handles = [
        plt.Line2D([0], [0], marker="o", color="w", label="PASS", markerfacecolor=COLORS["pass"], markersize=10),
        plt.Line2D([0], [0], marker="o", color="w", label="WARN", markerfacecolor=COLORS["warn"], markersize=10),
        plt.Line2D([0], [0], marker="o", color="w", label="INFO/SKIP", markerfacecolor=COLORS["info"], markersize=10),
        plt.Line2D([0], [0], marker="o", color="w", label="FAIL", markerfacecolor=COLORS["fail"], markersize=10),
    ]
    ax.legend(handles=legend_handles, loc="upper center", bbox_to_anchor=(0.5, -0.03), ncol=4, frameon=True)
    fig.suptitle("Suite 05 - Full stack end-to-end validation flow", fontsize=14, fontweight="bold")
    fig.tight_layout(rect=[0, 0.08, 1, 0.9])
    save(fig, "suite_05_e2e_flow.png")


def main():
    rows = parse_run_all()
    if not rows:
        raise SystemExit("No run_all_*.log found in benchmark/reports")
    plot_overview(rows)
    plot_suite_01()
    plot_suite_02()
    plot_suite_03()
    plot_suite_04()
    plot_suite_05()
    print(f"\nGenerated suite visuals in {OUT}")


if __name__ == "__main__":
    main()
