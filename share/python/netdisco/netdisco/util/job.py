"""
netdisco.util.job
~~~~~~~~~~~~~~~~~

Access to Netdisco job metadata.
"""

import os
import json
from dataclasses import dataclass, InitVar

ND2_JOB_METADATA = json.loads(os.environ['ND2_JOB_METADATA'])


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


job = Job(**ND2_JOB_METADATA)
