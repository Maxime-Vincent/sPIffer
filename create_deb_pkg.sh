#!/bin/bash

sudo mkdir libs && sudo chmod 777 libs


echo "[INFO] Generate lib dependencies"
while read -r package; do
   apt-rdepends "$package" | grep -v "^ " >> libs/full-package-list.txt
done < package-list.txt

cd libs

sort -u full-package-list.txt -o full-package-list.txt

while read -r package; do
   echo "[INFO] Download package: $package"
   apt-get download "$package" -y
done < full-package-list.txt

cd ../..
sudo chmod 775 -R sPIffer
sudo chown -R root:root sPIffer
sudo dpkg-deb --build sPIffer
sudo mkdir sPIffer/dist
sudo mv *.deb sPIffer/dist