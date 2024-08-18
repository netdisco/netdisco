"""
netdisco.util.stash
~~~~~~~~~~~~~~~~~~~

Access to Netdisco vars() stash.
"""

import os
import json
from dataclasses import dataclass, field

ND2_VARS = json.loads(os.environ['ND2_VARS'])

@dataclass(frozen=True)
class StashManager:
    store: dict = field(default_factory=dict)

    def get(self, key):
        if key in ND2_VARS:
            return ND2_VARS[key]
        elif key in self.store:
            return self.store[key]
        else:
            raise KeyError(f'cannot find key "{key}" in Perl/Dancer vars or Python stash')

    def set(self, key, val):
        self.store[key] = val

stash = StashManager()