import sys
from runpy import run_module
from netdisco.util.perl import return_to_perl


def main():
    target = ['netdisco', 'worklet']

    if len(sys.argv) > 1:
        target.extend(sys.argv[1:])
    else:
        raise Exception('missing worklet name to runner')

    gd = run_module('.'.join(target), run_name='__main__')
    print(return_to_perl(gd['c']))


if __name__ == '__main__':
    main()
