"""
netdisco.util.ssh
~~~~~~~~~~~~~~~~~

This module provides a netmiko connection handler using
the credentials in device_auth.
"""

import os
from netmiko import ConnectHandler

from netdisco.util.config import setting
from netdisco.util.job import job

if 'ND2_FSM_TEMPLATES' in os.environ:
    os.environ['NET_TEXTFSM'] = os.environ['ND2_FSM_TEMPLATES']

device_auth_setting = setting('device_auth')
if not isinstance(device_auth_setting, list):
    raise Exception('device_auth is not a list')
if len(device_auth_setting) != 1:
    raise Exception('device_auth for cli is not one entry only')

device_auth = device_auth_setting[0]
if not isinstance(device_auth, dict):
    raise Exception('device_auth[0] is not a dictionary')

target = {
    'host': job.device,
    'username': device_auth['username'],
    'password': device_auth['password'],
    'device_type': device_auth['device_type'],
}
net_connect = ConnectHandler(**target)
