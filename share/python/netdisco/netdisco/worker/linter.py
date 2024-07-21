import yamllint
from yamllint.config import YamlLintConfig
from netdisco.util.log import debug
from netdisco.util.configuration import job


def main():
    yaml_config = YamlLintConfig('{extends: relaxed, rules: {empty-lines: disable}}')
    target = job.subaction
    debug('target: ' + target)

    for p in yamllint.linter.run(open(target), yaml_config):
        debug(p.desc, p.line, p.rule)


if __name__ == '__main__':
    main()
