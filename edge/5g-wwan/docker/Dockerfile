FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install core networking dependencies for QMI, DHCP, and Ping
RUN apt-get update -yqq && \
    apt-get install -yq --no-install-recommends \
    libqmi-utils \
    udhcpc \
    iproute2 \
    iputils-ping \
    udev \
    kmod \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/wwan

COPY wwan-start.sh .
RUN chmod +x /opt/wwan/wwan-start.sh

# Start the network natively within the container.
# Then enter a heartbeat loop. If internet ping fails, 
# exit the container. Docker Compose will restart it automatically!
CMD ./wwan-start.sh && \
    echo "[INFO] Entering Network Watchdog..." && \
    while ping -c 2 -W 3 8.8.8.8 >/dev/null; do sleep 15; done && \
    echo "[ERROR] Network Lost! Container will crash and restart." && \
    exit 1
