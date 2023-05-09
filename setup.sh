#!/bin/bash

echo "Iniciando ajustes..."
sudo -S sed -i 's/#WaylandEnable/WaylandEnable/' /etc/gdm3/custom.conf
sudo -S apt update
sudo -S apt install -y curl vim figlet 


#Libera SSH 
figlet  "Liberando ssh"
sudo -S apt -y install openssh-server
sudo -S systemctl enable ssh 
sudo -S systemctl start ssh

#Atualiza o Chrome
figlet "Instalando o chrome"
wget -c https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo -S  dpkg -i google-chrome-stable_current_amd64.deb

figlet "Instalando o driver da impressora"
sudo -S apt update
sudo -S apt install -y printer-driver-escpr

read -p "Você deseja instalar GIMP, Visual Studio, Kdenlive, shotcut e shotwell ? [s/n]: " choice
if [[ "$choice" == [Ss]* ]]; then
  figlet "Instalando gimp"
  sudo -S apt install -y gimp
  figlet "Instalando vs code"
  wget -q https://packages.microsoft.com/keys/microsoft.asc -O- | sudo apt-key add -
  sudo add-apt-repository "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main"
  sudo apt update
  sudo -S apt install code

  figlet "Instalando kdenlive"
  sudo -S apt install -y kdenlive
  
  figlet "Instalando shotcut e shotwell"
  sudo -S apt install -y shotcut
  sudo -S apt install -y shotwell
  
fi

figlet “Ajustes finalizados…”
figlet "Não se esqueça de instalar o gerenciador de extensões - o draw on your screen (windows+alt+d) "
