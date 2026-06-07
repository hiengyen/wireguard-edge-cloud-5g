#!/usr/bin/env python3
import os
import re
import sys
import glob
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

def setup_style():
    # Set premium plotting styles
    plt.rcParams['font.family'] = 'DejaVu Sans'
    plt.rcParams['font.size'] = 11
    plt.rcParams['axes.edgecolor'] = '#CCCCCC'
    plt.rcParams['axes.linewidth'] = 0.8
    plt.rcParams['grid.color'] = '#EEEEEE'
    plt.rcParams['grid.linewidth'] = 0.5
    plt.rcParams['legend.edgecolor'] = '#E0E0E0'
    plt.rcParams['legend.fancybox'] = True

def clean_float(val):
    if not val:
        return 0.0
    if isinstance(val, (int, float)):
        return float(val)
    # Extract only digit, dot, minus characters
    cleaned = re.sub(r'[^\d\.\-]', '', str(val))
    try:
        return float(cleaned) if cleaned else 0.0
    except ValueError:
        return 0.0

def parse_latest_logs(reports_dir):
    metrics = {
        'direct_down': 0.0, 'direct_up': 0.0,
        'wg_down': 0.0, 'wg_up': 0.0,
        'direct_lat': 0.0, 'direct_jit': 0.0,
        'wg_lat': 0.0, 'wg_jit': 0.0,
        'wg_cpu': 0.0, 'wg_ram': 0.0
    }
    
    # 1. Parse Latency Log
    ping_logs = glob.glob(os.path.join(reports_dir, "test_ping_latency_*.log"))
    if ping_logs:
        latest_ping_log = max(ping_logs, key=os.path.getmtime)
        print(f"Parsing ping latency from: {os.path.basename(latest_ping_log)}")
        with open(latest_ping_log, 'r') as f:
            content = f.read()
            # Clean ANSI colors
            content = re.sub(r'\x1b\[[0-9;]*m', '', content)
            
            # Parse WG-overlay line
            wg_match = re.search(r'WG-overlay → cloud-gateway.*?min=(\S+).*?avg=(\S+).*?max=(\S+).*?jitter=(\S+)\s+(\S+)\s+(\S+)', content)
            if wg_match:
                # If there was a parsing bug in the script where min="mdev", avg="=", max="val", jitter="min avg mdev"
                if wg_match.group(1) == "mdev" and wg_match.group(2) == "=":
                    metrics['wg_lat'] = clean_float(wg_match.group(5)) # actual average
                    metrics['wg_jit'] = clean_float(wg_match.group(6)) # actual jitter
                else:
                    metrics['wg_lat'] = clean_float(wg_match.group(2))
                    metrics['wg_jit'] = clean_float(wg_match.group(4))
            else:
                # Try fallback matching for corrected script output
                wg_match_correct = re.search(r'WG-overlay → cloud-gateway.*?avg=([\d\.]+)ms.*?jitter=([\d\.]+)ms', content)
                if wg_match_correct:
                    metrics['wg_lat'] = clean_float(wg_match_correct.group(1))
                    metrics['wg_jit'] = clean_float(wg_match_correct.group(2))
                else:
                    # Generic RTT parser
                    wg_match_rtt = re.search(r'WG-overlay → cloud-gateway.*?RTT=([\d\.]+)ms.*?jitter=([\d\.]+)ms', content)
                    if wg_match_rtt:
                        metrics['wg_lat'] = clean_float(wg_match_rtt.group(1))
                        metrics['wg_jit'] = clean_float(wg_match_rtt.group(2))

            # Parse 5G-uplink line
            direct_match = re.search(r'5G-uplink → 8.8.8.8.*?min=(\S+).*?avg=(\S+).*?max=(\S+).*?jitter=(\S+)\s+(\S+)\s+(\S+)', content)
            if direct_match:
                if direct_match.group(1) == "mdev" and direct_match.group(2) == "=":
                    metrics['direct_lat'] = clean_float(direct_match.group(5))
                    metrics['direct_jit'] = clean_float(direct_match.group(6))
                else:
                    metrics['direct_lat'] = clean_float(direct_match.group(2))
                    metrics['direct_jit'] = clean_float(direct_match.group(4))
            else:
                direct_match_correct = re.search(r'5G-uplink → 8.8.8.8.*?avg=([\d\.]+)ms.*?jitter=([\d\.]+)ms', content)
                if direct_match_correct:
                    metrics['direct_lat'] = clean_float(direct_match_correct.group(1))
                    metrics['direct_jit'] = clean_float(direct_match_correct.group(2))
                else:
                    direct_match_rtt = re.search(r'5G-uplink → 8.8.8.8.*?RTT=([\d\.]+)ms.*?jitter=([\d\.]+)ms', content)
                    if direct_match_rtt:
                        metrics['direct_lat'] = clean_float(direct_match_rtt.group(1))
                        metrics['direct_jit'] = clean_float(direct_match_rtt.group(2))

    # 2. Parse TCP Bandwidth Log
    tcp_logs = glob.glob(os.path.join(reports_dir, "test_iperf3_tcp_*.log"))
    if tcp_logs:
        latest_tcp_log = max(tcp_logs, key=os.path.getmtime)
        print(f"Parsing TCP bandwidth from: {os.path.basename(latest_tcp_log)}")
        with open(latest_tcp_log, 'r') as f:
            content = f.read()
            content = re.sub(r'\x1b\[[0-9;]*m', '', content)
            
            # Since the script runs iperf3 over WireGuard by default
            wg_down_match = re.search(r'TCP-downlink.*:\s+([\d\.]+)\s+Mbps', content)
            if wg_down_match:
                metrics['wg_down'] = float(wg_down_match.group(1))
            wg_up_match = re.search(r'TCP-uplink.*:\s+([\d\.]+)\s+Mbps', content)
            if wg_up_match:
                metrics['wg_up'] = float(wg_up_match.group(1))

    # 3. Parse Overhead Log (for Direct vs VPN comparison if available)
    overhead_logs = glob.glob(os.path.join(reports_dir, "test_wg_overhead_*.log"))
    if overhead_logs:
        latest_oh_log = max(overhead_logs, key=os.path.getmtime)
        print(f"Parsing WireGuard overhead from: {os.path.basename(latest_oh_log)}")
        with open(latest_oh_log, 'r') as f:
            content = f.read()
            content = re.sub(r'\x1b\[[0-9;]*m', '', content)
            
            # If we had direct vs VPN values in the overhead log
            direct_down_match = re.search(r'Direct download:\s+([\d\.]+)\s+Mbps', content)
            if direct_down_match:
                metrics['direct_down'] = float(direct_down_match.group(1))
            direct_up_match = re.search(r'Direct upload:\s+([\d\.]+)\s+Mbps', content)
            if direct_up_match:
                metrics['direct_up'] = float(direct_up_match.group(1))

    return metrics

