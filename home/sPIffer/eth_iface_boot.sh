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
sudo tee "$SERVICE_FILE" > /dev/null <<'EOF'
[Unit]
Description=sPIffer iface setup (eth1 <-> eth2) via config_net_analyzer
Wants=network-pre.target
After=network-pre.target
# Attendre que les interfaces existent vraiment (device units)
BindsTo=sys-subsystem-net-devices-eth1.device sys-subsystem-net-devices-eth2.device
After=sys-subsystem-net-devices-eth1.device sys-subsystem-net-devices-eth2.device

[Service]
Type=oneshot

# Sécurité: si une des interfaces n'existe pas encore -> échec
ExecStartPre=/bin/sh -c 'test -e /sys/class/net/eth1 && test -e /sys/class/net/eth2'

# Optionnel mais très utile: attendre que le kernel annonce une "operstate" (évite certains boot USB)
ExecStartPre=/bin/sh -c 'for i in $(seq 1 20); do s1=$(cat /sys/class/net/eth1/operstate 2>/dev/null || true); s2=$(cat /sys/class/net/eth2/operstate 2>/dev/null || true); if [ -n "$s1" ] && [ -n "$s2" ]; then exit 0; fi; sleep 1; done; exit 1'

ExecStart=/home/sPIffer/config_net_analyzer.sh apply
ExecStop=/home/sPIffer/config_net_analyzer.sh stop

RemainAfterExit=yes
TimeoutStartSec=45
TimeoutStopSec=10

# En cas d'échec boot (USB NIC lente, etc.), retenter
Restart=on-failure
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
