#!/bin/bash
# Check if the interface already exists
check_interface_exists() {
   if ! ip link show "$1" &> /dev/null; then
       echo "# Error : The interface $1 is not available."
       exit 1
   fi
}
disable_promiscuous_mode() {
   for interface in "$@"; do
       # Check if the interface exists
       if ip link show "$interface" > /dev/null 2>&1; then
           # Disable promiscuous mode
           sudo ip link set "$interface" promisc off
           echo "Promiscuous mode is disabled on $interface."
       else
           echo "$interface does not exist."
       fi
   done
}
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
   echo "# net.ipv4.ip_forward=1" >> /etc/sysctl.conf
else
   echo "# Forwarding IP is already configured in /etc/sysctl.conf."
fi
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
apt-get install -y bridge-utils
# Create a new bridge br0
echo "# Create a new bridge br0..."
brctl addbr br0
# Add eth1 and eth2 on bridge (the eth0 interface will be used for remote capture)
echo "# Add the interfaces eth1 and eth2 on bridge br0..."
brctl addif br0 eth1
brctl addif br0 eth2
# Set the interfaces eth1 and eth2 in UP mode
echo "# Set br0, eth1 and eth2 in UP mode..."
ip link set eth1 up
ip link set eth2 up
ip link set br0 up
# Set also eth0 in UP mode
ip link set eth0 up
# Deactivate the promiscuity mode for eth1, eth2 and br0
disable_promiscuous_mode eth1 eth2 br0
# Activate the promiscuity mode only for eth0 to capture all the network traffic
echo "# Activation of promiscuity mode on eth0 for network traffic..."
ip link set eth0 promisc on
# Finale confirmation and summary of the configurations
echo "# Configuration finished successfully !"
echo "# Summary of perform actions :"
echo "#  - Deletion of the older existing bridge."
echo "#  - Forwarding activation on eth1 and eth2."
echo "#  - The interface eth0 is configured in promiscuity mode to capture the network traffic."
echo "#  - You can now use Wireshark on eth0 to sniff all the network traffic between eth1 and eth2."
