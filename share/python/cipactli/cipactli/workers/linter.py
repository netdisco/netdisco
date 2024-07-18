
import os
import json
import logging
import yamllint
from yamllint.config import YamlLintConfig

def main():
  # TODO make this work outside of Perl worker (i.e. when missing)
  config = json.loads(os.environ['ND2_RUNTIME_CONFIGURATION'])
  logging.basicConfig(format=('['+ str(os.getpid()) +'] %(message)s'), level=getattr(logging, config['log'].upper()))

  # TODO make this work outside of Perl worker (i.e. when missing)
  job = json.loads(os.environ['ND2_JOB_CONFIGURATION'])
  target = job['subaction']

  # TODO provide a logger helper using Netdisco config or default
  log = logging.getLogger(__name__)

  yaml_config = YamlLintConfig('{extends: relaxed, rules: {empty-lines: disable}}')
  log.debug('target: ' + target)

  for p in yamllint.linter.run(open(target, "r"), yaml_config):
      log.error(p.desc, p.line, p.rule)

if __name__ == '__main__':
  main()
