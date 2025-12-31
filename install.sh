#!/bin/bash

INSTALL_DIR="/opt/tun2socks-gateway-manager"
BIN_DIR="${INSTALL_DIR}/bin"

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi

echo "Installing Tun2Socks Gateway Manager to ${INSTALL_DIR}..."

# Create directory structure
mkdir -p "${INSTALL_DIR}"/{bin,conf,run,scripts,systemd,completion}

# Copy assets
cp -r scripts/* "${INSTALL_DIR}/scripts/"
cp -r systemd/* "${INSTALL_DIR}/systemd/"
cp completion/* "${INSTALL_DIR}/completion/"

# Copy example config if no config exists
if [ ! -f "${INSTALL_DIR}/conf/example.conf" ]; then
    cp conf/example.conf "${INSTALL_DIR}/conf/" 2>/dev/null
fi

# Set permissions
chmod +x "${INSTALL_DIR}/scripts/"*.sh

# Create symlinks
ln -sf "${INSTALL_DIR}/scripts/cli.sh" /usr/local/bin/t2s
ln -sf "${INSTALL_DIR}/systemd/tun2socks@.service" /etc/systemd/system/
ln -sf "${INSTALL_DIR}/completion/t2s_completion" /etc/bash_completion.d/t2s

# Reload systemd to recognize new service file
systemctl daemon-reload

echo "Installation complete."
echo "Action Required: Download the 'tun2socks-linux-amd64' binary and place it at:"
echo " -> ${BIN_DIR}/tun2socks-current"
