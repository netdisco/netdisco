"""
netdisco.util.perl
~~~~~~~~~~~~~~~~~~

This module provides a utility function return_to_perl() to marshall a Python worklet's
status and stash for passing back to Netdisco Perl-side.
"""

import json


def return_to_perl(c):
    retval = {'status': c.status.status, 'log': c.status.log, 'vars': c.stash.store}
    print(json.dumps(retval, default=str))
