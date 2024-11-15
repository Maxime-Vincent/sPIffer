#!/bin/bash

sudo mkdir libs
cd libs

while read -r package; do
   apt-rdepends "$package" | grep -v "^ " >> full-package-list.txt
done < package-list.txt

sort -u full-package-list.txt -o full-package-list.txt

while read -r package; do
   apt-get download "$package" -y
done < full-package-list.txt

cd ..
for deb in libs/*.deb; do
   dpkg-deb -x "$deb" /home/sPIffer
done

sudo rm -rf libs
cd ..
sudo chmod 777 -R sPIffer
sudo dpkg-deb --build sPIffer
sudo mkdir sPIffer/dist
sudo mv *.deb /sPIffer/dist