"""
netdisco.util.log
~~~~~~~~~~~~~~~~~

This module provides a utility function debug() to emit log lines at level
DEBUG.
"""

import logging
from os import getpid
from .configuration import setting

logging.basicConfig(
    format=('[' + str(getpid()) + '] %(message)s'), level=getattr(logging, setting('log').upper())
)
log = logging.getLogger(__name__)


def debug(message):
    log.debug(str(message))
