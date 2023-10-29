#!/bin/bash

# Determine the home directory of the current user
HOMEDIR=$(eval echo ~$USER)

# Step 1: Install required packages and set up the virtual environment

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

# Step 2: Set up the Flask application

echo "[+] Setting up Flask application..."

# Creating the Flask app.py
cat <<EOL > $HOMEDIR/pi_vpn_wifi_selector/app.py
from flask import Flask, render_template, request, redirect, url_for, flash
from flask_wtf import FlaskForm
from wtforms import SelectField, PasswordField
import os
import re

app = Flask(__name__)
app.config['SECRET_KEY'] = 'your_secret_key_here'

class WiFiForm(FlaskForm):
    interface = SelectField('Interface', choices=[])
    ssid = SelectField('SSID', choices=[])
    password = PasswordField('Password')

@app.route('/', methods=['GET', 'POST'])
def index():
    form = WiFiForm()
    interfaces = [i for i in os.listdir('/sys/class/net/') if i.startswith('wlan')]
    form.interface.choices = [(i, i) for i in interfaces]

    if form.validate_on_submit():
        interface = form.interface.data
        ssid = form.ssid.data
        password = form.password.data
        # Here, add the logic to update the Wi-Fi connection
        # Avoid direct command execution with user input
        flash('Attempting to connect to {} on {}'.format(ssid, interface))
        return redirect(url_for('index'))

    # If an interface is selected, show SSIDs for that interface
    selected_interface = request.args.get('interface')
    if selected_interface:
        ssids = os.popen('sudo iwlist {} scan | grep ESSID'.format(selected_interface)).read().splitlines()
        ssids = [re.search(r'"(.*?)"', s).group(1) for s in ssids]
        form.ssid.choices = [(s, s) for s in ssids]
    
    return render_template('index.html', form=form)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
EOL

# Creating the templates/index.html
cat <<EOL > $HOMEDIR/pi_vpn_wifi_selector/templates/index.html
<!DOCTYPE html>
<html>
<head>
    <title>Connect to Wi-Fi</title>
</head>
<body>
    {% for message in get_flashed_messages() %}
        <p>{{ message }}</p>
    {% endfor %}
    <form action="" method="post">
        {{ form.hidden_tag() }}
        <p>
            {{ form.interface.label }}<br>
            {{ form.interface }}<br>
        </p>
        <p>
            {{ form.ssid.label }}<br>
            {{ form.ssid }}<br>
        </p>
        <p>
            {{ form.password.label }}<br>
            {{ form.password }}<br>
        </p>
        <p><input type="submit" value="Connect"></p>
    </form>
</body>
</html>
EOL

echo "[+] Flask application setup complete."

# Step 3: Create and start the systemd service

# Create systemd service file
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

# Display the status of the service
echo "[+] Flask service status:"
sudo systemctl status pi_vpn_wifi_selector -l --no-pager

# Step 4: Display the IP Address for wlan0

IP_ADDRESS_WLAN0=$(ip addr show wlan0 | grep inet | awk '{ print $2 }' | cut -d/ -f1)
echo "[+] Setup complete! Connect to the Raspberry Pi's WiFi network and then access:"
echo "http://$IP_ADDRESS_WLAN0"

