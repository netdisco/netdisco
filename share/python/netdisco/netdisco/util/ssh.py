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
    raise TypeError('device_auth is not a list')
if len(device_auth_setting) != 1:
    raise ValueError('device_auth for cli is not one entry only')

device_auth = device_auth_setting[0]
if not isinstance(device_auth, dict):
    raise TypeError('device_auth[0] is not a dictionary')

# netmiko accepts any host key and skips known_hosts unless told otherwise
target = {
    'host': job.device,
    'username': device_auth['username'],
    'password': device_auth['password'],
    'device_type': device_auth['device_type'],
    'ssh_strict': bool(device_auth.get('ssh_strict', True)),
    'system_host_keys': bool(device_auth.get('system_host_keys', True)),
}
if device_auth.get('alt_key_file'):
    target['alt_host_keys'] = True
    target['alt_key_file'] = device_auth['alt_key_file']
net_connect = ConnectHandler(**target)
