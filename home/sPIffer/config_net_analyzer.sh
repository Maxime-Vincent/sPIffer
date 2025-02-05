#!/bin/bash

LOG_FILE="/var/log/network_setup.log"

# Supprimer l'ancien fichier de log
if [ -f "$LOG_FILE" ]; then
    rm -f "$LOG_FILE"
fi

# Rediriger toute la sortie vers le fichier de log
exec > >(tee -a "$LOG_FILE") 2>&1

echo "----------------------------------------------------"
echo "# Starting network configuration and optimization script..."
echo "----------------------------------------------------"

# Vérification des permissions root
if [[ $EUID -ne 0 ]]; then
    echo "# Error: Please run this script as root or use sudo."
    exit 1
fi

# Fonction pour vérifier si une interface existe
check_interface_exists() {
    if ! ip link show "$1" &> /dev/null; then
        echo "# Error: Interface $1 is not available."
        exit 1
    fi
}

# Fonction pour ajouter une règle iptables si elle n'existe pas déjà
add_iptables_rule() {
    local rule="$1"
    if ! iptables-save | grep -q -- "$rule"; then
        iptables $rule
        echo "# Added iptables rule: $rule"
    else
        echo "# Iptables rule already exists: $rule"
    fi
}

# Désactivation du Wi-Fi
echo "# Disabling Wi-Fi (wlan0)..."
sudo ip link set wlan0 down
echo "----------------------------------------------------"

# Vérification des interfaces réseau
echo "# Checking network interfaces (eth0, eth1, and eth2)..."
for interface in eth0 eth1 eth2; do
    check_interface_exists "$interface"
done
echo "# Interfaces eth0, eth1, and eth2 are available."
echo "----------------------------------------------------"

# Désactivation des interfaces avant configuration
echo "# Disabling interfaces..."
for interface in eth0 eth1 eth2; do
    sudo ip link set "$interface" down
done

# Suppression du pont br0 s'il existe
if ip link show br0 &> /dev/null; then
    echo "# Removing existing bridge br0."
    sudo ip link set br0 down
    sudo brctl delbr br0
else
    echo "# No existing bridge br0 to delete."
fi
echo "----------------------------------------------------"

# Activation du forwarding IPv4
echo "# Enabling IPv4 forwarding..."
echo 1 > /proc/sys/net/ipv4/ip_forward
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    echo "# IPv4 forwarding configuration added to /etc/sysctl.conf"
fi
sysctl -p /etc/sysctl.conf
echo "----------------------------------------------------"

# Application des optimisations réseau pour IPv4 si le fichier n'existe pas
if [ ! -f /etc/sysctl.d/custom_network.conf ]; then
    echo "# Applying advanced network optimizations for IPv4..."
    cat <<EOF > /etc/sysctl.d/custom_network.conf
net.core.rmem_default=26214400
net.core.wmem_default=26214400
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.core.optmem_max=67108864
net.core.netdev_max_backlog=10000
net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864
net.ipv4.tcp_mem=67108864 67108864 67108864
net.ipv4.tcp_congestion_control=cubic
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_low_latency=1
net.ipv4.ipfrag_high_thresh=16777216
net.ipv4.ipfrag_low_thresh=15728640
net.ipv4.ipfrag_time=30
EOF
    sysctl --system
    echo "# Advanced network optimizations applied for IPv4."
else
    echo "# IPv4 optimizations already applied. Skipping configuration."
fi
echo "----------------------------------------------------"

# Désactivation des fonctionnalités d'offloading
echo "# Disabling offloading features on eth1 and eth2..."
for interface in eth1 eth2; do
    sudo ethtool -K "$interface" tso off gso off gro off lro off
done

# Configuration du MTU
echo "# Setting MTU to 9000 on eth1, eth2, and br0..."
sudo ip link set eth1 mtu 9000
sudo ip link set eth2 mtu 9000
sudo ip link set br0 mtu 9000
echo "----------------------------------------------------"

# Création du pont réseau
echo "# Creating the bridge br0 and adding interfaces eth1 and eth2..."
sudo brctl addbr br0
sudo brctl addif br0 eth1
sudo brctl addif br0 eth2

# Configurer les paramètres du pont
sudo brctl setbridgeprio br0 0
sudo brctl setfd br0 0

# Activation du mode promiscuité
echo "# Enabling promiscuous mode on eth1, eth2, and br0..."
for interface in eth1 eth2 br0; do
    sudo ip link set "$interface" promisc on
done

# Désactivation du mode promiscuité pour eth0
echo "# Deactivating promiscuous mode on eth0 for network traffic..."
sudo ip link set eth0 promisc off

# Configuration des règles iptables
echo "# Configuring iptables rules for forwarding between eth1 and eth2..."
add_iptables_rule "-A FORWARD -i eth1 -o eth2 -j ACCEPT"
add_iptables_rule "-A FORWARD -i eth2 -o eth1 -j ACCEPT"

# Nettoyage des adresses IP
sudo ip addr flush dev eth1
sudo ip addr flush dev eth2

# Activation des interfaces
echo "# Activating interfaces eth0, eth1, eth2, and br0..."
for interface in eth0 eth1 eth2 br0; do
    sudo ip link set "$interface" up
done
echo "----------------------------------------------------"

# Vérification du pont
echo "# Verifying the bridge and forwarding between eth1 and eth2..."
sudo brctl showstp br0
echo "----------------------------------------------------"

# Démarrage du serveur web
echo "# Starting the web server..."
cd /home/sPIffer || exit 1
sudo nohup npm start > /var/log/npm_server.log 2>&1 &
sleep 2

if pgrep -f "npm start" > /dev/null; then
    echo "# Web server started successfully."
else
    echo "# Error: Failed to start the web server."
    exit 1
fi
echo "----------------------------------------------------"
echo "# Network configuration and optimizations completed."