#!/bin/bash


su - colaborativa <<!
Col@borativa@890
echo "Iniciando ajustes..."

e
echo Col@borativa@890 | sudo -S sed -i 's/#WaylandEnable/WaylandEnable/' /etc/gdm3/custom.conf

echo Col@borativa@890 | sudo -S apt update
echo Col@borativa@890 | sudo -S apt install -y curl vim


#Libera SSH 
echo Col@borativa@890 | sudo -S apt -y install openssh-server
echo Col@borativa@890 | sudo -S systemctl enable ssh 
echo Col@borativa@890 | sudo -S systemctl start ssh

#Atualiza o Chrome
wget -c https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
echo Col@borativa@890 | sudo -S  dpkg -i google-chrome-stable_current_amd64.deb

echo Col@borativa@890 | sudo -S apt update
echo Col@borativa@890 | sudo -S apt install -y printer-driver-escpr
!
echo “Ajustes finalizados…”
