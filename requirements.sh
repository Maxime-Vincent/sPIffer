#!/bin/bash

set -e

sudo apt-get update
sudo apt-get install tshark=4.0.17
sudo apt-get install iptables=1.8.9
sudo apt-get install bridge-utils=1.7.1
sudo apt-get install nodejs=18.19.0
sudo apt-get install npm=9.2.0
sudo apt-get install libpam0g-dev=1.5.2