def annotate_no_data(ax, title, message):
    ax.set_title(title, fontsize=12, fontweight='bold', pad=15)
    ax.text(0.5, 0.5, message, ha='center', va='center',
            transform=ax.transAxes, fontsize=11, color='#555555')
    ax.set_xticks([])
    ax.set_yticks([])
    for spine in ax.spines.values():
        spine.set_visible(False)

def place_legend_below(ax, columns=2):
    ax.legend(
        frameon=True,
        facecolor='white',
        loc='upper center',
        bbox_to_anchor=(0.5, -0.14),
        ncol=columns,
        borderaxespad=0.0
    )

def plot_throughput(output_path, metrics):
    setup_style()
    fig, ax = plt.subplots(figsize=(8, 5))
    
    categories = []
    down_speeds = []
    up_speeds = []
    if metrics['direct_down'] > 0 or metrics['direct_up'] > 0:
        categories.append('Direct 5G')
        down_speeds.append(metrics['direct_down'])
        up_speeds.append(metrics['direct_up'])
    if metrics['wg_down'] > 0 or metrics['wg_up'] > 0:
        categories.append('WireGuard')
        down_speeds.append(metrics['wg_down'])
        up_speeds.append(metrics['wg_up'])

    if not categories:
        annotate_no_data(
            ax,
            'Băng thông truyền tải thực tế qua 5G',
            'Không có dữ liệu throughput đo được trong benchmark/reports'
        )
        plt.tight_layout()
        plt.savefig(output_path, dpi=300)
        plt.close()
        print(f"Throughput chart successfully saved to {output_path}")
        return
    
    x = np.arange(len(categories))
    width = 0.35
    
    # Modern harmonious color palette
    rects1 = ax.bar(x - width/2, down_speeds, width, label='Tải xuống (Download)', color='#2E75B6', edgecolor='none')
    rects2 = ax.bar(x + width/2, up_speeds, width, label='Tải lên (Upload)', color='#8FAADC', edgecolor='none')
    
    ax.set_ylabel('Băng thông (Mbps)', fontsize=12, fontweight='bold', labelpad=10)
    ax.set_title('So sánh Băng thông truyền tải thực tế qua 5G', fontsize=13, fontweight='bold', pad=15)
    ax.set_xticks(x)
    ax.set_xticklabels(categories, fontsize=11)
    place_legend_below(ax, columns=2)
    ax.grid(True, axis='y', linestyle='-', alpha=0.7)
    
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    
    def autolabel(rects):
        for rect in rects:
            height = rect.get_height()
            ax.annotate(f'{height:.1f} Mbps',
                        xy=(rect.get_x() + rect.get_width() / 2, height),
                        xytext=(0, 3),
                        textcoords="offset points",
                        ha='center', va='bottom', fontsize=9, color='#333333')
            
    autolabel(rects1)
    autolabel(rects2)
    
    plt.tight_layout(rect=[0, 0.08, 1, 1])
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"Throughput chart successfully saved to {output_path}")

