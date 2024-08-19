import yamllint
from yamllint.config import YamlLintConfig
from netdisco.util.worklet import debug, context as c


def main():
    yaml_config = YamlLintConfig('{extends: relaxed, rules: {empty-lines: disable}}')
    target = c.job.subaction or c.stash.get('file_to_lint')
    debug('target: ' + target)

    found_issues = False
    for p in yamllint.linter.run(open(target), yaml_config):
        found_issues = True
        debug(f'{p.line}: ({p.rule}) {p.desc}')

    if found_issues:
        c.status.error('Lint errors, view with --debug')
    else:
        c.status.done('Linted OK')


if __name__ == '__main__':
    main()
