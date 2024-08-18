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
import netdisco.util.status as status
import netdisco.util.config as config


@dataclass(frozen=True)
class Context:
    job: object = job.job
    stash: object = stash.stash
    status: object = status.status
    setting: function = config.setting


debug = log.debug
context = Context()
