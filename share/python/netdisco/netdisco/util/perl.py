import json


def return_to_perl(c):
    retval = {'status': c.status.status, 'log': c.status.log, 'vars': c.stash.store}
    print(json.dumps(retval, default=str))
