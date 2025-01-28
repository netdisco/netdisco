import platform
from netdisco.util.worklet import debug, context as c


def main():
    c.stash.set('python_ver', platform.python_version())
    debug('python version is: ' + c.stash.get('python_ver'))
    c.status.info('stashed Python version')


if __name__ == '__main__':
    main()