def plot_latency(output_path, metrics):
    setup_style()
    fig, ax = plt.subplots(figsize=(8, 5))
    
    categories = []
    latency = []
    jitter = []
    if metrics['direct_lat'] > 0 or metrics['direct_jit'] > 0:
        categories.append('Direct 5G')
        latency.append(metrics['direct_lat'])
        jitter.append(metrics['direct_jit'])
    if metrics['wg_lat'] > 0 or metrics['wg_jit'] > 0:
        categories.append('WireGuard')
        latency.append(metrics['wg_lat'])
        jitter.append(metrics['wg_jit'])

    if not categories:
        annotate_no_data(
            ax,
            'Độ trễ RTT và biến thiên trễ',
            'Không có dữ liệu latency đo được trong benchmark/reports'
        )
        plt.tight_layout()
        plt.savefig(output_path, dpi=300)
        plt.close()
        print(f"Latency chart successfully saved to {output_path}")
        return
    
    x = np.arange(len(categories))
    width = 0.35
    
    rects1 = ax.bar(x - width/2, latency, width, label='Độ trễ trung bình (RTT)', color='#E24A35', edgecolor='none')
    rects2 = ax.bar(x + width/2, jitter, width, label='Độ biến thiên trễ (Jitter)', color='#FBC15E', edgecolor='none')
    
    ax.set_ylabel('Thời gian (ms)', fontsize=12, fontweight='bold', labelpad=10)
    ax.set_title('So sánh Độ trễ (Latency RTT) và Biến thiên trễ (Jitter)', fontsize=13, fontweight='bold', pad=15)
    ax.set_xticks(x)
    ax.set_xticklabels(categories, fontsize=11)
    place_legend_below(ax, columns=2)
    ax.grid(True, axis='y', linestyle='-', alpha=0.7)
    
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    
    def autolabel(rects):
        for rect in rects:
            height = rect.get_height()
            ax.annotate(f'{height:.1f} ms',
                        xy=(rect.get_x() + rect.get_width() / 2, height),
                        xytext=(0, 3),
                        textcoords="offset points",
                        ha='center', va='bottom', fontsize=9, color='#333333')
            
    autolabel(rects1)
    autolabel(rects2)
    
    plt.tight_layout(rect=[0, 0.08, 1, 1])
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"Latency chart successfully saved to {output_path}")

