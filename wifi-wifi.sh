#!/bin/bash

# Environment file to store persistent variables
ENV_FILE=~/wifi_env.sh

# File containing WiFi credentials
WIFI_PASS_FILE=~/wifipass.txt

# Helper message
show_help() {
    echo "Usage: $0 [interface|nickname] [--skip] [--clean]"
    echo ""
    echo "interface    The network interface to connect to the internet (e.g., wlan0, wlan1, eth0)."
    echo "nickname     Use 'TheOne' for the USB antenna or 'caca' for the internal antenna."
    echo "--skip       Skip package updates, installations, and network reset."
    echo "--clean      Remove all configuration files and restart services to default state."
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

# Function to reset network interfaces to default state
reset_network_interfaces() {
    echo "####################"
    echo "Resetting network interfaces to default state..."

    # Remove any existing configuration files
    sudo rm -f /etc/hostapd/hostapd.conf
    sudo rm -f /etc/dnsmasq.conf
    sudo rm -f /etc/dhcpcd.conf
    sudo rm -f $ENV_FILE

    # Restart network services
    sudo systemctl restart network-manager
}

# Function to connect an interface to the internet
connect_to_internet() {
    local interface=$1
    echo "####################"
    echo "Connecting $interface to the internet..."
    nmcli dev wifi connect "\"$SSID\"" password "\"$PASSWORD\"" ifname "$interface"
}

# Function to set up a WiFi hotspot
setup_hotspot() {
    local interface=$1
    echo "####################"
    echo "Setting up $interface as a WiFi hotspot..."

    # Configure hostapd
    sudo bash -c "cat > /etc/hostapd/hostapd.conf" <<EOF
interface=$interface
ssid=PiHotspot
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=raspberry
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

    # Configure dnsmasq
    sudo bash -c "cat > /etc/dnsmasq.conf" <<EOF
interface=$interface
dhcp-range=192.168.220.10,192.168.220.50,255.255.255.0,24h
EOF

    # Configure dhcpcd
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
if [[ $1 == "--help" ]]; then
    show_help
    exit 0
fi

if [[ $1 == "--clean" ]]; then
    reset_network_interfaces
    exit 0
fi

if [[ ! -f $ENV_FILE ]]; then
    detect_and_assign_nicknames
else
    source $ENV_FILE
fi

# Read WiFi credentials from ~/wifipass.txt
if [[ -f $WIFI_PASS_FILE ]]; then
    SSID=$(sed -n '1p' $WIFI_PASS_FILE)
    PASSWORD=$(sed -n '2p' $WIFI_PASS_FILE)
    
    # Check if SSID or PASSWORD is empty
    if [[ -z "$SSID" || -z "$PASSWORD" ]]; then
        echo "Error: SSID or password is empty in $WIFI_PASS_FILE."
        exit 1
    fi
else
    echo "Error: WiFi credentials file $WIFI_PASS_FILE not found."
    exit 1
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

# Disconnect all other wireless interfaces before connecting the designated one
for intf in $(iw dev | grep Interface | awk '{print $2}'); do
    if [[ $intf != $internet_interface ]]; then
        nmcli dev disconnect $intf
    fi
done

# Connect the designated interface to the internet
connect_to_internet "$internet_interface"

# Setup the other interface as a hotspot
setup_hotspot "$hotspot_interface"
