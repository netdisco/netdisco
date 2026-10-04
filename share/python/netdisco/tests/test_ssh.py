"""
netdisco.util.ssh connects at import time, so each test installs a fake
netmiko, sets the environment the module reads, and imports it afresh.
"""

import importlib
import json
import os
import sys
import types
import unittest
from typing import ClassVar


class FakeConnectHandler:
    calls: ClassVar[list] = []

    def __init__(self, **kwargs):
        FakeConnectHandler.calls.append(kwargs)


ND2_ENV = ('ND2_CONFIGURATION', 'ND2_JOB_METADATA')
ND2_MODULES = ('netdisco.util.config', 'netdisco.util.job', 'netdisco.util.ssh')
STANZA = {'username': 'netdisco', 'password': 'secret', 'device_type': 'juniper_junos'}


def connect_kwargs_for(stanza):
    os.environ['ND2_CONFIGURATION'] = json.dumps({'device_auth': [stanza]})
    os.environ['ND2_JOB_METADATA'] = json.dumps({'action': 'arpnip', 'device': '192.0.2.1'})
    for name in ND2_MODULES:
        sys.modules.pop(name, None)
    importlib.import_module('netdisco.util.ssh')
    return FakeConnectHandler.calls[-1]


class SshHostKeyOptionsTest(unittest.TestCase):
    def setUp(self):
        self.saved_modules = {name: sys.modules.get(name) for name in ('netmiko', *ND2_MODULES)}
        self.saved_env = {name: os.environ.get(name) for name in ND2_ENV}
        fake_netmiko = types.ModuleType('netmiko')
        fake_netmiko.ConnectHandler = FakeConnectHandler
        sys.modules['netmiko'] = fake_netmiko
        FakeConnectHandler.calls = []

    def tearDown(self):
        for name, module in self.saved_modules.items():
            if module is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = module
        for name, value in self.saved_env.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value

    def test_ssh_module__stanza_without_host_key_options__verifies_against_known_hosts(self):
        kwargs = connect_kwargs_for(STANZA)
        self.assertIs(kwargs['ssh_strict'], True)
        self.assertIs(kwargs['system_host_keys'], True)
        self.assertNotIn('alt_host_keys', kwargs)
        self.assertEqual(kwargs['host'], '192.0.2.1')
        self.assertEqual(kwargs['username'], 'netdisco')
        self.assertEqual(kwargs['password'], 'secret')
        self.assertEqual(kwargs['device_type'], 'juniper_junos')

    def test_ssh_module__stanza_opts_out_of_strict_checking__passes_opt_out_to_netmiko(self):
        kwargs = connect_kwargs_for({**STANZA, 'ssh_strict': False})
        self.assertIs(kwargs['ssh_strict'], False)
        self.assertIs(kwargs['system_host_keys'], True)

    def test_ssh_module__stanza_names_alt_key_file__loads_host_keys_from_that_file(self):
        kwargs = connect_kwargs_for({**STANZA, 'alt_key_file': '/etc/netdisco/known_hosts'})
        self.assertIs(kwargs['alt_host_keys'], True)
        self.assertEqual(kwargs['alt_key_file'], '/etc/netdisco/known_hosts')
        self.assertIs(kwargs['ssh_strict'], True)


if __name__ == '__main__':
    unittest.main()
