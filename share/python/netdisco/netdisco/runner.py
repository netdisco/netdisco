import sys
from runpy import run_module


def main():
    target = ['netdisco', 'worker']

    if len(sys.argv) > 1:
        target.append(sys.argv[1])
    else:
        raise Exception('missing worker name to runner')

    run_module('.'.join(target), run_name='__main__')


if __name__ == '__main__':
    main()
