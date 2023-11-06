
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

# Function to detect wireless interfaces and assign nicknames


# ASCII Art
echo "   /------------------------\\"
echo "  /                          \\"
echo " /        BANK OF ASCII       \\"
echo "/______________________________\\__________"
echo "|  ____    _______            |  \\VPN/   |"
echo "| |ATM |  |       |           |   | |    |"
echo "| |____|  |   $   |           |   |_|    |"
echo "|         |_______|           |  /___\\   |"
echo "|     |           |           |         |"
echo "|_____|___________|___________|_________|"

show_help() {
    echo "Usage: $0 [internet_interface] [hotspot_interface] [--skip] [--clean]"
    echo ""
    echo "internet_interface    The network interface to connect to the internet (e.g., wlan0, wlan1, eth0)."
    echo "hotspot_interface     The network interface to set up as a hotspot (e.g., wlan0, wlan1). Use 'none' if no hotspot is needed."
    echo "--skip                Skip package updates, installations, and network reset."
    echo "--clean               Remove all configuration files and restart services to default state."
    echo ""
    echo "If no interfaces are specified, defaults will be used (USB antenna for internet, internal antenna for hotspot)."
    echo "If 'none' is specified for hotspot_interface, no hotspot will be set up."
}



list_interfaces() {
    echo "Available network interfaces:"
    local count=1
    local interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo")
    for interface in $interfaces; do
        local mac=$(ip link show $interface | awk '/ether/ {print $2}')
        local type=""
        if [[ $(lsusb | grep -i "USB wireless") ]] && [[ $(iw dev $interface info | grep 'Interface') ]]; then
            type="USB antenna"
        elif [[ $(iw dev $interface info | grep 'Interface') ]]; then
            type="Internal antenna"
        fi
        echo "$count) $interface - MAC: $mac ($type)"
        let count++
    done
}

choose_interfaces() {
    # List available interfaces
    list_interfaces

    local interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo"))
    local number_of_interfaces=${#interfaces[@]}

    # Prompt user to choose internet interface by number
    while true; do
        echo "Enter the number of the interface you want to use for the internet connection:"
        read internet_interface_number
        if [[ $internet_interface_number -ge 1 && $internet_interface_number -le $number_of_interfaces ]]; then
            internet_interface=${interfaces[$internet_interface_number-1]}
            break
        else
            echo "Invalid selection. Please enter a number between 1 and $number_of_interfaces."
        fi
    done
    
    # Prompt user to choose hotspot interface by number or 'none'
    while true; do
        echo "Enter the number of the interface you want to set up as a hotspot, or 'none' if no hotspot is needed:"
        read hotspot_interface_number
        if [[ $hotspot_interface_number == "none" ]]; then
            hotspot_interface="none"
            break
        elif [[ $hotspot_interface_number -ge 1 && $hotspot_interface_number -le $number_of_interfaces ]]; then
            hotspot_interface=${interfaces[$hotspot_interface_number-1]}
            break
        else
            echo "Invalid selection. Please enter a number between 1 and $number_of_interfaces or 'none'."
        fi
    done
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

# Prompt user to choose interfaces
choose_interfaces

# Proceed with the rest of the script...


() {
    local usb_interface=$(lsusb | grep -i wireless | awk '{print $2":"$4}' | sed 's/://g')
    local good_interface=$(iw dev | grep -B 1 "$usb_interface" | awk '$1=="Interface" {print $2}')
    local caca_interface=$(iw dev | grep -v "$good_interface" | awk '$1=="Interface" {print $2}' | head -n 1) 
    echo "caca = $caca_interface"
    echo "good = $good_interface"
    # Store the nicknames and associated interfaces in the environment file

    # Source the environment file to make variables available in the current session
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

    # Check if the selected interface is Ethernet
    if [[ $interface == "eth0" ]]; then
        sudo nmcli con up id "$(nmcli -t -f NAME con show --active | grep 'eth0')"
    else
        # If it's a wireless interface, proceed with WiFi connection
        sudo nmcli dev set $interface managed yes
        echo "########################"
        echo "Sleeping 4sec"
        sleep 4
        nmcli dev wifi connect $SSID password $PASSWORD ifname $interface
    fi
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

    # New logic to handle 'none' selection for the hotspot
    if [[ $interface == "none" ]]; then
        echo "No hotspot setup required."
        return 0
    fi



# Main execution
if [[ $1 == "--help" ]]; then
    show_help
    exit 0
fi

if [[ $1 == "--clean" ]]; then
    reset_network_interfaces
    exit 0
fi

# Check if the user has provided both internet and hotspot interface arguments
if [[ -n $1 ]] && [[ -n $2 ]]; then
    internet_interface=$1
    hotspot_interface=$2
else
    # If not, prompt the user to choose interfaces
    choose_interfaces
fi

# Proceed with the rest of the script...


 {
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


