from dataclasses import dataclass, field
import netdisco.util.log as log
import netdisco.util.configuration as config
from netdisco.util.status import Status


@dataclass
class Stash:
    store: dict = field(default_factory=dict)

    def get(self, key):
        return config.stash(key) or self.store[key]

    def set(self, key, val):
        self.store[key] = val


@dataclass(frozen=True)
class Context:
    job: object = config.job
    stash: Stash = Stash()
    status: Status = Status()


debug = log.debug
context = Context()
