#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------
# This script creates/updates two systemd services:
# 1) sPIffer_iface_config.service  -> configures the transparent bridge (br0 eth1<->eth2)
# 2) spiffer_web.service           -> runs the Node web server under systemd supervision
#
# Why split?
# - A oneshot network setup service should NOT spawn long-running daemons (npm/node).
# - systemd can restart/stop the web server cleanly if it crashes.
# - logs are visible via journalctl per-service.
# ------------------------------------------------------------

# -------- Bridge service (network) --------
SCRIPT_PATH="/home/sPIffer/config_net_analyzer.sh"
SERVICE_NAME="sPIffer_iface_config"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# -------- Web service (node) --------
WEB_SERVICE_NAME="spiffer_web"
WEB_SERVICE_FILE="/etc/systemd/system/${WEB_SERVICE_NAME}.service"
WEB_WORKDIR="/home/sPIffer"

# If your project needs a different start command, change this:
# - If you use package.json "start": keep /usr/bin/npm start
# - If you run directly: set WEB_EXEC_START="/usr/bin/node src/server.js"
WEB_EXEC_START="/usr/bin/npm start"

# Check if the target bridge script exists
if [[ ! -f "$SCRIPT_PATH" ]]; then
  echo "Error: Script $SCRIPT_PATH does not exist."
  exit 1
fi

# Ensure the bridge script is executable
sudo chmod +x "$SCRIPT_PATH"

# ------------------------------------------------------------
# Create/overwrite the bridge setup systemd service
# ------------------------------------------------------------
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=sPIffer bridge setup (br0: eth1 <-> eth2)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot

# Wait (up to ~30s) for eth1 and eth2 to exist (useful for USB NICs)
ExecStartPre=/bin/sh -c 'for i in \$(seq 1 30); do ip link show eth1 >/dev/null 2>&1 && ip link show eth2 >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1'

ExecStart=${SCRIPT_PATH} start
ExecStop=${SCRIPT_PATH} stop

RemainAfterExit=yes
TimeoutStartSec=30
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF

# Safe permissions (never 777)
sudo chown root:root "$SERVICE_FILE"
sudo chmod 644 "$SERVICE_FILE"

# ------------------------------------------------------------
# Create/overwrite the dedicated web server systemd service
# ------------------------------------------------------------
sudo tee "$WEB_SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=sPIffer Web Server (Node)
After=network-online.target ${SERVICE_NAME}.service
Wants=network-online.target

[Service]
Type=simple
User=sPIffer
WorkingDirectory=${WEB_WORKDIR}
Environment=NODE_ENV=production
ExecStart=${WEB_EXEC_START}
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

# Safe permissions (never 777)
sudo chown root:root "$WEB_SERVICE_FILE"
sudo chmod 644 "$WEB_SERVICE_FILE"

# ------------------------------------------------------------
# Reload systemd and enable services
# ------------------------------------------------------------
sudo systemctl daemon-reload

sudo systemctl enable "${SERVICE_NAME}.service"
sudo systemctl enable "${WEB_SERVICE_NAME}.service"

# Optional: restart both now (recommended so changes apply immediately)
sudo systemctl restart "${SERVICE_NAME}.service"
sudo systemctl restart "${WEB_SERVICE_NAME}.service"

echo "OK: Services created/updated and enabled:"
echo " - ${SERVICE_NAME}.service"
echo " - ${WEB_SERVICE_NAME}.service"
echo
echo "Check status:"
echo "  sudo systemctl status ${SERVICE_NAME}.service --no-pager"
echo "  sudo systemctl status ${WEB_SERVICE_NAME}.service --no-pager"
echo
echo "Check logs (current boot):"
echo "  sudo journalctl -u ${SERVICE_NAME} -b --no-pager"
echo "  sudo journalctl -u ${WEB_SERVICE_NAME} -b --no-pager"
