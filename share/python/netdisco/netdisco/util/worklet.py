"""
netdisco.util.worklet
~~~~~~~~~~~~~~~~~~~~~

This module provides a "context" god-object instance with convenience functions helpful
for writing Python worklets. The context manages stash/vars and status, as well as providing
access to job metadata. For convenience netdisco.util.log.debug() is also shared.
"""

from dataclasses import dataclass
import netdisco.util.log as log
import netdisco.util.job as job
import netdisco.util.stash as stash
import netdisco.util.status as status
import netdisco.util.config as config
import netdisco.util.database as database

@dataclass(frozen=True)
class Context:
    job = job.job
    stash = stash.stash
    status = status.status
    db = database.engine

    @staticmethod
    def setting(name):
        return config.setting(name)


debug = log.debug
context = Context()
