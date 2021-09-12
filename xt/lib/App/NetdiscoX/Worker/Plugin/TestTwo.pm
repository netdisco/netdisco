package App::NetdiscoX::Worker::Plugin::TestTwo;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

# info 'test: lower priority driver not run if higher is successful';

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  return Status->done('NOT OK: SNMP driver should NOT be run.');
});

register_worker({ phase => 'main', driver => 'cli' }, sub {
  return Status->done('OK: CLI driver is successful.');
});

true;
