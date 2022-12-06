package App::NetdiscoX::Worker::Plugin::TestSeven;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

# info 'test: add to an action';

register_worker({ phase => 'main', driver => 'direct', title => 'cancelled' }, sub {
  return (shift)->cancel('NOT OK: cancelled job at direct level.');
});

register_worker({ phase => 'main', driver => 'snmp', title => 'OK' }, sub {
  return Status->done('OK: SNMP driver is successful.');
});

true;
