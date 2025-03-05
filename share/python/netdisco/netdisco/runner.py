import os
import sys
from runpy import run_module
from netdisco.util.stash import stash
from netdisco.util.status import status
from netdisco.util.perl import piped_return, marshal_for_perl

if len(sys.argv) < 2 or len(sys.argv[1]) == 0:
    raise Exception('Missing temporary filename or "-" for context transfer')
contextfile = sys.argv[1]

while True:
    try:
        worklet = input()
    except EOFError:
        sys.exit(0)

    if len(worklet) == 0:
        sys.exit(0)

    if 'ND2_JOB_METADATA' not in os.environ:
        action = worklet.split('.')[2]
        os.environ['ND2_JOB_METADATA'] = f'{{"action":"{action}"}}'

    stash.load_vars()
    gd = run_module(worklet, run_name='__main__')

    context = gd['c'] if 'c' in gd else gd['context'] if 'context' in gd else None
    retval = marshal_for_perl(context)

    if contextfile == '-':
        print(piped_return(retval))
    else:
        with open(contextfile, 'w') as cf:
            cf.write(retval)

    status.reset()
    print('.')
