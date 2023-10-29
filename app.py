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
        logging.debug(ssids)  # Debug log
        ssids = [re.search(r'"(.*?)"', s).group(1) for s in ssids]
        form.ssid.choices = [(s, s) for s in ssids]
    
    return render_template('index.html', form=form)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5555)
