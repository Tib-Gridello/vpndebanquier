#!/bin/bash

# Environment file to store persistent variables

# File containing WiFi credentials
WIFI_PASS_FILE=~/wifipass.txt

# Helper message
show_help() {
    echo "Usage: $0 [interface|nickname] [--skip] [--clean]"
    echo ""
    echo "interface    The network interface to connect to the internet (e.g., wlan0, wlan1, eth0)."
    echo "--skip       Skip package updates, installations, and network reset."
    echo "--clean      Remove all configuration files and restart services to default state."
    echo ""
    echo "If no interface or nickname is specified, 'TheOne' (USB antenna) will be used by default."
}


reset_network_interfaces() {
    echo "####################"
    echo "Resetting network interfaces to default state..."

    # Killing OpenVPN processes
    echo "Killing OpenVPN processes..."
    sudo pkill openvpn

    # Bring down tun0 and other interfaces
    for intf in $(ip link show | awk -F: '$0 !~ "lo|virbr|docker|^[^0-9]"{print $2;getline}'); do
        echo "Bringing down $intf..."
        sudo ip link set $intf down
    done

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
}



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

    # Restart NetworkManager to apply changes
    sudo systemctl restart NetworkManager

    # Configure hostapd
    echo "Configuring hostapd..."
    sudo cp config/hostapd.conf.template /etc/hostapd/hostapd.conf
sudo sed -i "s/\$1/$1/g" /etc/hostapd/hostapd.conf

    # Ensure hostapd knows where to find the configuration file
    echo "DAEMON_CONF=\"/etc/hostapd/hostapd.conf\"" | sudo tee -a /etc/default/hostapd

    # Configure dnsmasq
    echo "Configuring dnsmasq..."
    sudo cp config/dnsmasq.conf.template /etc/dnsmasq.conf
sudo sed -i "s/\$1/$interface/g" /etc/dnsmasq.conf

    # Configure dhcpcd
    echo "Configuring dhcpcd..."
    sudo cp config/dhcpcd.conf.template /etc/dhcpcd.conf
sudo sed -i "s/\$1/$interface/g" /etc/dhcpcd.conf

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


# Function to ask user for interface selection
ask_for_interface_selection() {
    # Display available interfaces
    echo "Available Network Interfaces:"
    interfaces=($(ip link show | awk -F: '$0 !~ "lo|virbr|docker|^[^0-9]"{print $2;getline}'))
    
    for i in "${!interfaces[@]}"; do
        echo "$((i+1)). ${interfaces[i]}"
    done

    # Check if eth0 has an IP address
    if ip addr show eth0 | grep -qw 'inet'; then
        echo "eth0 has an IP address."
        display_public_ip

        echo "eth0 will be used for the internet connection. Please choose the interface for the hotspot:"
        read -p "Enter choice (1-${#interfaces[@]}): " hotspot_choice
        hotspot_interface=${interfaces[$((hotspot_choice-1))]}
        
        # Setup the chosen interface as a hotspot
        setup_hotspot "$hotspot_interface"
    else
        echo "Choose the interface for the internet connection:"
        read -p "Enter choice (1-${#interfaces[@]}): " internet_choice
        internet_interface=${interfaces[$((internet_choice-1))]}

        echo "Choose the interface for the hotspot:"
        read -p "Enter choice (1-${#interfaces[@]}): " hotspot_choice
        hotspot_interface=${interfaces[$((hotspot_choice-1))]}

        # Connect the chosen interface to the internet
        connect_to_internet "$internet_interface"

        # Setup the other interface as a hotspot
        setup_hotspot "$hotspot_interface"
    fi
}

display_public_ip() {
    echo "##############"
    public_ip=$(curl -s ifconfig.me)
    echo "Current public IP: $public_ip"
    location=$(curl -s ipinfo.io/$public_ip/city)
    echo "Location: $location"
    echo "##############"
}

# Function to find the active VPN interface (tun0 for OpenVPN, wg0 for WireGuard, etc.)
find_vpn_interface() {
    # Add logic here to determine the VPN interface
    # This can be as simple as checking if 'tun0' or 'wg0' exists, or more complex logic based on the VPN type
    if ip link show tun0 > /dev/null 2>&1; then
        echo "tun0"
    elif ip link show wg0 > /dev/null 2>&1; then
        echo "wg0"
    else
        echo "unknown"
    fi
}

# Function to set up a VPN connection
setup_vpn() {
    echo "Setting up VPN connection..."
    
       # Display public IP before VPN connection
    echo "Public IP before VPN connection:"
    display_public_ip
    # Replace 'your-vpn-config.ovpn' with your actual OpenVPN configuration file
    sudo openvpn --config ~/vpndebanquier.ovpn &
    echo "sleeping 6s"
    sleep 6
    echo "Public IP after VPN connection:"
    display_public_ip
    # You can add similar logic for WireGuard or other VPN types
}

# Function to modify and apply nftables rules based on the active VPN interface
apply_nftables_rules() {
    local vpn_interface=$(find_vpn_interface)

    if [ "$vpn_interface" = "unknown" ]; then
        echo "Unable to determine the VPN interface. Kill switch will not be activated."
        return
    fi

    echo "Modifying nftables rules for interface: $vpn_interface"
    sudo mv ~/vpndebanquier/config/nftables.conf /etc/nftables.conf
    # Use sed to replace the placeholder in the nftables.conf file
    sudo sed -i "s/{{vpn_interface}}/$vpn_interface/g" /etc/nftables.conf

    # Apply the modified nftables rules
    sudo nft -f /etc/nftables.conf
}


# Main execution
reset_network_interfaces

# Call the function to ask for interface selection
ask_for_interface_selection
setup_vpn
find_vpn_interface
apply_nftables_rules
