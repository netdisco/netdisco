package App::NetdiscoX::Worker::Plugin::TestOne;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

# info 'test: workers are run in decreasing priority until done';

register_worker({ phase => 'main', driver => 'cli' }, sub {
  return Status->noop('NOT OK: CLI driver is not the winner here.');
});

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  return Status->done('OK: SNMP driver is successful.');
});

true;
