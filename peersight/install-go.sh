#!/bin/bash
# ==============================================================
# Install Go from the official upstream tarball
# Supported targets: Linux x86_64 (amd64) and aarch64 (arm64)
# Run this on both Cloud Gateway and Edge Nodes
# Usage:
#   sudo ./install-go.sh
#   GO_VERSION=1.22.4 sudo ./install-go.sh
# ==============================================================

set -euo pipefail

GO_VERSION="${GO_VERSION:-1.23.0}"
INSTALL_DIR="/usr/local"
PROFILE_FILE="/etc/profile.d/go.sh"
BASE_URL="https://go.dev/dl"

# ── 1. Root check ──────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] This script must be run as root. Please use sudo."
    exit 1
fi

# ── 2. Skip if already installed and version matches ──────────
if command -v go &>/dev/null; then
    CURRENT="$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//')"
    if [[ "$CURRENT" == "$GO_VERSION" ]]; then
        echo "[INFO] Go ${GO_VERSION} is already installed at $(command -v go). Nothing to do."
        exit 0
    fi
    echo "[INFO] Found Go ${CURRENT}, will replace with Go ${GO_VERSION}."
fi

# ── 3. Detect architecture ────────────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  GO_ARCH="amd64" ;;
    aarch64) GO_ARCH="arm64" ;;
    armv7l)  GO_ARCH="armv6l" ;;
    *)
        echo "[ERROR] Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

TAR_FILE="go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
DOWNLOAD_URL="${BASE_URL}/${TAR_FILE}"

echo "=== Installing Go ${GO_VERSION} (${GO_ARCH}) ==="

# ── 4. Download ────────────────────────────────────────────────
TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

echo "[1/4] Downloading ${DOWNLOAD_URL} ..."
curl -fsSL --retry 3 --retry-delay 2 -o "${TMPDIR_WORK}/${TAR_FILE}" "${DOWNLOAD_URL}"

# ── 5. Verify checksum against go.dev public list ─────────────
echo "[2/4] Verifying checksum ..."
SHA_URL="${BASE_URL}/${TAR_FILE}.sha256"
EXPECTED_SHA=$(curl -fsSL --retry 3 "${SHA_URL}")
ACTUAL_SHA=$(sha256sum "${TMPDIR_WORK}/${TAR_FILE}" | awk '{print $1}')

if [[ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]]; then
    echo "[ERROR] SHA-256 mismatch!"
    echo "  Expected: ${EXPECTED_SHA}"
    echo "  Got     : ${ACTUAL_SHA}"
    exit 1
fi
echo "[OK] Checksum verified."

# ── 6. Extract & install ───────────────────────────────────────
echo "[3/4] Extracting to ${INSTALL_DIR} ..."
rm -rf "${INSTALL_DIR}/go"
tar -C "${INSTALL_DIR}" -xzf "${TMPDIR_WORK}/${TAR_FILE}"

# ── 7. Set up PATH for all login shells ───────────────────────
echo "[4/4] Configuring PATH via ${PROFILE_FILE} ..."
cat > "${PROFILE_FILE}" << 'EOF'
# Go language runtime — managed by peersight/install-go.sh
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
EOF
chmod 644 "${PROFILE_FILE}"

# Also apply to the current shell session for immediate use
export GOROOT="${INSTALL_DIR}/go"
export PATH="${GOROOT}/bin:${PATH}"

# ── 8. Sanity check ───────────────────────────────────────────
echo ""
go version
echo ""
echo "=== Go ${GO_VERSION} installed successfully ==="
echo "    Binary  : ${INSTALL_DIR}/go/bin/go"
echo "    Profile : ${PROFILE_FILE}"
echo ""
echo "NOTE: Open a new shell (or run 'source ${PROFILE_FILE}') to activate PATH for all users."
