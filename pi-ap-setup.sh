#!/bin/bash

# Update and install required packages without prompts
sudo DEBIAN_FRONTEND=noninteractive apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y hostapd dnsmasq nftables dhcpcd5 openvpn vim

# Stop the services while we configure them
sudo systemctl stop hostapd
sudo systemctl stop dnsmasq
sudo systemctl stop dhcpcd

# Configure hostapd for Wi-Fi access point
echo "interface=wlan0
driver=nl80211
ssid=lereseauderemi
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=1111111111
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP" | sudo tee /etc/hostapd/hostapd.conf

# Point the default configuration to the file we've just created
echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' | sudo tee /etc/default/hostapd

# Configure dnsmasq
echo "interface=wlan0
dhcp-range=192.168.220.50,192.168.220.150,12h" | sudo tee /etc/dnsmasq.conf

# Configure nftables
echo "table ip nat {
    chain prerouting { type nat hook prerouting priority 0; }
    chain postrouting {
        type nat hook postrouting priority 100;
        masquerade;
    }
}

table ip filter {
    chain input { type filter hook input priority 0; }
    chain forward {
        type filter hook forward priority 0;
        ip saddr 192.168.220.0/24 ip daddr != 192.168.220.0/24 accept
    }
    chain output { type filter hook output priority 0; }
}" | sudo tee /etc/nftables.conf

# Load the nftables ruleset
sudo nft flush ruleset
sudo nft -f /etc/nftables.conf

# Ensure IP Forwarding is enabled
sudo sed -i '/^#net.ipv4.ip_forward=1/c\net.ipv4.ip_forward=1' /etc/sysctl.conf
sudo sysctl -p

# Set static IP for wlan0
echo "interface wlan0
static ip_address=192.168.220.1/24" | sudo tee -a /etc/dhcpcd.conf

# Restart dhcpcd to apply the new configuration
sudo systemctl restart dhcpcd

# Enable and start the services
sudo systemctl unmask hostapd
sudo systemctl enable nftables
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq
sudo systemctl start nftables
sudo systemctl start hostapd
sudo systemctl start dnsmasq

# Print a success message
echo "Wi-Fi hotspot setup complete! Connect to 'lereseauderemi' with the password '1111111111'."
