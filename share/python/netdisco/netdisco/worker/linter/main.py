import yamllint
from yamllint.config import YamlLintConfig
from netdisco.util.log import debug
from netdisco.util.configuration import stash, job
from netdisco.util.status import Status


def main():
    yaml_config = YamlLintConfig('{extends: relaxed, rules: {empty-lines: disable}}')
    target = job.subaction or stash('file_to_lint')
    debug('target: ' + target)

    found_issues = False
    for p in yamllint.linter.run(open(target), yaml_config):
        found_issues = True
        debug(f'{p.line}: ({p.rule}) {p.desc}')

    # TODO still need a helper to make this more elegant
    globals()['status'] = (
        Status.error('Lint errors, view with --debug') if found_issues else Status.done('Linted OK')
    )
    globals()['stash'] = {'a_new_key': 'a_new_value'}


if __name__ == '__main__':
    main()
