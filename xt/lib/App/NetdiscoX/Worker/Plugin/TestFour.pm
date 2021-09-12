package App::NetdiscoX::Worker::Plugin::TestFour;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

# info 'test: override an action';

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  return Status->done('NOT OK: SNMP driver should NOT be run.');
});

register_worker({ phase => 'main', priority => 120 }, sub {
  return Status->done('OK: custom driver is successful.');
});

true;
