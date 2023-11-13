from flask import Flask, render_template, request, redirect, url_for, flash
from flask_wtf import FlaskForm
from wtforms import SelectField, PasswordField, SubmitField
import os
import re
import logging
from datetime import datetime

app = Flask(__name__)
app.config['SECRET_KEY'] = 'your_secret_key_here'  # Used for form protection

# Setup logging
logging.basicConfig(filename='flask_app.log', level=logging.DEBUG)

class WiFiForm(FlaskForm):
    interface = SelectField('Interface', choices=[])
    ssid = SelectField('SSID', choices=[])
    password = PasswordField('Password')
    scan = SubmitField('Scan')
    connect = SubmitField('Connect')
    internet_interface = SelectField('Internet Interface', choices=[])
    hotspot_interface = SelectField('Hotspot Interface', choices=[])
    submit_config = SubmitField('Save Configuration')

@app.route('/', methods=['GET', 'POST'])
def index():
    form = WiFiForm()
    interfaces = get_network_interfaces()
    form.interface.choices = [(i, i) for i in interfaces]
    form.internet_interface.choices = [(i, i) for i in interfaces]
    form.hotspot_interface.choices = [(i, i) for i in interfaces]

    if form.validate_on_submit():
        if form.submit_config.data:
            save_user_configuration(form.internet_interface.data, form.hotspot_interface.data)
            flash('Configuration saved.')
            return redirect(url_for('index'))
        if form.connect.data:
            # Add the logic to update the Wi-Fi connection
            interface = form.interface.data
            ssid = form.ssid.data
            password = form.password.data
            flash('Attempting to connect to {} on {}'.format(ssid, interface))
            return redirect(url_for('index'))

    return render_template('index.html', form=form, scanned=False)

@app.route('/scan', methods=['GET', 'POST'])
def scan():
    form = WiFiForm()

    if request.method == 'POST':
        selected_interface = form.interface.data
        logging.debug(f"Scanning on {selected_interface}")
        return execute_scan(selected_interface)
    else:
        # GET request: Display interfaces for scanning
        interfaces = get_network_interfaces()
        form.interface.choices = [(i, i) for i in interfaces]
        return render_template('index.html', form=form, scanned=False)

def save_user_configuration(internet_interface, hotspot_interface):
    config = {
        'internet_interface': internet_interface,
        'hotspot_interface': hotspot_interface
    }
    with open('user_config.json', 'w') as f:
        json.dump(config, f)

def save_wifi_credentials(ssid, password):
    wifi_dir = os.path.expanduser('~/wifi')
    os.makedirs(wifi_dir, exist_ok=True)
    file_path = os.path.join(wifi_dir, ssid)
    with open(file_path, 'w') as f:
        f.write(password)
        
def get_network_interfaces():
    interfaces = [i for i in os.listdir('/sys/class/net/') if re.match(r'wlan\d+', i)]
    return interfaces

def execute_scan(interface):
    command = ['sudo', 'iwlist', interface, 'scan']
    scan_output = os.popen(' '.join(command)).read()
    
    # Save scan output and extract SSIDs
    save_scan_output(interface, scan_output)
    ssids = extract_ssids(scan_output)

    form = WiFiForm()
    form.ssid.choices = [(s, s) for s in ssids]
    return render_template('index.html', form=form, scanned=True)

def save_scan_output(interface, scan_output):
    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    filename = f"scans/{interface}-scan{timestamp}.txt"
    os.makedirs(os.path.dirname(filename), exist_ok=True)
    with open(filename, 'w') as f:
        f.write(scan_output)

def extract_ssids(scan_output):
    ssids = [line for line in scan_output.splitlines() if "ESSID" in line]
    ssids = [re.search(r'"(.*?)"', s).group(1) for s in ssids if re.search(r'"(.*?)"', s)]
    return ssids


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5555)
