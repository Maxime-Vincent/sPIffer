# sPIffer

> [!NOTE]
> Some dependencies are needed if you choose not to install it using the package .deb:  
> - tshark: ```sudo apt-get install tshark```  
> - iptables:  ```sudo apt-get install iptables```  
> - bridge-utils: ```sudo apt-get install bridge-utils```
> - nodejs: ```sudo apt-get install nodejs```
> - npm: ```sudo apt-get install npm```
> - pkg: ```sudo npm install dpkg```
> - libpam0g-dev: ```sudo apt-get install libpam0g-dev```

## Script Description
This package configures network forwarding on a Raspberry Pi by setting up a bridge (br0) between two added Ethernet interfaces (eth1 and eth2). It also enables traffic capture beyond the bridge (br0) which is in promiscuous mode.
## Key Features
1. Remove Existing Bridges: The script starts by clearing any pre-existing network bridges to ensure a clean setup.
2. Check Network Interfaces: It verifies the availability of the required interfaces (eth0, eth1, and eth2) to ensure they are active and ready for configuration.
3. Enable IP Forwarding: The script enables IP forwarding, allowing packets to be routed between the interfaces.
4. Create a Bridge: It creates a new bridge named br0 and attaches eth1 and eth2 to it, facilitating the transfer of traffic between these two interfaces.
5. It launches a web server that allows the user to start capturing and downloading network traffic.
## Use Case
This setup is ideal for scenarios where network traffic analysis is needed, such as monitoring for performance, security, or debugging purposes. By capturing traffic in real-time, users can gain insights into data flow and network behavior.

## Manual installation

### Create certificate with openssl

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout server.key -out server.crt

### Launch Server

    sudo node server.js

or

    sudo npm start

### Create package sPIffer

    sudo dpkg-deb --build sPIffer/

### Install package sPIffer

    sudo dpkg -i sPIffer.deb
