#!/bin/bash
# ==============================================================
# WWAN 5G Service Installer
# Installs scripts to /usr/local/bin and sets up systemd services
# ==============================================================

set -euo pipefail

apt_package_exists() {
    apt-cache show "$1" >/dev/null 2>&1
}

dnf_package_exists() {
    dnf -q list available "$1" >/dev/null 2>&1
}

install_docker_compose_plugin_manual() {
    local plugin_dir="/usr/local/lib/docker/cli-plugins"
    echo "[INFO] Installing Docker Compose plugin manually..."
    mkdir -p "$plugin_dir"
    curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)" \
        -o "${plugin_dir}/docker-compose"
    chmod +x "${plugin_dir}/docker-compose"
}

enable_docker_if_installed() {
    if systemctl list-unit-files | grep -q '^docker\.service'; then
        echo "[INFO] Enabling Docker service..."
        systemctl enable --now docker
    fi
}

ensure_docker_compose_v2() {
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        return 0
    fi

    install_docker_compose_plugin_manual
}

# 1. Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] This script must be run as root. Please use sudo."
    exit 1
fi

echo "=== Installing 5G WWAN Services ==="

# 2. Install required dependencies
echo "[INFO] Installing required dependencies and operator tooling..."
if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -yqq
    APT_PACKAGES=(
        build-essential
        curl
        docker.io
        git
        iperf3
        iproute2
        iputils-ping
        libqmi-utils
        rsync
        stow
        tmux
        udhcpc
        ufw
        vim
    )

    if apt_package_exists docker-compose-plugin; then
        APT_PACKAGES+=(docker-compose-plugin)
    elif apt_package_exists docker-compose-v2; then
        APT_PACKAGES+=(docker-compose-v2)
    else
        echo "[WARN] Docker Compose v2 package not found in apt repositories. Will install plugin manually."
    fi

    apt-get install -yq "${APT_PACKAGES[@]}"
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y \
        busybox \
        curl \
        docker \
        gcc \
        git \
        iperf3 \
        iproute \
        iputils \
        libqmi-utils \
        make \
        rsync \
        stow \
        tmux \
        vim

    if dnf_package_exists docker-compose-plugin; then
        dnf install -y docker-compose-plugin
    else
        echo "[WARN] docker-compose-plugin package not found in dnf repositories. Will install plugin manually."
    fi

    if dnf_package_exists ufw; then
        dnf install -y ufw
    else
        echo "[WARN] ufw package not found in dnf repositories. Skipping ufw installation on this edge host."
    fi
else
    echo "[ERROR] Unsupported package manager. Expected apt-get or dnf."
    exit 1
fi

enable_docker_if_installed
ensure_docker_compose_v2

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# 3. Check if required files exist
REQUIRED_FILES=("wwan-stop.sh" "wwan-monitor.sh" "wwan.service" "wwan-monitor.service")
for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$SCRIPT_DIR/$file" ]]; then
        echo "[ERROR] Critical file missing: $file"
        exit 1
    fi
done

# 3.5. Compile quectel-CM
PROJECT_ROOT=$(readlink -f "$SCRIPT_DIR/../../")
echo "[INFO] Compiling quectel-CM..."
cd "$PROJECT_ROOT/quectel-CM"
make clean && make
cp quectel-CM /usr/local/bin/
chmod +x /usr/local/bin/quectel-CM
cd "$SCRIPT_DIR"

# 4. Copy scripts to /usr/local/bin
echo "[INFO] Copying executable scripts to /usr/local/bin..."
cp "$SCRIPT_DIR"/wwan-stop.sh /usr/local/bin/
cp "$SCRIPT_DIR"/wwan-monitor.sh /usr/local/bin/

# Make them executable
chmod +x /usr/local/bin/wwan-stop.sh
chmod +x /usr/local/bin/wwan-monitor.sh

# 5. Install systemd services
echo "[INFO] Installing systemd services..."
cp "$SCRIPT_DIR"/wwan.service /etc/systemd/system/
cp "$SCRIPT_DIR"/wwan-monitor.service /etc/systemd/system/

# Fix permissions on unit files
chmod 644 /etc/systemd/system/wwan.service
chmod 644 /etc/systemd/system/wwan-monitor.service

# 6. Setup default environment file
if [[ ! -f /etc/default/wwan ]]; then
    echo "[INFO] Creating default configuration at /etc/default/wwan..."
    cat <<EOF > /etc/default/wwan
# WWAN Configuration
WWAN_APN=internet
WWAN_DEVICE_WAIT_TIMEOUT=45
EOF
fi

# 7. Reload daemon and enable services
echo "[INFO] Reloading systemd daemon..."
systemctl daemon-reload

echo "[INFO] Enabling services to start on boot..."
systemctl enable wwan.service
systemctl enable wwan-monitor.service

# 8. Ask user if they want to start the services immediately
echo ""
read -r -p "Do you want to start the 5G connection now? [y/N]: " START_NOW
if [[ "$START_NOW" =~ ^[Yy]$ ]]; then
    echo "[INFO] Starting wwan.service..."
    if ! systemctl start wwan.service; then
        echo "[ERROR] wwan.service failed to start."
        echo "       Inspect the service with:"
        echo "       systemctl status wwan.service"
        echo "       journalctl -xeu wwan.service"
        exit 1
    fi
    echo "[INFO] Starting wwan-monitor.service..."
    systemctl start wwan-monitor.service
    echo "[SUCCESS] Services started. Use 'systemctl status wwan' to check."
else
    echo "[INFO] Installation complete. Services will start automatically "
    echo "       on the next system boot, or you can start them manually with:"
    echo "       sudo systemctl start wwan.service"
fi

echo "======================================"
echo "   Installation Completed Successfully"
echo "======================================"
