import os
import sys
from runpy import run_module
from netdisco.util.perl import marshal_for_perl


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

    gd = run_module(worklet, run_name='__main__')

    context = gd['c'] if 'c' in gd else gd['context'] if 'context' in gd else None
    retval = marshal_for_perl(context)
    print(retval)
    print('.')
