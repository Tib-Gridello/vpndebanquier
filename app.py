from flask import Flask, render_template, request, redirect, url_for, flash
import os
import re
import json
import logging
from datetime import datetime
from flask_wtf import FlaskForm
from wtforms import SelectField, PasswordField, SubmitField
import subprocess
import traceback

app = Flask(__name__)
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'default_secret_key')

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

def get_network_interfaces():
    return [i for i in os.listdir('/sys/class/net/') if re.match(r'wlan\d+', i)]

def execute_scan(interface):
    command = ['sudo', 'iwlist', interface, 'scan']
    scan_output = os.popen(' '.join(command)).read()
    save_scan_output(interface, scan_output)
    return extract_ssids(scan_output)

def save_scan_output(interface, scan_output):
    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    filename = f"scans/{interface}-scan{timestamp}.txt"
    os.makedirs(os.path.dirname(filename), exist_ok=True)
    with open(filename, 'w') as f:
        f.write(scan_output)

def extract_ssids(scan_output):
    ssids = [line for line in scan_output.splitlines() if "ESSID" in line]
    return [re.search(r'"(.*?)"', s).group(1) for s in ssids if re.search(r'"(.*?)"', s)]

def save_user_configuration(internet_interface, hotspot_interface):
    config = {'internet_interface': internet_interface, 'hotspot_interface': hotspot_interface}
    with open('user_config.json', 'w') as f:
        json.dump(config, f)

def save_wifi_credentials(ssid, password):
    try:
        wifi_dir = os.path.expanduser('~/wifi')
        os.makedirs(wifi_dir, exist_ok=True)
        file_path = os.path.join(wifi_dir, ssid)
        with open(file_path, 'w') as f:
            f.write(password)
    except Exception as e:
        logging.error(f"Error saving WiFi credentials: {e}")
        traceback.print_exc()

def execute_connection_script(internet_interface, hotspot_interface, ssid):
    logging.debug(f"Starting script with ssid {ssid}")
    wifi_creds_path = os.path.expanduser(f'home/naps/wifi/{ssid}')
    script_path = os.path.expanduser('~/vpndebanquier/wifi-wifi.sh')
    command = [script_path, '--internet', internet_interface, '--hotspot', hotspot_interface, '--wifi-creds', wifi_creds_path]
    subprocess.run(command, check=True)

@app.route('/', methods=['GET', 'POST'])
def index():
    logging.debug("Entered index route")
    form = WiFiForm()
    update_interface_choices(form)

    # Check for SSIDs in query string
    ssids = request.args.get('ssids')
    if ssids:
        ssid_list = ssids.split(',')
        form.ssid.choices = [(ssid, ssid) for ssid in ssid_list]

    if form.validate_on_submit():
        if form.scan.data:
             logging.debug("form valid on sub")
            return handle_scan(form)
        elif form.connect.data:
            logging.debug(f"Connect button pressed. User selections: Interface - {form.interface.data}, SSID - {form.ssid.data}, Internet Interface - {form.internet_interface.data}, Hotspot Interface - {form.hotspot_interface.data}")
            return handle_connect(form)

    scanned = 'ssids' in request.args
    return render_template('index.html', form=form, scanned=scanned)


def update_interface_choices(form):
    interfaces = get_network_interfaces()
    form.interface.choices = [(i, i) for i in interfaces]
    form.internet_interface.choices = [('eth0', 'eth0')] + [(i, i) for i in interfaces]
    form.hotspot_interface.choices = [('eth0', 'eth0')] + [(i, i) for i in interfaces]

def handle_scan(form):
    selected_interface = form.interface.data
    logging.debug(f"Scanning on {selected_interface}")
    ssids = execute_scan(selected_interface)
    form.ssid.choices = [(s, s) for s in ssids]
    return render_template('index.html', form=form, scanned=True)

def handle_connect(form):
    logging.debug("Entered handle_connect function")
    ssid = form.ssid.data
    password = form.password.data
    internet_interface = form.internet_interface.data
    hotspot_interface = form.hotspot_interface.data

    try:
        logging.debug(f"Saving WiFi credentials for SSID: {ssid}")
        save_wifi_credentials(ssid, password)
        logging.debug("WiFi credentials saved successfully.")
        flash(f'WiFi credentials saved for {ssid}.')
        execute_connection_script(internet_interface, hotspot_interface, ssid)
        flash('Configuration saved and script executed.')
    except Exception as e:
        flash(f"Error: {e}")
        logging.error(f"Error in handle_connect: {e}")
        traceback.print_exc()

    return redirect(url_for('index'))


@app.route('/scan', methods=['POST'])
def scan():
    form = WiFiForm()
    update_interface_choices(form)
    
    selected_interface = form.interface.data
    ssids = execute_scan(selected_interface)
    return redirect(url_for('index', ssids=','.join(ssids)))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5555)