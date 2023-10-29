from flask import Flask, render_template, request, redirect, url_for, flash
from flask_wtf import FlaskForm
from wtforms import SelectField, PasswordField
import os
import re
import logging

app = Flask(__name__)
app.config['SECRET_KEY'] = 'your_secret_key_here'

# Setup logging
logging.basicConfig(filename='flask_app.log', level=logging.DEBUG)

class WiFiForm(FlaskForm):
    ssid = SelectField('SSID', choices=[])
    password = PasswordField('Password')

@app.route('/', methods=['GET', 'POST'])
def index():
    form = WiFiForm()

    if form.validate_on_submit():
        ssid = form.ssid.data
        password = form.password.data
        # Here, add the logic to update the Wi-Fi connection
        # Avoid direct command execution with user input
        flash('Attempting to connect to {}'.format(ssid))
        return redirect(url_for('index'))

    # Set interface to wlan0 by default
    selected_interface = 'wlan0'
    command = ['sudo', 'iwlist', selected_interface, 'scan']
    scan_output = os.popen(' '.join(command)).read()
    ssids = [line for line in scan_output.splitlines() if "ESSID" in line]
    logging.debug("Scan output for {}: {}".format(selected_interface, scan_output))
    ssids = [re.search(r'"(.*?)"', s).group(1) for s in ssids if re.search(r'"(.*?)"', s)]
    logging.debug("Filtered SSIDs: {}".format(ssids))
    form.ssid.choices = [(s, s) for s in ssids]
    
    return render_template('index.html', form=form)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5555)
