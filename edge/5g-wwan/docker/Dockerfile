FROM alpine:latest

# Install core networking dependencies for QMI, DHCP, and Ping
# udhcpc is provided by busybox natively in Alpine
RUN apk add --no-cache \
    bash \
    libqmi-utils \
    iproute2 \
    iputils \
    eudev \
    kmod

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
