import yamllint
from yamllint.config import YamlLintConfig
from netdisco.util.log import debug
from netdisco.util.configuration import stash, job


def main():
    yaml_config = YamlLintConfig('{extends: relaxed, rules: {empty-lines: disable}}')
    target = job.subaction or stash('file_to_lint')
    debug('target: ' + target)

    for p in yamllint.linter.run(open(target), yaml_config):
        debug(f'{p.line}: ({p.rule}) {p.desc}')


if __name__ == '__main__':
    main()
