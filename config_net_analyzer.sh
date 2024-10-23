#!/bin/bash

# Check if the interface already exists
check_interface_exists() {
   if ! ip link show "$1" &> /dev/null; then
       echo "# Error : The interface $1 is not available."
       exit 1
   fi
}

# Check if a required library is available, and install if missing
check_lib_available(){
    if dpkg -l | grep -qw "$1"; then
        echo "# $1 is already installed."
    else
        echo "# $1 not installed. Exit the configuration..."
        exit 1
    fi
}

# Set up Wifi for possible library to install
sudo ip link set wlan0 up

# Delete every existing bridge and dissociate the interfaces
echo "# Deletion of every existing bridges..."
for bridge in $(brctl show | awk 'NR>1 {print $1}' | sort -u); do
   echo "# Deletion of $bridge and dissociation of the interfaces..."
   for iface in $(brctl show "$bridge" | awk 'NR>1 {print $4}'); do
       echo "# Deletion of the interface $iface of bridge $bridge..."
       ip link set "$iface" down
       brctl delif "$bridge" "$iface"
   done
   ip link set "$bridge" down
   brctl delbr "$bridge"
done
echo "# Every bridge has been well deleted."

# Verify the availability of the interfaces eth0, eth1 and eth2
echo "# Verification of network interfaces..."
check_interface_exists "eth0"
check_interface_exists "eth1"
check_interface_exists "eth2"
echo "# Interfaces eth0, eth1 and eth2 are available."

# Activate the forwarding IP at kernel level
echo "# Activation of forwarding IP..."
echo 1 > /proc/sys/net/ipv4/ip_forward

# Keep the forwarding persistent inside system file /etc/sysctl.conf
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
   echo "# Add the configuration of the forwarding IP in /etc/sysctl.conf..."
   echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
else
   echo "# Forwarding IP is already configured in /etc/sysctl.conf."
fi

# Install iptables if needed
echo "# Verification and installation of iptables if needed..."
check_lib_available iptables

# Empty the iptables existing rules to start from scratch
echo "# Reinitialisation of iptables rules..."
iptables -F
iptables -t nat -F

# Add the rules for forwarding between eth1 and eth2
echo "# Configuration of forwarding between eth1 and eth2..."
iptables -A FORWARD -i eth1 -o eth2 -j ACCEPT
iptables -A FORWARD -i eth2 -o eth1 -j ACCEPT

# Install bridge-utils if needed (useful for the bridge management)
echo "# Verification and installation of bridge-utils if needed..."
check_lib_available bridge-utils

# Create a new bridge br0
echo "# Create a new bridge br0..."
brctl addbr br0

# Add top priority to the bridge br0
brctl setbridgeprio br0 0

# Set lowest bridge forwarding time delay
brctl setfd br0 0

# Add eth1 and eth2 on bridge (the eth0 interface will be used for remote capture)
echo "# Add the interfaces eth1 and eth2 on bridge br0..."
brctl addif br0 eth1
brctl addif br0 eth2

# Set the interfaces eth1 and eth2 in UP mode
echo "# Set br0, eth1 and eth2 in UP mode..."
ip link set eth1 up
ip link set eth2 up
ip link set br0 up

# Set eth0 in UP mode
ip link set eth0 up

# Activate the promiscuity mode for eth1, eth2
ip link set eth1 promisc on
ip link set eth2 promisc on

# Remove the use of IP address on eth1 and eth2 (for sniffing purposes)
sudo ip addr flush dev eth1
sudo ip addr flush dev eth2

# Activate the promiscuity mode only for eth0 to capture all the network traffic
echo "# Activation of promiscuity mode on eth0 for network traffic..."
ip link set eth0 promisc on
ip link set br0 promisc on

# Install tc (iproute2) if not already installed
echo "# Verification and installation of tc (iproute2) if needed..."
check_lib_available iproute2

# Configure port mirroring from br0 to eth0 using tc
echo "# Configuring port mirroring from br0 to eth0 using tc..."
sudo tc qdisc add dev br0 ingress
sudo tc filter add dev br0 parent ffff: protocol all u32 match u8 0 0 action mirred egress mirror dev eth0
sudo tc qdisc add dev br0 handle 1: root prio
sudo tc filter add dev br0 parent 1: protocol all u32 match u8 0 0 action mirred egress mirror dev eth0

# Final confirmation and summary of the configurations
echo "# Configuration finished successfully!"
echo "# Summary of performed actions:"
echo "#  - Deletion of the older existing bridges."
echo "#  - Forwarding activation on eth1 and eth2."
echo "#  - Port mirroring from br0 to eth0 configured."
echo "#  - The interface eth0 is configured in promiscuity mode to capture the network traffic."
echo "#  - IP address on eth0 has been flushed for stealth capture."
echo "#  - You can now connect to eth0 with your PC and use Wireshark to sniff all the network traffic between eth1 and eth2."

# Stop and disable Wifi to avoid some external process
sudo ip link set wlan0 down

# Disable IP address on eth0 to make it invisible on the network
sudo ip addr flush dev eth0
