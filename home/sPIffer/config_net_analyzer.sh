#!/bin/bash

# Check if the interface already exists
check_interface_exists() {
   if ! ip link show "$1" &> /dev/null; then
       echo "# Error : The interface $1 is not available."
       exit 1
   fi
}
# Function to add iptables rules if they do not already exist
add_iptables_rule() {
   local rule="$1"
   # Check if the rule already exists
   if ! iptables $rule 2>/dev/null; then
       # Add the rule if it doesn't exist
       iptables $rule
       echo "# Added iptables rule: $rule"
   else
       echo "# Iptables rule already exists: $rule"
   fi
}

echo "----------------------------------------------------"
# Stop and disable Wifi to avoid some external process
echo "# Set wlan0 to DOWN mode"
sudo ip link set wlan0 down
echo "----------------------------------------------------"
# Verify the availability of the interfaces eth0, eth1 et eth2
echo "# Verification of network interfaces..."
check_interface_exists "eth0"
check_interface_exists "eth1"
check_interface_exists "eth2"
echo "# Interfaces eth0, eth1 et eth2 are available."
# Bring down interfaces before configuration
echo "# Bringing down interfaces eth1 and eth2 for safe configuration..."
sudo ip link set eth1 down
sudo ip link set eth2 down
echo "----------------------------------------------------"
# Delete any existing bridge br0 safely
if brctl show | grep -q "br0"; then
   echo "# Deleting existing bridge br0."
   sudo ip link set br0 down
   brctl delbr br0
else
   echo "# No existing bridge br0 to delete."
fi
echo "----------------------------------------------------"
# Enable IP forwarding at kernel level
echo "# Enabling IP forwarding..."
echo 1 > /proc/sys/net/ipv4/ip_forward
# Keep the forwarding persistant inside system file /etc/sysctl.conf
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
   echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
   echo "# IP forwarding configuration added to /etc/sysctl.conf"
fi
echo "----------------------------------------------------"
# Network optimizations before bringing up interfaces
echo "# Applying network optimizations..."
sysctl -w net.core.rmem_max=26214400 > /dev/null
sysctl -w net.core.wmem_max=26214400 > /dev/null
sysctl -w net.core.netdev_max_backlog=5000 > /dev/null
sysctl -w net.ipv4.tcp_rmem="4096 87380 26214400" > /dev/null
sysctl -w net.ipv4.tcp_wmem="4096 65536 26214400" > /dev/null
sysctl -w net.ipv4.tcp_mem="50576 64768 98152" > /dev/null
# Disable TCP offloading features safely
echo "# Disabling offload features on eth1 and eth2."
ethtool -K eth1 tso off gso off gro off lro off
ethtool -K eth2 tso off gso off gro off lro off
# Set MTU to 9000
echo "# Setting MTU to 9000 on eth1 and eth2."
sudo ip link set eth1 mtu 9000
sudo ip link set eth2 mtu 9000
# Configure iptables rules for forwarding
echo "# Configuring iptables rules for forwarding between eth1 and eth2."
add_iptables_rule "-A FORWARD -i eth1 -o eth2 -j ACCEPT"
add_iptables_rule "-A FORWARD -i eth2 -o eth1 -j ACCEPT"
add_iptables_rule "-A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT"
echo "----------------------------------------------------"
# Create a new bridge br0
echo "# Create a new bridge br0..."
sudo brctl addbr br0
# Add top priority to the bridge br0
echo "# Configuring bridge br0 with priority and delay settings..."
sudo brctl setbridgeprio br0 0
# Set lowest bridge forwarding time delay
echo "# Set lowest bridge forwarding time delay..."
sudo brctl setfd br0 0
# Add eth1 and eth2 on bridge (the eth0 interface will be used for remote capture)
echo "# Add the interfaces eth1 and eth2 on bridge br0..."
sudo brctl addif br0 eth1
sudo brctl addif br0 eth2
# Activate the promiscuity mode for eth1, eth2
sudo ip link set eth1 promisc on
sudo ip link set eth2 promisc on
sudo ip link set br0 promisc on
# Remove the use of IP address on ETH sniffed
sudo ip addr flush dev eth1
sudo ip addr flush dev eth2
# Deactivate the promiscuity mode only for eth0 to capture all the network traffic
echo "# Deactivation of promiscuity mode on eth0 for network traffic..."
sudo ip link set eth0 promisc off
# Set the interfaces eth1 and eth2 in UP mode
echo "# Set br0, eth0, eth1 and eth2 in UP mode..."
sudo ip link set eth1 up
sudo ip link set eth2 up
sudo ip link set br0 up
# Set also eth0 in UP mode
sudo ip link set eth0 up
echo "----------------------------------------------------"
# Verify the status of the bridge and the forwarding
echo "# Verify the forwarding btw eth1 and eth2"
sudo brctl showstp br0
echo "----------------------------------------------------"
# Start the web server
echo "# Starting the web server..."
cd /home/sPIffer
sudo nohup npm start > /dev/null 2>&1 &
echo "# Web server started successfully."
echo "----------------------------------------------------"
echo "# Network configuration and optimizations completed."