package App::NetdiscoX::Worker::Plugin::TestThree;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

# info 'test: respect user config filtering the driver, action and namespace';

register_worker({ phase => 'main', driver => 'cli' }, sub {
  return Status->done('NOT OK: CLI driver should NOT be run.');
});

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  return Status->done('OK: SNMP driver is successful.');
});

true;
