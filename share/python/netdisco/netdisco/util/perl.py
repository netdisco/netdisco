"""
netdisco.util.perl
~~~~~~~~~~~~~~~~~~

This module provides a utility function marshal_for_perl() to marshall a Python worklet's
status and stash for passing back to Netdisco Perl-side.
"""

import json


def marshal_for_perl(c):
    retval = {'status': c.status.status, 'log': c.status.log, 'vars': c.stash.store}
    return json.dumps(retval, default=str)
