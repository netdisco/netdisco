import json
import yamllint
from yamllint.config import YamlLintConfig
from netdisco.util.log import debug
from netdisco.util.configuration import stash, job


def main():
    yaml_config = YamlLintConfig('{extends: relaxed, rules: {empty-lines: disable}}')
    target = job.subaction or stash('file_to_lint')
    debug('target: ' + target)

    found_issues = False
    for p in yamllint.linter.run(open(target), yaml_config):
        found_issues = True
        debug(f'{p.line}: ({p.rule}) {p.desc}')

    # TODO provide a helper util for this
    retval = {
        'status': 'error' if found_issues else 'done',
        'log': 'Lint errors, view with --debug' if found_issues else 'Linted OK',
        'vars': {'a_new_key': 'a_new_value'},
    }
    print(json.dumps(retval, default=str))


if __name__ == '__main__':
    main()
