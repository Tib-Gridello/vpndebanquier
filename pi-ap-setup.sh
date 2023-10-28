#!/bin/bash

# Update and install required packages without prompts
sudo DEBIAN_FRONTEND=noninteractive apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y hostapd dnsmasq nftables dhcpcd5 openvpn vim

# Stop and disable the services while we configure them
sudo systemctl stop hostapd
sudo systemctl stop dnsmasq
sudo systemctl unmask hostapd
sudo systemctl disable hostapd
sudo systemctl disable dnsmasq

# Configure hostapd for Wi-Fi access point
HOSTAPD_CONF="/etc/hostapd/hostapd.conf"
if [ ! -f "$HOSTAPD_CONF" ]; then
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
rsn_pairwise=CCMP" | sudo tee "$HOSTAPD_CONF"
fi

# Point the default configuration to the file we've just created
if ! grep -q 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' /etc/default/hostapd; then
    echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' | sudo tee -a /etc/default/hostapd
fi

# Configure dnsmasq
DNSMASQ_CONF="/etc/dnsmasq.conf"
if [ ! -f "$DNSMASQ_CONF" ]; then
    echo "interface=wlan0
dhcp-range=192.168.220.50,192.168.220.150,12h" | sudo tee "$DNSMASQ_CONF"
fi
# Set up IP forwarding with nftables
NFTABLES_CONF="/etc/nftables.conf"
if [ ! -f "$NFTABLES_CONF" ]; then
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
}" | sudo tee "$NFTABLES_CONF"
    
    # Flush current ruleset
    sudo nft flush ruleset
    
    # Load the new ruleset
    sudo nft -f "$NFTABLES_CONF"
fi


# Ensure IP Forwarding is enabled
if grep -q '^#net.ipv4.ip_forward=1' /etc/sysctl.conf; then
    # Uncomment the line
    sudo sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
elif ! grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf; then
    # Append the line if it doesn't exist
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p

# Set static IP for wlan0
if ! grep -q 'interface wlan0' /etc/dhcpcd.conf; then
    echo -e "\ninterface wlan0\nstatic ip_address=192.168.220.1/24" | sudo tee -a /etc/dhcpcd.conf
fi

# Enable and start the services
sudo systemctl enable nftables
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq
sudo systemctl start nftables
sudo systemctl start hostapd
sudo systemctl start dnsmasq

# Print a success message
echo "Wi-Fi hotspot setup complete! Connect to 'lereseauderemi' with the password '1111111111'."
