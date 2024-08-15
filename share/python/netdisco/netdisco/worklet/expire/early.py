import platform
from netdisco.util.worklet import context as c


def main():
    c.stash.set('python_ver', platform.python_version())
    c.status.info('stashed Python version')


if __name__ == '__main__':
    main()
