"""
netdisco.util.configuration
~~~~~~~~~~~~~~~~~~~~~~~~~~~

This module provides a utility function setting() to get one of Netdisco's
configuration settings.
"""

import logging
from os import getpid

import os
import json
from dataclasses import dataclass, InitVar

# avoid circular dependency, this module may need to log.debug itself
logging.basicConfig(format=('[' + str(getpid()) + '] %(message)s'), level=getattr(logging, 'DEBUG'))
log = logging.getLogger(__name__)

ND2_JOB_VARS = json.loads(os.environ['ND2_JOB_VARS'])
ND2_JOB_CONFIGURATION = json.loads(os.environ['ND2_JOB_CONFIGURATION'])
ND2_RUNTIME_CONFIGURATION = json.loads(os.environ['ND2_RUNTIME_CONFIGURATION'])
# ND2_WORKER_CONFIGURATION  = json.loads(os.environ['ND2_WORKER_CONFIGURATION'])


def stash(name):
    return ND2_JOB_VARS[name]


def setting(name):
    return ND2_RUNTIME_CONFIGURATION[name]


@dataclass(frozen=True)
class Job:
    job: int
    action: str
    entered: str = ''
    started: str = ''
    finished: str = ''
    device: str = ''
    port: str = ''
    only_namespace: str = ''
    subaction: str = ''
    status: str = ''
    username: str = ''
    userip: str = ''
    log: str = ''
    device_key: str = ''
    job_priority: str = ''
    is_cancelled: bool = False
    is_offline: bool = False

    _current_phase: InitVar[str] = ''
    _last_namespace: InitVar[str] = ''
    _last_priority: InitVar[int] = 0
    _statuslist: InitVar[list] = []  # field(default_factory=list)

    def id(self) -> int:
        return self.job


job = Job(**ND2_JOB_CONFIGURATION)
