#!/bin/bash

# Variables
SCRIPT_PATH="/home/sPIffer/config_net_analyzer.sh"
SERVICE_NAME="sPIffer_iface_config"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"

# Check if the target script exists
if [[ ! -f "$SCRIPT_PATH" ]]; then
  echo "Error: Script $SCRIPT_PATH does not exist."
  exit 1
fi

# Create the systemd service file
echo "[Unit]
Description=My Startup Script
After=network.target

[Service]
Type=simple
ExecStart=$SCRIPT_PATH
Restart=on-failure

[Install]
WantedBy=multi-user.target" | sudo tee "$SERVICE_FILE" > /dev/null

# Set the correct permissions for the service file
sudo chmod 644 "$SERVICE_FILE"

# Reload systemd to apply changes
sudo systemctl daemon-reload

# Enable the service to start on boot
sudo systemctl enable "$SERVICE_NAME.service"

echo "Service $SERVICE_NAME has been created and enabled to start at boot."

# Optional: Start the service immediately
read -p "Do you want to start the service now? (y/n): " start_now
if [[ "$start_now" =~ ^[Yy]$ ]]; then
  sudo systemctl start "$SERVICE_NAME.service"
  echo "Service $SERVICE_NAME started."
else
  echo "Service $SERVICE_NAME will start at the next boot."
fi
