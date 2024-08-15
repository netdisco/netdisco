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
        return ND2_VARS[key] or self.store[key]

    def set(self, key, val):
        self.store[key] = val

stash = StashManager()