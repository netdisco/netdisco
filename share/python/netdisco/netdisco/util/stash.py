"""
netdisco.util.stash
~~~~~~~~~~~~~~~~~~~

Access to Netdisco vars() stash.
"""

import json
import sys
from dataclasses import dataclass, field


def refresh_stash():
    # this is safe because runner will have died if sys.arg[1] missing
    contextfile = sys.argv[1]
    with open(contextfile) as cf:
        stash = json.loads(cf.read())['vars']
    with open(contextfile, 'w') as cf:
        cf.truncate(0)
    return stash


@dataclass(frozen=True)
class StashManager:
    store: dict = field(default_factory=dict)
    stash: dict = field(default_factory=dict)

    def get(self, key):
        if key in self.store:
            return self.store[key]
        elif key in self.stash:
            return self.stash[key]
        else:
            raise KeyError(f'cannot find key "{key}" in Python stash or Perl/Dancer vars')

    def set(self, key, val):
        self.store[key] = val

    def load_stash(self):
        object.__setattr__(self, 'store', dict())
        object.__setattr__(self, 'stash', refresh_stash())


stash = StashManager()
