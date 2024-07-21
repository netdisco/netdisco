"""
netdisco.util.configuration
~~~~~~~~~~~~~~~~~~~~~~~~~~~

This module provides a utility function setting() to get one of Netdisco's
configuration settings.
"""

import os
import json

ND2_JOB_CONFIGURATION = json.loads(os.environ['ND2_JOB_CONFIGURATION'])
ND2_RUNTIME_CONFIGURATION = json.loads(os.environ['ND2_RUNTIME_CONFIGURATION'])
# ND2_WORKER_CONFIGURATION  = json.loads(os.environ['ND2_WORKER_CONFIGURATION'])


def setting(name):
    return ND2_RUNTIME_CONFIGURATION[name]


class Job:
    # TODO make readonly attributes
    def __init__(self, iterable=(), **kwargs):
        self.__dict__.update(iterable, **kwargs)


job = Job(ND2_JOB_CONFIGURATION)
