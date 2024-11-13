#!/bin/bash

# Get the actual path of this script bash
SCRIPT_PATH="$(realpath "$BASH_SOURCE")"

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
# Delete every existing bridge and dissociate the interfaces
echo "# Deletion of every existing bridges..."
for bridge in $(brctl show | awk 'NR>1 {print $1}' | sort -u); do
   echo "# Deletion of $bridge and dissociation of the interfaces..."
   # Dissociate the interfaces with the bridge
   for iface in $(brctl show $bridge | awk 'NR>1 {print $4}'); do
       echo "# Deletion of the interface $iface of bridge $bridge..."
       ip link set "$iface" down
       brctl delif "$bridge" "$iface"
   done
   # Supprimer le bridge lui-même
   ip link set "$bridge" down
   brctl delbr "$bridge"
done
echo "# Every bridge have been well deleted."
echo "----------------------------------------------------"
# Verify the availability of the interfaces eth0, eth1 et eth2
echo "# Verification of network interfaces..."
check_interface_exists "eth0"
check_interface_exists "eth1"
check_interface_exists "eth2"
echo "# Interfaces eth0, eth1 et eth2 are available."
# Activate the forwarding IP at kernel level
echo "# Activation of forwarding IP..."
echo 1 > /proc/sys/net/ipv4/ip_forward
# Keep the forwarding persistant inside system file /etc/sysctl.conf
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
   echo "# Add the configuration of the forwarding IP in /etc/sysctl.conf..."
   echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
else
   echo "# Forwarding IP is already configured in /etc/sysctl.conf."
fi
echo "----------------------------------------------------"
# Add the rules for forwarding between eth1 and eth2
echo "# Configuration of forwarding between eth1 and eth2..."
add_iptables_rule "-A FORWARD -i eth1 -o eth2 -j ACCEPT"
add_iptables_rule "-A FORWARD -i eth2 -o eth1 -j ACCEPT"
echo "----------------------------------------------------"
# Create a new bridge br0
echo "# Create a new bridge br0..."
sudo brctl addbr br0
# Add top priority to the bridge br0
echo "# Update priority for bridge br0"
sudo brctl setbridgeprio br0 0
# Set lowest bridge forwarding time delay
sudo brctl setfd br0 0
# Add eth1 and eth2 on bridge (the eth0 interface will be used for remote capture)
echo "# Add the interfaces eth1 and eth2 on bridge br0..."
sudo brctl addif br0 eth1
sudo brctl addif br0 eth2
# Set the interfaces eth1 and eth2 in UP mode
echo "# Set br0, eth0, eth1 and eth2 in UP mode..."
sudo ip link set eth1 up
sudo ip link set eth2 up
sudo ip link set br0 up
# Set also eth0 in UP mode
sudo ip link set eth0 up
# Activate the promiscuity mode for eth1, eth2
sudo ip link set eth1 promisc on
sudo ip link set eth2 promisc on
sudo ip link set br0 promisc on
# Remove the use of IP address on ETH sniffed
sudo ip addr flush dev eth1
sudo ip addr flush dev eth2
# Activate the promiscuity mode only for eth0 to capture all the network traffic
echo "# Deactivation of promiscuity mode on eth0 for network traffic..."
sudo ip link set eth0 promisc off
echo "----------------------------------------------------"
# Verify the status of the bridge and the forwarding
echo "# Verify the forwarding btw eth1 and eth2"
sudo brctl showstp br0
echo "----------------------------------------------------"
# Finale confirmation and summary of the configurations
echo "# Configuration finished successfully !"
echo "# Summary of perform actions :"
echo "#  - Deletion of the older existing bridge."
echo "#  - Forwarding activation on eth1 and eth2."
echo "#  - The interface eth0 is configured without promiscuity mode to capture the network traffic."
echo "#  - You can now use Wireshark on br0 to sniff all the network traffic between eth1 and eth2."
echo "----------------------------------------------------"