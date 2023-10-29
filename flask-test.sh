	#!/bin/bash

# Step 1: Install required packages

echo "[+] Installing required packages..."
sudo apt-get update
sudo apt-get install -y python3-pip
sudo pip3 install Flask Flask-WTF Flask-Session

# Step 2: Set up the Flask application

echo "[+] Setting up Flask application..."

# Creating the directory structure
mkdir -p ~/pi_vpn_wifi_selector/templates

# Creating the Flask app.py
cat <<EOL > ~/pi_vpn_wifi_selector/app.py
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
cat <<EOL > ~/pi_vpn_wifi_selector/templates/index.html
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

# Step 3: Display the Raspberry Pi's IP address

IP_ADDRESS=$(hostname -I | awk '{print $1}')
echo "[+] Setup complete! Connect to the Raspberry Pi's WiFi network and then access:"
echo "http://$IP_ADDRESS"

