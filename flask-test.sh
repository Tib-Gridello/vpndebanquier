#!/bin/bash

# Step 1: Install required packages and set up the virtual environment

echo "[+] Installing required packages and setting up the virtual environment..."
sudo apt-get update
sudo apt-get install -y python3-pip python3-venv

# Set up a virtual environment
python3 -m venv ~/pi_vpn_wifi_selector/venv

# Activate the virtual environment
source ~/pi_vpn_wifi_selector/venv/bin/activate

# Now, install the packages inside the virtual environment
pip install Flask Flask-WTF Flask-Session

echo "[+] Flask environment setup complete."

# Step 2: Set up the Flask application

echo "[+] Setting up Flask application..."

# Creating the directory structure
mkdir -p ~/pi_vpn_wifi_selector/templates

# Creating the Flask app.py
cat <<EOL > ~/pi_vpn_wifi_selector/app.py
... (This part remains the same as the previous script) ...
EOL

# Creating the templates/index.html
cat <<EOL > ~/pi_vpn_wifi_selector/templates/index.html
... (This part remains the same as the previous script) ...
EOL

echo "[+] Flask application setup complete."

# Step 3: Create and start the systemd service

# Create systemd service file
cat <<EOL | sudo tee /etc/systemd/system/pi_vpn_wifi_selector.service
[Unit]
Description=Flask WiFi Selector App
After=network.target

[Service]
ExecStart=/home/pi/pi_vpn_wifi_selector/venv/bin/python3 /home/pi/pi_vpn_wifi_selector/app.py
WorkingDirectory=/home/pi/pi_vpn_wifi_selector/
User=pi
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# Reload the systemd manager configuration
sudo systemctl daemon-reload

# Enable and start the service
sudo systemctl enable pi_vpn_wifi_selector
sudo systemctl start pi_vpn_wifi_selector

# Display the status of the service
echo "[+] Flask service status:"
sudo systemctl status pi_vpn_wifi_selector

# Step 4: Display the IP Address for wlan0

IP_ADDRESS_WLAN0=$(ip addr show wlan0 | grep inet | awk '{ print $2 }' | cut -d/ -f1)
echo "[+] Setup complete! Connect to the Raspberry Pi's WiFi network and then access:"
echo "http://$IP_ADDRESS_WLAN0"

