# vpndebanquier

Prerequ

sudo apt update && sudo apt install -y systemd network-manager hostapd dnsmasq dhcpcd iw usbutils

**To check and add :**


Wireguard pour gain de vitesse
RaspAP qui permet directement la connection VPN

IGD UPnP
Faire tourner un .onion qui fait des requetes sur la pi domicile :
*Ip Local
*Ip Publique

Faut ajouter le protocole dans la boite.
Permet de bypass les ouvertures de port ?

Genere un fichier config ovpn et l'envoi par mail ?

#Network manager

wlan1 scan and  connect with nmcli device wifi list ifname wlan1 



# USB WIFI

Pour la AWUS036ACS :  
git clone aircrack-ng/rtl8821au

//pour le moment dl mon repo vpndebanquier et remplacer wifi_regd.c dans le dossier osdep/linux  
sudo make && sudo make install

# Speedtest

ALFA <--> wlan de la pi <--> internet : 9.31
wlan de la pi <--> ALFA <--> internet :
wlan de la pi  <--> eth0 : ~20
ALFA AWUS036ACS <--> eth0 : ~20
