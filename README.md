# sPIffer

> [!NOTE]
> Some dependencies are needed:  
> - tshark: ```sudo apt-get install tshark```  
> - iptables:  ```sudo apt-get install iptables```  
> - bridge-utils: ```sudo apt-get install bridge-utils```  

## Script Description
This Bash script configures network forwarding on a Raspberry Pi by setting up a bridge between two Ethernet interfaces (eth1 and eth2). It also enables traffic capture on a third interface (eth0) in promiscuous mode. Below are the key steps and features of the script:
## Key Features
1. Remove Existing Bridges: The script starts by clearing any pre-existing network bridges to ensure a clean setup.
2. Check Network Interfaces: It verifies the availability of the required interfaces (eth0, eth1, and eth2) to ensure they are active and ready for configuration.
3. Enable IP Forwarding: The script enables IP forwarding, allowing packets to be routed between the interfaces.
4. Create a Bridge: It creates a new bridge named br0 and attaches eth1 and eth2 to it, facilitating the transfer of traffic between these two interfaces.
## Use Case
This setup is ideal for scenarios where network traffic analysis is needed, such as monitoring for performance, security, or debugging purposes. By capturing traffic in real-time, users can gain insights into data flow and network behavior.
Feel free to modify any part of this description to better fit your style or specific requirements!
