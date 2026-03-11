# sPIffer

sPIffer is a Raspberry Pi network analyser and inline sniffer. It
configures a transparent bridge between two network interfaces and
provides a web interface to capture and download traffic.

The project is designed to run on **Raspberry Pi OS (Bookworm)**.

------------------------------------------------------------------------

# Features

-   Transparent network bridge between two Ethernet interfaces
-   Promiscuous traffic capture using **tshark**
-   Web interface to control captures
-   Automatic TLS certificate generation
-   Automatic network configuration
-   Systemd services for automatic startup
-   Packaged as a **Debian package (.deb)**

------------------------------------------------------------------------

# Architecture

sPIffer configures the following network topology:

```text
Raspberry PI eth1 -----------\
                              +-- br0 (bridge) -- Raspberry Pi
Raspberry PI eth2 -----------/
```

The bridge operates in **promiscuous mode** to allow traffic capture.

------------------------------------------------------------------------

# Dependencies

These dependencies are automatically installed when using the Debian
package.

Manual installation requires:

-   tshark
-   iptables
-   nodejs
-   npm
-   libpam0g-dev
-   network-manager
-   openssl

Example installation:

sudo apt install tshark iptables bridge-utils nodejs npm libpam0g-dev
network-manager openssl

------------------------------------------------------------------------

# Recommended Installation (Debian package)

Download the latest release:

spiffer_2.0.0_arm64.deb

Install:

sudo dpkg -i spiffer_2.0.0_arm64.deb sudo apt-get -f install

The installation automatically:

-   creates the **spiffer** system user
-   installs all files under `/usr/lib/spiffer`
-   installs systemd services
-   generates a TLS certificate
-   prepares the network bridge

------------------------------------------------------------------------

# System Services

sPIffer installs two services.

### Network configuration

spiffer-iface-config.service

Responsible for:

-   configuring the bridge
-   preparing the capture interfaces

### Web interface

spiffer-web.service

Responsible for:

-   running the Node.js server
-   exposing the web interface

Check status:

systemctl status spiffer-iface-config.service systemctl status
spiffer-web.service

Restart services:

sudo systemctl restart spiffer-iface-config.service sudo systemctl
restart spiffer-web.service

------------------------------------------------------------------------

# Web Interface

Once started, the interface is accessible at:

https://`<raspberry-ip>`{=html}:3000

From the dashboard you can:

-   start traffic capture
-   stop capture
-   download `.pcap` files

------------------------------------------------------------------------

# Manual Installation (Development)

Clone the repository:

git clone https://github.com/Maxime-Vincent/sPIffer.git cd sPIffer

Install dependencies:

sudo ./requirements.sh

Install Node modules:

npm install

Start the server manually:

sudo node src/server.js

or

npm start

------------------------------------------------------------------------

# Configuration

Environment configuration is stored in:

/etc/spiffer/spiffer.env

You can modify parameters such as:

-   network interfaces
-   capture settings
-   server configuration

Restart services after modification:

sudo systemctl restart spiffer-web

------------------------------------------------------------------------

# Development

To build the Debian package:

dpkg-buildpackage -us -uc

This generates:

spiffer_2.0.0_arm64.deb

------------------------------------------------------------------------

# License

MIT License
