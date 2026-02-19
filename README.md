# sPIffer

> [!NOTE]
> Some dependencies are needed if you choose not to install it using the ```requirements.sh```:  
> - tshark: ```sudo apt-get install tshark```  
> - iptables:  ```sudo apt-get install iptables```  
> - bridge-utils: ```sudo apt-get install bridge-utils```
> - nodejs: ```sudo apt-get install nodejs```
> - npm: ```sudo apt-get install npm```
> - libpam0g-dev: ```sudo apt-get install libpam0g-dev```

Passive Inline Network Tap & Bridge Sniffer for Industrial Test & Debug

sPIffer is a passive network capture and analysis tool designed for industrial, test, and debugging environments.
It operates as an inline Ethernet tap using a transparent Layer-2 Linux bridge, allowing traffic observation without modifying the system under test.

⚠️ sPIffer does not modify, inject, redirect, replay, or manipulate network traffic.
It is intended only for networks you own or are explicitly authorized to analyze.

⸻

🎯 Project Goal

In industrial environments (PLCs, IO modules, HMIs, test benches, field protocols), it is often necessary to:
	•	observe real network traffic without impacting behavior
	•	capture exchanges for offline analysis
	•	debug intermittent issues (timeouts, resets, latency)
	•	generate traceable network evidence (PCAPs with timestamps)

sPIffer provides a simple, reproducible inline observation box based on standard Linux networking.

⸻

🧠 How It Works

•	eth1 and eth2 are connected through a Linux bridge (br0)
	•	traffic flows at Layer 2 (Ethernet), like a switch
	•	packet capture is performed read-only on the bridge
	•	no NAT, proxy, routing, or packet alteration

👉 Network behavior remains strictly unchanged.

⸻

✅ What sPIffer Does
	•	Creates a transparent Ethernet L2 bridge
	•	Enables promiscuous mode for capture only
	•	Captures traffic using tshark / dumpcap
	•	Provides PCAP download capability
	•	Offers a local web interface to control captures

⸻

❌ What sPIffer Does NOT Do
	•	❌ modify packets
	•	❌ inject or replay traffic
	•	❌ perform application-level interception (TLS, credentials, etc.)
	•	❌ act as a network proxy or router
	•	❌ bypass or weaken security mechanisms

sPIffer is not an offensive MITM tool.

⸻

🧪 Typical Use Cases
	•	Modbus TCP, EtherNet/IP, OPC UA, and industrial TCP/IP debugging
	•	Intermittent communication issue analysis
	•	Protocol compliance validation
	•	Network non-regression testing
	•	Functional network audits in controlled environments

⸻

🖥️ Target Environment
	•	Raspberry Pi (or equivalent ARM/x86 system)
	•	Linux OS
	•	At least two physical Ethernet interfaces
	•	Root access required (bridge + packet capture)

⸻

🔐 Security & Best Practices
	•	The web interface should be used on a trusted network
	•	Recommended:
	•	bind to localhost
	•	restrict access via SSH tunnel or VPN
	•	regularly clean captured PCAP files
	•	Captures may contain sensitive data → handle accordingly

⸻

⚠️ Legal Notice

This tool is intended for:
	•	test environments
	•	private industrial networks
	•	systems for which you have explicit authorization

The user is solely responsible for ensuring legal and compliant usage.

⸻

🚧 Project Status

sPIffer is currently:
	•	functional for passive network capture
	•	evolving toward a reusable library
	•	focused on robustness, traceability, and industrial QA

Contributions and feedback are welcome.