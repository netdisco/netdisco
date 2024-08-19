"""
netdisco.util.status
~~~~~~~~~~~~~~~~~~~~

This module provides a Status class which models the return code and message
of a Python worklet along with convenience methods to set the status. A fresh
instance of the Status class has an empty message and null (empty string) message.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class StatusManager:
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

    # this is pretty disgusting and must TODO come back and rework it

    def error(self, msg):
        object.__setattr__(self, 'status', 'error')
        object.__setattr__(self, 'log', msg)

    def done(self, msg):
        object.__setattr__(self, 'status', 'done')
        object.__setattr__(self, 'log', msg)

    def defer(self, msg):
        object.__setattr__(self, 'status', 'defer')
        object.__setattr__(self, 'log', msg)

    def info(self, msg):
        object.__setattr__(self, 'status', 'info')
        object.__setattr__(self, 'log', msg)


status = StatusManager()
