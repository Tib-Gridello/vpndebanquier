#!/bin/bash

# Environment file to store persistent variables
ENV_FILE=~/wifi_env.sh

# File containing WiFi credentials
WIFI_PASS_FILE=~/wifipass.txt

# Helper message
show_help() {
    echo "Usage: $0 [interface|nickname] [--skip]"
    echo ""
    echo "interface    The network interface to connect to the internet (e.g., wlan0, wlan1, eth0)."
    echo "nickname     Use 'TheOne' for the USB antenna or 'caca' for the internal antenna."
    echo "--skip       Skip package updates and installations."
    echo ""
    echo "If no interface or nickname is specified, 'TheOne' (USB antenna) will be used by default."
}

# Function to detect wireless interfaces and assign nicknames
detect_and_assign_nicknames() {
    local usb_interface=$(lsusb | grep -i wireless | awk '{print $2":"$4}' | sed 's/://g')
    local good_interface=$(iw dev | grep -B 1 "$usb_interface" | awk '$1=="Interface" {print $2}')
    local caca_interface=$(iw dev | grep -v "$good_interface" | awk '$1=="Interface" {print $2}' | head -n 1)

    # Store the nicknames and associated interfaces in the environment file
    echo "export TheOne=$good_interface" > $ENV_FILE
    echo "export caca=$caca_interface" >> $ENV_FILE

    # Source the environment file to make variables available in the current session
    source $ENV_FILE
}

# Check for the --skip option
SKIP_UPDATE=false
for arg in "$@"; do
    if [[ $arg == "--skip" ]]; then
        SKIP_UPDATE=true
    fi
done

# Ensure required packages are installed
if [ "$SKIP_UPDATE" = false ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-change-held-packages hostapd dnsmasq network-manager dhcpcd5
fi

# Read WiFi credentials from ~/wifipass.txt
SSID=$(sed -n '1p' $WIFI_PASS_FILE)
PASSWORD=$(sed -n '2p' $WIFI_PASS_FILE)

# Function to reset network interfaces to default state
reset_network_interfaces() {
    echo "Resetting network interfaces to default state..."
    sudo systemctl stop hostapd
    sudo systemctl stop dnsmasq
    sudo systemctl disable hostapd
    sudo systemctl disable dnsmasq
    sudo nmcli con down id "Wired connection 1"
    sudo nmcli con up id "Wired connection 1"
    sudo nmcli con down id "Wireless connection 1"
    sudo nmcli con up id "Wireless connection 1"
    sudo rm -f /etc/hostapd/hostapd.conf
    sudo rm -f /etc/dnsmasq.conf
    sudo rm -f /etc/dhcpcd.conf
    sudo systemctl restart network-manager
}

# Function to connect an interface to the internet
connect_to_internet() {
    local interface=$1
    echo "####################"
    echo "Connecting $interface to the internet..."
    nmcli dev wifi connect "$SSID" password "$PASSWORD" ifname "$interface"
}

# Function to set up a WiFi hotspot
setup_hotspot() {
    local interface=$1
    echo "####################"
    echo "Setting up $interface as a WiFi hotspot..."

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
    sudo bash -c "cat > /etc/dhcpcd.conf" <<EOF
interface $interface
static ip_address=192.168.220.1/24
nohook wpa_supplicant
EOF

    # Restart services
    sudo systemctl daemon-reload
    sudo systemctl restart dhcpcd
    sudo systemctl unmask hostapd
    sudo systemctl enable hostapd
    sudo systemctl enable dnsmasq
    sudo systemctl start hostapd
    sudo systemctl start dnsmasq
}

# Main execution
if [[ ! -f $ENV_FILE ]]; then
    detect_and_assign_nicknames
else
    source $ENV_FILE
fi

# Set a default interface if no argument is provided
if [[ -z $1 || $1 == "--skip" ]]; then
    echo "####################"
    echo "No interface specified. Using default."
    internet_interface=$TheOne
else
    if [[ $1 == "TheOne" || $1 == "caca" ]]; then
        internet_interface=${!1}
    else
        internet_interface=$1
    fi
fi

# Determine the interface for the hotspot
if [[ $internet_interface == $TheOne ]]; then
    hotspot_interface=$caca
else
    hotspot_interface=$TheOne
fi

# Check for the --help option
if [[ $1 == "--help" ]]; then
    show_help
else
    reset_network_interfaces
    connect_to_internet "$internet_interface"
    setup_hotspot "$hotspot_interface"
fi

# Uncomment the following lines to persist settings across reboots
# sudo crontab -l > mycron
# echo "@reboot /path/to/this/script $internet_interface --skip" >> mycron
# sudo crontab mycron
# rm mycron