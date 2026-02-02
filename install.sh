#!/bin/bash

# =========================================================
# Tun2Socks Gateway Manager Installer
# =========================================================

INSTALL_DIR="/opt/tun2socks-gateway-manager"
BIN_DIR="${INSTALL_DIR}/bin"
CONF_DIR="${INSTALL_DIR}/conf"
SCRIPT_DIR="${INSTALL_DIR}/scripts"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root.${NC}"
    exit 1
fi

echo -e "${GREEN}>>> Installing Tun2Socks Gateway Manager to ${INSTALL_DIR}...${NC}"

# 1. Create Directory Structure
# Creates 'run' and 'ids' inside the install directory, not the source folder.
mkdir -p "${INSTALL_DIR}"/{bin,conf,run,ids,scripts,systemd,completion}

# 2. Copy Scripts & Assets
echo ">>> Copying scripts and configuration..."
cp -r scripts/* "${INSTALL_DIR}/scripts/"
chmod +x "${INSTALL_DIR}/scripts/"*.sh

cp -r systemd/* "${INSTALL_DIR}/systemd/"
cp completion/* "${INSTALL_DIR}/completion/"

# Copy example config if no config exists
if [ ! -f "${CONF_DIR}/example.conf" ]; then
    cp conf/example.conf "${CONF_DIR}/" 2>/dev/null
fi

# 3. Setup ICMP Responder (Pre-compiled)
echo ">>> Setting up ICMP Responder..."
if [ -f "bin/icmp_responder" ]; then
    cp bin/icmp_responder "${BIN_DIR}/"
    chmod +x "${BIN_DIR}/icmp_responder"
else
    echo -e "${YELLOW}Warning: 'bin/icmp_responder' not found. Latency simulation will not work.${NC}"
fi

# 4. Setup Tun2Socks Binary
echo ">>> Checking Tun2Socks binary..."
if [ -f "bin/tun2socks-current" ]; then
    cp bin/tun2socks-current "${BIN_DIR}/"
    chmod +x "${BIN_DIR}/tun2socks-current"
    echo "    Installed local binary."
elif [ -f "bin/tun2socks" ]; then
    cp bin/tun2socks "${BIN_DIR}/tun2socks-current"
    chmod +x "${BIN_DIR}/tun2socks-current"
    echo "    Installed local binary (renamed to tun2socks-current)."
fi

# 5. Create Symlinks
echo ">>> Creating system links..."
ln -sf "${INSTALL_DIR}/scripts/cli.sh" /usr/local/bin/t2s
ln -sf "${INSTALL_DIR}/systemd/tun2socks@.service" /etc/systemd/system/

# Install Bash Completion
if [ -d "/usr/share/bash-completion/completions" ]; then
    ln -sf "${INSTALL_DIR}/completion/t2s_completion" /usr/share/bash-completion/completions/t2s
elif [ -d "/etc/bash_completion.d" ]; then
    ln -sf "${INSTALL_DIR}/completion/t2s_completion" /etc/bash_completion.d/t2s
fi

# 6. Finalize
systemctl daemon-reload

echo -e "${GREEN}>>> Installation complete.${NC}"

# Check if main binary is missing
if [ ! -f "${BIN_DIR}/tun2socks-current" ]; then
    echo ""
    echo -e "${YELLOW}ACTION REQUIRED:${NC}"
    echo "The 'tun2socks' binary is missing."
    echo "1. Download 'tun2socks-linux-amd64' from GitHub releases."
    echo "2. Rename it to 'tun2socks-current'"
    echo "3. Place it in: ${BIN_DIR}/"
fi

echo ""
echo "Usage:"
echo "  t2s start <name>"
echo "  t2s status"
