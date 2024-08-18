import sys
from runpy import run_module
from netdisco.util.perl import marshal_for_perl


def main():
    target = ['netdisco', 'worklet']

    if len(sys.argv) > 1:
        target.extend(sys.argv[1:])
    else:
        raise Exception('missing worklet name to runner')

    gd = run_module('.'.join(target), run_name='__main__')
    context = gd['c'] if 'c' in gd else gd['context'] if 'context' in gd else None
    retval = marshal_for_perl(context)
    print(retval)


if __name__ == '__main__':
    main()
