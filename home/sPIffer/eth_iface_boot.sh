#!/bin/bash
set -euo pipefail

# Variables
SCRIPT_PATH="/home/sPIffer/config_net_analyzer.sh"
SERVICE_NAME="sPIffer_iface_config"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# Check if the target script exists
if [[ ! -f "$SCRIPT_PATH" ]]; then
  echo "Error: Script $SCRIPT_PATH does not exist."
  exit 1
fi

# Create (or overwrite) the systemd service file
# - network-online.target is the proper target for "network is up"
# - RemainAfterExit=yes keeps service "active" after oneshot
# - ExecStop allows a clean teardown if your script supports it
# - Optional ExecStartPre waits for eth1/eth2 to exist (very helpful with USB NICs)
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=sPIffer bridge setup at boot (br0: eth1 <-> eth2)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
# Wait (up to ~30s) for eth1 and eth2 to exist before running the bridge script
ExecStartPre=/bin/sh -c 'for i in \$(seq 1 30); do ip link show eth1 >/dev/null 2>&1 && ip link show eth2 >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1'
ExecStart=${SCRIPT_PATH} start
ExecStop=${SCRIPT_PATH} stop
RemainAfterExit=yes
TimeoutStartSec=30
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF

# Set correct and safe permissions
# 644 means: root can write; everyone can read. This is standard for systemd units.
sudo chown root:root "$SERVICE_FILE"
sudo chmod 644 "$SERVICE_FILE"

# Reload systemd to apply changes
sudo systemctl daemon-reload

# Enable the service to start on boot
sudo systemctl enable "${SERVICE_NAME}.service"

echo "Service ${SERVICE_NAME} has been created/updated and enabled at boot."
echo "You can start it now with: sudo systemctl restart ${SERVICE_NAME}.service"
echo "Check logs with: sudo journalctl -u ${SERVICE_NAME} -b --no-pager"
