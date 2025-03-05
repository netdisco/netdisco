"""
netdisco.util.perl
~~~~~~~~~~~~~~~~~~

This module provides a utility function marshal_for_perl() to marshall a Python worklet's
status and stash for passing back to Netdisco Perl-side.
"""

import json
import base64
# from netdisco.util.log import debug


def marshal_for_perl(c):
    retval = {}

    if c is not None:
        retval = {'status': c.status.status, 'log': c.status.log, 'stash': c.stash.store}

    jstr = json.dumps(retval, default=str)
    # debug('returning: ' + jstr)
    return base64.b64encode(jstr.encode('ascii')).decode('ascii')


def piped_return(retval):
    return base64.b64decode(retval).decode('ascii')
