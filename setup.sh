#!/bin/bash

# Determine the home directory of the current user
HOMEDIR=$(eval echo ~$USER)

# Install required packages and set up the virtual environment
echo "[+] Installing required packages and setting up the virtual environment..."
sudo apt-get update
sudo apt-get install -y python3-pip python3-venv

# Set up a virtual environment
mkdir -p $HOMEDIR/pi_vpn_wifi_selector
python3 -m venv $HOMEDIR/pi_vpn_wifi_selector/venv

# Activate the virtual environment
source $HOMEDIR/pi_vpn_wifi_selector/venv/bin/activate

# Install the packages inside the virtual environment
pip install Flask Flask-WTF Flask-Session

echo "[+] Flask environment setup complete."

# Move the app, templates, and systemd service files to their correct locations
mv app.py $HOMEDIR/pi_vpn_wifi_selector/
mv templates $HOMEDIR/pi_vpn_wifi_selector/

echo "[+] Moved Flask app and templates."

# Create systemd service file
echo "[+] Setting up systemd service..."
cat <<EOL | sudo tee /etc/systemd/system/pi_vpn_wifi_selector.service
[Unit]
Description=Flask WiFi Selector App
After=network.target

[Service]
ExecStart=$HOMEDIR/pi_vpn_wifi_selector/venv/bin/python3 $HOMEDIR/pi_vpn_wifi_selector/app.py
WorkingDirectory=$HOMEDIR/pi_vpn_wifi_selector/
User=$USER
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# Reload the systemd manager configuration
sudo systemctl daemon-reload

# Enable and start the service
sudo systemctl enable pi_vpn_wifi_selector
sudo systemctl start pi_vpn_wifi_selector

echo "[+] Systemd service setup complete."

# Display the IP Address for wlan0
IP_ADDRESS_WLAN0=$(ip addr show wlan0 | grep inet | awk '{ print $2 }' | cut -d/ -f1)
echo "[+] Setup complete! Connect to the Raspberry Pi's WiFi network and then access:"
echo "http://$IP_ADDRESS_WLAN0:5555"

