#!/bin/bash

echo "Iniciando ajustes..."
sudo -S sed -i 's/#WaylandEnable/WaylandEnable/' /etc/gdm3/custom.conf
sudo -S apt update
sudo -S apt install -y curl vim


#Libera SSH 
echo  "Liberando ssh"
sudo -S apt -y install openssh-server
sudo -S systemctl enable ssh 
sudo -S systemctl start ssh

#Atualiza o Chrome
echo "Instalando o chrome"
wget -c https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo -S  dpkg -i google-chrome-stable_current_amd64.deb

echo "Instalando o driver da impressora"
sudo -S apt update
sudo -S apt install -y printer-driver-escpr
!
echo “Ajustes finalizados…”
