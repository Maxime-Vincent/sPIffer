#!/bin/bash

cd ..
sudo chmod 775 -R sPIffer
sudo chown -R root:root sPIffer
sudo dpkg-deb --build sPIffer
sudo mkdir sPIffer/dist
sudo mv *.deb sPIffer/dist