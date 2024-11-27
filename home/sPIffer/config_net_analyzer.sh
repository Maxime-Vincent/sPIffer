#!/bin/bash

# Check if a network interface exists
check_interface_exists() {
   if ! ip link show "$1" &> /dev/null; then
       echo "# Error: Interface $1 is not available."
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
# Disable Wi-Fi
echo "# Disabling Wi-Fi (wlan0)..."
sudo ip link set wlan0 down
echo "----------------------------------------------------"
# Check network interfaces
echo "# Checking network interfaces (eth1 and eth2)..."
check_interface_exists "eth0"
check_interface_exists "eth1"
check_interface_exists "eth2"
echo "# Interfaces eth0, eth1 and eth2 are available."
echo "----------------------------------------------------"
# Disable interfaces before configuration
echo "# Disabling interfaces eth1 and eth2..."
sudo ip link set eth1 down
sudo ip link set eth2 down
# Remove any existing bridge
if brctl show | grep -q "br0"; then
   echo "# Removing existing bridge br0."
   sudo ip link set br0 down
   sudo brctl delbr br0
else
   echo "# No existing bridge br0 to delete."
fi
echo "----------------------------------------------------"
# Enable IPv4 and IPv6 forwarding at kernel level
echo "# Enabling IPv4 and IPv6 forwarding..."
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
   echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
if ! grep -q "net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf; then
   echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
fi
echo "----------------------------------------------------"
# Apply advanced network optimizations for IPv4 and IPv6
echo "# Applying advanced network optimizations for IPv4 and IPv6..."
# IPv4 optimizations
sysctl -w net.core.rmem_default=26214400 > /dev/null
sysctl -w net.core.wmem_default=26214400 > /dev/null
sysctl -w net.core.rmem_max=67108864 > /dev/null
sysctl -w net.core.wmem_max=67108864 > /dev/null
sysctl -w net.core.optmem_max=67108864 > /dev/null
sysctl -w net.core.netdev_max_backlog=10000 > /dev/null
sysctl -w net.ipv4.tcp_rmem="4096 87380 67108864" > /dev/null
sysctl -w net.ipv4.tcp_wmem="4096 65536 67108864" > /dev/null
sysctl -w net.ipv4.tcp_mem="67108864 67108864 67108864" > /dev/null
sysctl -w net.ipv4.tcp_congestion_control=cubic > /dev/null
sysctl -w net.ipv4.tcp_mtu_probing=1 > /dev/null
sysctl -w net.ipv4.tcp_no_metrics_save=1 > /dev/null
sysctl -w net.ipv4.tcp_low_latency=1 > /dev/null
sysctl -w net.ipv4.ipfrag_high_thresh=16777216 > /dev/null
sysctl -w net.ipv4.ipfrag_low_thresh=15728640 > /dev/null
sysctl -w net.ipv4.ipfrag_time=30 > /dev/null
# IPv6 optimizations
sysctl -w net.ipv6.conf.all.accept_ra=0 > /dev/null  # Disable RA auto-configuration
sysctl -w net.ipv6.conf.default.accept_ra=0 > /dev/null
sysctl -w net.ipv6.conf.all.autoconf=0 > /dev/null
sysctl -w net.ipv6.conf.default.autoconf=0 > /dev/null
sysctl -w net.ipv6.conf.all.max_addresses=1 > /dev/null  # Limit the number of assigned addresses
sysctl -w net.ipv6.conf.default.max_addresses=1 > /dev/null
sysctl -w net.ipv6.ip6frag_high_thresh=16777216 > /dev/null
sysctl -w net.ipv6.ip6frag_low_thresh=15728640 > /dev/null
sysctl -w net.ipv6.ip6frag_time=30 > /dev/null
sysctl -w net.ipv6.conf.all.forwarding=1 > /dev/null  # Enable IPv6 forwarding
sysctl -w net.ipv6.conf.default.forwarding=1 > /dev/null
echo "# Advanced network optimizations applied for IPv4 and IPv6."
echo "----------------------------------------------------"
# Disable offloading features
echo "# Disabling offloading features on eth1 and eth2..."
sudo ethtool -K eth1 tso off gso off gro off lro off rx off tx off sg off ufo off
sudo ethtool -K eth2 tso off gso off gro off lro off rx off tx off sg off ufo off
# Set MTU
echo "# Setting MTU to 9000 on eth1 and eth2..."
sudo ip link set eth1 mtu 9000
sudo ip link set eth2 mtu 9000
echo "----------------------------------------------------"
# Create the bridge
echo "# Creating the bridge br0 and adding interfaces eth1 and eth2..."
sudo brctl addbr br0
sudo brctl addif br0 eth1
sudo brctl addif br0 eth2
# Set priority and delay
sudo brctl setbridgeprio br0 0
sudo brctl setfd br0 0
# Enable promiscuous mode
echo "# Enabling promiscuous mode on eth1, eth2, and br0..."
sudo ip link set eth1 promisc on
sudo ip link set eth2 promisc on
sudo ip link set br0 promisc on
# Deactivate the promiscuity mode only for eth0 to capture all the network traffic
echo "# Deactivation of promiscuity mode on eth0 for network traffic..."
sudo ip link set eth0 promisc off
# Configure iptables rules for forwarding
echo "# Configuring iptables rules for forwarding between eth1 and eth2."
add_iptables_rule "-A FORWARD -i eth1 -o eth2 -j ACCEPT"
add_iptables_rule "-A FORWARD -i eth2 -o eth1 -j ACCEPT"
add_iptables_rule "-A FORWARD -p icmp -j ACCEPT"
add_iptables_rule "-A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT"
# Remove IP addresses from the interfaces
ip addr flush dev eth1
ip addr flush dev eth2
# Activate interfaces
echo "# Activating interfaces eth1, eth2, and br0..."
ip link set eth1 up
ip link set eth2 up
ip link set br0 up
echo "----------------------------------------------------"
# Verify the bridge configuration
echo "# Verifying bridge br0 configuration..."
brctl showstp br0
echo "----------------------------------------------------"
echo "# Network configuration and IPv4/IPv6 optimization completed."
echo "----------------------------------------------------"
# Verify the status of the bridge and the forwarding
echo "# Verify the forwarding btw eth1 and eth2"
sudo brctl showstp br0
echo "----------------------------------------------------"
# Start the web server
echo "# Starting the web server..."
cd /home/sPIffer
sudo nohup npm start > /var/log/npm_server.log 2>&1 &
echo "# Web server started successfully."
echo "----------------------------------------------------"
echo "# Network configuration and optimizations completed."