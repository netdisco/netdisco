"""
netdisco.util.log
~~~~~~~~~~~~~~~~~

This module provides a utility function debug() to emit log lines at level
DEBUG (if Netdisco configuration enables that, with "log: debug"). Log
messages are prefixed with the current process ID.
"""

import logging
from os import getpid
from netdisco.util.config import setting

logging.basicConfig(
    format=('[' + str(getpid()) + '] %(message)s'), level=getattr(logging, setting('log').upper())
)
log = logging.getLogger(__name__)


def debug(message):
    log.debug(str(message))
