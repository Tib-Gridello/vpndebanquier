#!/bin/bash

# Environment file to store persistent variables

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

    # Check eth0 connectivity
    if ip link show eth0 | grep -qw 'UP' && ping -c 1 -I eth0 8.8.8.8 >/dev/null 2>&1; then
        echo "eth0 is connected to the internet. Please choose the interface for the hotspot:"
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

# Main execution
reset_network_interfaces
display_interfaces_and_check_eth0

# Call the function to ask for interface selection
ask_for_interface_selection

