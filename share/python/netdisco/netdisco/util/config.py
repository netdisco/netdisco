"""
netdisco.util.config
~~~~~~~~~~~~~~~~~~~~

Access to Netdisco runtime configuration.
"""

import os
import json

ND2_CONFIGURATION = json.loads(os.environ['ND2_CONFIGURATION'])


def setting(name):
    if name in ND2_CONFIGURATION:
        return ND2_CONFIGURATION[name]
    else:
        raise KeyError(f'unable to find setting "{name}" in Netdisco configuration')
