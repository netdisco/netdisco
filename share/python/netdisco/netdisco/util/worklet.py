"""
netdisco.util.worklet
~~~~~~~~~~~~~~~~~~~~~

This module provides a "context" god-object instance with convenience functions helpful
for writing Python worklets. The context manages stash/vars and status, as well as providing
access to job metadata. For convenience netdisco.util.log.debug() is also shared.
"""

from dataclasses import dataclass, field
import netdisco.util.log as log
import netdisco.util.job as job
import netdisco.util.stash as stash
from netdisco.util.status import Status


@dataclass
class Stash:
    store: dict = field(default_factory=dict)

    def get(self, key):
        return stash.stash(key) or self.store[key]

    def set(self, key, val):
        self.store[key] = val


@dataclass(frozen=True)
class Context:
    job: object = job.job
    stash: Stash = Stash()
    status: Status = Status()


debug = log.debug
context = Context()
