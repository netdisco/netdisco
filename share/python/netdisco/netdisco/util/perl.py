import json


def return_to_perl(status, stash):
    retval = {'status': status.status, 'log': status.log, 'vars': stash}
    print(json.dumps(retval, default=str))