def plot_resources(output_path, metrics):
    setup_style()
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(9, 5))
    
    # 1. WireGuard CPU usage
    if metrics['wg_cpu'] > 0:
        rects1 = ax1.bar(['WireGuard'], [metrics['wg_cpu']], width=0.5, color=['#348ABD'], edgecolor='none')
        ax1.set_ylabel('Mức tải CPU trung bình (%)', fontsize=11, fontweight='bold')
        ax1.set_title('Tải CPU của WireGuard trên thiết bị biên', fontsize=11, fontweight='bold', pad=10)
        ax1.grid(True, axis='y', linestyle='-', alpha=0.5)
        ax1.spines['top'].set_visible(False)
        ax1.spines['right'].set_visible(False)

        for rect in rects1:
            height = rect.get_height()
            ax1.annotate(f'{height:.1f}%',
                        xy=(rect.get_x() + rect.get_width() / 2, height),
                        xytext=(0, 3),
                        textcoords="offset points",
                        ha='center', va='bottom', fontsize=10)
    else:
        annotate_no_data(ax1, 'Tải CPU của WireGuard', 'Chưa có dữ liệu CPU đo được')
                    
    # 2. WireGuard RAM usage
    if metrics['wg_ram'] > 0:
        rects2 = ax2.bar(['WireGuard'], [metrics['wg_ram']], width=0.5, color=['#467821'], edgecolor='none')
        ax2.set_ylabel('Dung lượng RAM tiêu thụ (MB)', fontsize=11, fontweight='bold')
        ax2.set_title('Dung lượng RAM tĩnh của WireGuard', fontsize=11, fontweight='bold', pad=10)
        ax2.grid(True, axis='y', linestyle='-', alpha=0.5)
        ax2.spines['top'].set_visible(False)
        ax2.spines['right'].set_visible(False)

        for rect in rects2:
            height = rect.get_height()
            ax2.annotate(f'{height:.2f} MB',
                        xy=(rect.get_x() + rect.get_width() / 2, height),
                        xytext=(0, 3),
                        textcoords="offset points",
                        ha='center', va='bottom', fontsize=10)
    else:
        annotate_no_data(ax2, 'RAM của WireGuard', 'Chưa có dữ liệu RAM đo được')
                    
    plt.suptitle('Mức tiêu hao tài nguyên phần cứng của WireGuard', fontsize=13, fontweight='bold', y=0.98)
    plt.tight_layout()
    plt.savefig(output_path, dpi=300)
    plt.close()
    print(f"Resource utilization chart successfully saved to {output_path}")

def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    reports_dir = os.path.join(base_dir, "reports")
    
    os.makedirs(reports_dir, exist_ok=True)
    
    # Check if --demo flag is passed
    use_demo = '--demo' in sys.argv
    
    if use_demo:
        print("Using demo/thesis-grade benchmark metrics for plotting...")
        metrics = {
            'direct_down': 187.4, 'direct_up': 73.6,
            'wg_down': 164.2, 'wg_up': 68.1,
            'direct_lat': 28.4, 'direct_jit': 8.2,
            'wg_lat': 34.7, 'wg_jit': 9.6,
            'wg_cpu': 14.3, 'wg_ram': 0.25
        }
    else:
        print("Scanning benchmark/reports/ directory for latest logs...")
        metrics = parse_latest_logs(reports_dir)
    
    # Output file paths
    throughput_png = os.path.join(reports_dir, "throughput_comparison.png")
    latency_png = os.path.join(reports_dir, "latency_comparison.png")
    resources_png = os.path.join(reports_dir, "resources_comparison.png")
    
    print("\nGenerating charts...")
    plot_throughput(throughput_png, metrics)
    plot_latency(latency_png, metrics)
    plot_resources(resources_png, metrics)
    
    print(f"\nAll visualizations successfully generated in: {reports_dir}/")
    print(f"1. Bandwidth:  {os.path.basename(throughput_png)}")
    print(f"2. Latency:    {os.path.basename(latency_png)}")
    print(f"3. Resources:  {os.path.basename(resources_png)}")

if __name__ == '__main__':
    main()
