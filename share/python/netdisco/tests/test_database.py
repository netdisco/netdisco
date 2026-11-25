"""
Netdisco exports the database port as PGPORT, and netdisco-web reads PORT as
its own listen port. The connector read PORT, so wherever PORT was set the
worklets connected to the web port instead of the database. #1768.

netdisco.util.database builds its URL at import time, so each test sets the
environment and imports it afresh.
"""

import importlib
import os
import sys
import unittest

PORT_ENV = ('PORT', 'PGPORT')
MODULE = 'netdisco.util.database'


def url_port_for(env):
    for name in PORT_ENV:
        os.environ.pop(name, None)
    os.environ.update(env)
    sys.modules.pop(MODULE, None)
    return importlib.import_module(MODULE).db_connect_url.port


class DatabasePortTest(unittest.TestCase):
    def setUp(self):
        self.saved_module = sys.modules.get(MODULE)
        self.saved_env = {name: os.environ.get(name) for name in PORT_ENV}

    def tearDown(self):
        for name, value in self.saved_env.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value
        if self.saved_module is None:
            sys.modules.pop(MODULE, None)
        else:
            sys.modules[MODULE] = self.saved_module

    def test_url__web_port_set__uses_pgport(self):
        self.assertEqual(url_port_for({'PORT': '5000', 'PGPORT': '5433'}), 5433)

    def test_url__only_web_port_set__leaves_port_to_libpq(self):
        self.assertIsNone(url_port_for({'PORT': '5000'}))

    def test_url__pgport_set__uses_pgport(self):
        self.assertEqual(url_port_for({'PGPORT': '5433'}), 5433)


if __name__ == '__main__':
    unittest.main()
