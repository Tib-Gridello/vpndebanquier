#!/bin/bash
# Environment file to store persistent variables
ENV_FILE=~/wifi_env.sh

# File containing WiFi credentials
WIFI_PASS_FILE=~/wifipass.txt

# Function to detect wireless interfaces and assign nicknames
detect_and_assign_nicknames() {
    local good_interface=$(iw dev | awk '$1=="Interface" {print $2}' | head -n 1)
    local caca_interface=$(iw dev | awk '$1=="Interface" {print $2}' | tail -n 1)

    # Store the nicknames and associated interfaces in the environment file
    echo "export TheOne=$good_interface" > $ENV_FILE
    echo "export caca=$caca_interface" >> $ENV_FILE

    # Source the environment file to make variables available in the current session
    source $ENV_FILE
}

# Read WiFi credentials from ~/wifipass.txt
SSID=$(sed -n '1p' $WIFI_PASS_FILE)
PASSWORD=$(sed -n '2p' $WIFI_PASS_FILE)

# Function to connect an interface to the internet
connect_to_internet() {
    local interface=$1
    nmcli dev wifi connect "$SSID" password "$PASSWORD" iface "$interface"
}

# Function to set up a WiFi hotspot
setup_hotspot() {
    local interface=$1

    # Configure hostapd
    sudo bash -c "cat > /etc/hostapd/hostapd.conf" <<EOF
interface=$interface
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
rsn_pairwise=CCMP
EOF

    # Point the default configuration to the file we've just created
    echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' | sudo tee /etc/default/hostapd

    # Configure dnsmasq
    sudo bash -c "cat > /etc/dnsmasq.conf" <<EOF
interface=$interface
dhcp-range=192.168.220.50,192.168.220.150,12h
EOF

    # Configure nftables
    sudo bash -c "cat > /etc/nftables.conf" <<EOF
table ip nat {
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
}
EOF

    # Load the nftables ruleset
    sudo nft flush ruleset
    sudo nft -f /etc/nftables.conf

    # Ensure IP Forwarding is enabled
    sudo sed -i '/^#net.ipv4.ip_forward=1/c\net.ipv4.ip_forward=1' /etc/sysctl.conf
    sudo sysctl -p

    # Set static IP for the hotspot interface
    echo "interface $interface
static ip_address=192.168.220.1/24" | sudo tee -a /etc/dhcpcd.conf

    # Restart services
    sudo systemctl restart dhcpcd
    sudo systemctl unmask hostapd
    sudo systemctl enable nftables
    sudo systemctl enable hostapd
    sudo systemctl enable dnsmasq
    sudo systemctl start nftables
    sudo systemctl start hostapd
    sudo systemctl start dnsmasq
}

# Main execution
if [[ ! -f $ENV_FILE ]]; then
    detect_and_assign_nicknames
else
    source $ENV_FILE
fi

if [[ $1 == "TheOne" || $1 == "caca" ]]; then
    internet_interface=${!1}
else
    internet_interface=$1
fi

# Determine the interface for the hotspot
if [[ $internet_interface == $TheOne ]]; then
    hotspot_interface=$caca
else
    hotspot_interface=$TheOne
fi

connect_to_internet "$internet_interface"
setup_hotspot "$hotspot_interface"
