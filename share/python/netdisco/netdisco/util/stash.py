"""
netdisco.util.stash
~~~~~~~~~~~~~~~~~~~

Access to Netdisco vars() stash.
"""

import json
import sys
import os
from dataclasses import dataclass, field


def refresh_vars():
    # this is safe because runner will have died if sys.arg[1] missing
    contextfile = sys.argv[1]
    vars = dict()

    if contextfile == '-':
        vars = json.loads(os.environ.get('ND2_VARS', '{}'))
    else:
        try:
            with open(contextfile) as cf:
                vars = json.loads(cf.read())['vars']
            with open(contextfile, 'w') as cf:
                cf.truncate(0)
        except Exception:
            pass

    return vars


@dataclass(frozen=True)
class StashManager:
    vars: dict = field(default_factory=dict)
    store: dict = field(default_factory=dict)

    def get(self, key):
        if key in self.store:
            return self.store[key]
        elif key in self.vars:
            return self.vars[key]
        else:
            raise KeyError(f'cannot find key "{key}" in Python stash or Perl/Dancer vars')

    def set(self, key, val):
        self.store[key] = val

    def load_vars(self):
        object.__setattr__(self, 'vars', refresh_vars())
        object.__setattr__(self, 'store', dict())


stash = StashManager()
