"""
netdisco.util.config
~~~~~~~~~~~~~~~~~~~~

Access to Netdisco runtime configuration.
"""

import os
import json

ND2_CONFIGURATION = json.loads(os.environ['ND2_CONFIGURATION'])


def setting(name):
    return ND2_CONFIGURATION[name]
