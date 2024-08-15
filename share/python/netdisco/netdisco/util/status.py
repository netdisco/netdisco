"""
netdisco.util.status
~~~~~~~~~~~~~~~~~~~~

This module provides a Status class which models the return code and message
of a Python worklet along with convenience methods to set the status. A fresh
instance of the Status class has an empty message and null (empty string) message.
"""

from dataclasses import dataclass


@dataclass
class Status:
    status: str = ''
    log: str = ''

    def is_ok(self) -> bool:
        return True if self.status == 'done' else False

    def not_ok(self) -> bool:
        return not self.is_ok()

    def level(self) -> int:
        return (
            4
            if self.status == 'error'
            else 3
            if self.status == 'done'
            else 2
            if self.status == 'defer'
            else 1
            if self.status == 'info'
            else 0
        )

    def error(self, msg):
        self.status = 'error'
        self.log = msg

    def done(self, msg):
        self.status = 'done'
        self.log = msg

    def defer(self, msg):
        self.status = 'defer'
        self.log = msg

    def info(self, msg):
        self.status = 'info'
        self.log = msg
