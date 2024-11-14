#!/bin/sh

IP_ADDR=$1

cat <<EOF > \/etc\/network\/interfaces
# interfaces(5) file used by ifup(8) and ifdown(8)
# Include files from /etc/network/interfaces.d:
source /etc/network/interfaces.d/*

auto eth0
iface eth0 inet static
address $IP_ADDR
netmask 255.255.255.0
gateway 0.0.0.0

sudo systemctl disable dhcpcd
sudo systemctl stop dhcpcd
EOF