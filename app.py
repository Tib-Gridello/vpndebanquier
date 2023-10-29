from flask import Flask, render_template, request, redirect, url_for, flash
from flask_wtf import FlaskForm
from wtforms import SelectField, PasswordField, SubmitField
import os
import re
import logging

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

@app.route('/', methods=['GET', 'POST'])
def index():
    form = WiFiForm()

    # Whitelist interfaces
    interfaces = [i for i in os.listdir('/sys/class/net/') if re.match(r'wlan\d+', i)]
    form.interface.choices = [(i, i) for i in interfaces]

    if form.validate_on_submit():
        if form.scan.data:
            selected_interface = form.interface.data
            command = ['sudo', 'iwlist', selected_interface, 'scan']
            scan_output = os.popen(' '.join(command)).read()
            ssids = [line for line in scan_output.splitlines() if "ESSID" in line]
            ssids = [re.search(r'"(.*?)"', s).group(1) for s in ssids if re.search(r'"(.*?)"', s)]
            form.ssid.choices = [(s, s) for s in ssids]
            return render_template('index.html', form=form, scanned=True)

        if form.connect.data:
            # Add the logic to update the Wi-Fi connection
            interface = form.interface.data
            ssid = form.ssid.data
            password = form.password.data
            flash('Attempting to connect to {} on {}'.format(ssid, interface))
            return redirect(url_for('index'))

    return render_template('index.html', form=form, scanned=False)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5555)
