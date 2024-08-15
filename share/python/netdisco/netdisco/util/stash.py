"""
netdisco.util.stash
~~~~~~~~~~~~~~~~~~~

Access to Netdisco vars() stash.
"""

import os
import json

ND2_VARS = json.loads(os.environ['ND2_VARS'])


def stash(name):
    return ND2_VARS[name]
