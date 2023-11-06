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

reset_network_interfaces() {
    echo "####################"
    echo "Resetting network interfaces to default state..."

    # Remove any existing configuration files
    sudo rm -f /etc/hostapd/hostapd.conf
    sudo rm -f /etc/dnsmasq.conf
    sudo rm -f /etc/dhcpcd.conf
    sudo rm -f $ENV_FILE
    sudo rm -f /etc/NetworkManager/system-connections/*
    # Remove interface-specific configuration files
    sudo rm -f /etc/NetworkManager/conf.d/wlan0.conf
    sudo rm -f /etc/NetworkManager/conf.d/wlan1.conf

    # Restart network services
    if systemctl list-units --full -all | grep -Fq 'NetworkManager.service'; then
        sudo systemctl restart NetworkManager
    elif systemctl list-units --full -all | grep -Fq 'network-manager.service'; then
        sudo systemctl restart network-manager
    else
        echo "NetworkManager service not found. Please install or start the service manually."
    fi

    # Ensure both interfaces are managed by NetworkManager
    if [[ -f $ENV_FILE ]]; then
        source $ENV_FILE
        nmcli dev set $TheOne managed yes
        nmcli dev set $caca managed yes
    else
        echo "Environment file $ENV_FILE not found. Cannot set interfaces as managed."
    fi
}
echo "Disconnecting other interfaces..."
for intf in $(iw dev | grep Interface | awk '{print $2}'); do
    if [[ $intf != $internet_interface ]]; then
        echo "Disconnecting $intf..."
        nmcli dev disconnect $intf
        # Explicitly tell NetworkManager to ignore this interface
        echo "Telling NetworkManager to ignore $intf..."
        sudo nmcli dev set $intf managed no
    fi
done
# Function to connect an interface to the internet
connect_to_internet() {
    local interface=$1
    echo "####################"
    echo "Connecting $interface to the internet..."
    sudo nmcli dev set $1 managed yes
    echo "########################"
    echo "Sleeping 4sec"
    sleep 4
    nmcli dev wifi connect $SSID password $PASSWORD ifname $interface
}

# Function to set up a WiFi hotspot
setup_hotspot() {
    local interface=$1
    echo "####################"
    echo "Setting up $interface as a WiFi hotspot..."

    # Tell NetworkManager to ignore this interface
    echo "Telling NetworkManager to ignore $interface..."
    cp network_manager.conf.template network_manager_$interface.conf
sed -i "s/\$1/$interface/g" network_manager_$interface.conf
[keyfile]
unmanaged-devices=interface-name:$interface
EOF

    # Restart NetworkManager to apply changes
    sudo systemctl restart NetworkManager

    # Configure hostapd
    echo "Configuring hostapd..."
    cp /mnt/data/config/hostapd.conf.template hostapd.conf
sed -i "s/\$1/$1/g" hostapd.conf
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

    # Ensure hostapd knows where to find the configuration file
    echo "DAEMON_CONF=\"/etc/hostapd/hostapd.conf\"" | sudo tee -a /etc/default/hostapd

    # Configure dnsmasq
    echo "Configuring dnsmasq..."
    cp /mnt/data/config/dnsmasq.conf.template dnsmasq.conf
sed -i "s/\$1/$interface/g" dnsmasq.conf
interface=$interface
dhcp-range=192.168.220.10,192.168.220.50,255.255.255.0,24h
EOF

    # Configure dhcpcd
    echo "Configuring dhcpcd..."
    cp /mnt/data/config/dhcpcd.conf.template dhcpcd.conf
sed -i "s/\$1/$interface/g" dhcpcd.conf
interface $interface
static ip_address=192.168.220.1/24
nohook wpa_supplicant
EOF

    # Restart services
    echo "Restarting network services..."
    sudo systemctl daemon-reload
    sudo systemctl restart dhcpcd
    sudo systemctl unmask hostapd
    sudo systemctl enable hostapd
    sudo systemctl restart hostapd
    sudo systemctl enable dnsmasq
    sudo systemctl restart dnsmasq

    # Check service status
    echo "Checking hostapd status..."
    sudo systemctl status hostapd | grep "Active"
    echo "Checking dnsmasq status..."
    sudo systemctl status dnsmasq | grep "Active"
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



# Disconnect all other wireless interfaces before connecting the designated one
for intf in $(iw dev | grep Interface | awk '{print $2}'); do
    if [[ $intf != $internet_interface ]]; then
        nmcli dev disconnect $intf
    fi
done

reset_network_interfaces
# Connect the designated interface to the internet
connect_to_internet "$1"

# Setup the other interface as a hotspot
setup_hotspot "$2"

