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
    wifi_creds_path = os.path.expanduser(f'~/wifi/{ssid}')
    script_path = os.path.expanduser('~/vpndebanquier/wifi-wifi.sh')
    command = [script_path, '--internet', internet_interface, '--hotspot', hotspot_interface, '--wifi-creds', wifi_creds_path]
    subprocess.run(command, check=True)

@app.route('/', methods=['GET', 'POST'])
def index():
    form = WiFiForm()
    interfaces = get_network_interfaces()
    form.interface.choices = [(i, i) for i in interfaces]
    form.internet_interface.choices = [(i, i) for i in interfaces]
    form.hotspot_interface.choices = [(i, i) for i in interfaces]

    # Handling SSID selection and password input
    if request.args.get('ssids'):
        ssids = request.args.get('ssids').split(',')
        form.ssid.choices = [(s, s) for s in ssids]

    if form.validate_on_submit():
        if form.scan.data:
            selected_interface = form.interface.data
            logging.debug(f"Scanning on {selected_interface}")
            ssids = execute_scan(selected_interface)
            form.ssid.choices = [(s, s) for s in ssids]
        return render_template('index.html', form=form, scanned=True)

        if form.connect.data:
            try:
                ssid = form.ssid.data
                password = form.password.data
                save_wifi_credentials(ssid, password)
                flash(f'WiFi credentials saved in {ssid}. File content: {password}')
            except Exception as e:
                flash(f"Error: {e}")
                # Error handling code
            return redirect(url_for('index'))if form.connect.data:
          
        if form.submit_config.data:
            try:
                internet_interface = form.internet_interface.data
                hotspot_interface = form.hotspot_interface.data
                execute_connection_script(internet_interface, hotspot_interface, ssid)
                flash('Configuration saved and script executed.')
            except Exception as e:
                flash(f"Error: {e}")
                # Error handling code
            return redirect(url_for('index'))

    return render_template('index.html', form=form, scanned='ssids' in request.args)
    
@app.route('/scan', methods=['POST'])
def scan():
    form = WiFiForm()
    selected_interface = form.interface.data
    logging.debug(f"Scanning on {selected_interface}")

    ssids = execute_scan(selected_interface)
    return redirect(url_for('index', ssids=ssids))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5555)