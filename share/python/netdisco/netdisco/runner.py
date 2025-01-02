import os
import sys
from runpy import run_module
from netdisco.util.perl import marshal_for_perl


def main():
    if len(sys.argv) > 1:
        action = sys.argv[1]
    else:
        raise Exception('missing action name to runner')

    if 'ND2_JOB_METADATA' not in os.environ:
        os.environ['ND2_JOB_METADATA'] = f'{{"action":"{action}"}}'

    worklets = []
    if len(sys.argv) > 2:
        worklets = sys.argv[2:]
    else:
        raise Exception('missing worklet names to runner')

    gd = run_module(worklets[0], run_name='__main__')
    context = gd['c'] if 'c' in gd else gd['context'] if 'context' in gd else None
    retval = marshal_for_perl(context)
    print(retval)


if __name__ == '__main__':
    main()
