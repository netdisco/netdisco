package App::NetdiscoX::Worker::Plugin::TestFive;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

# info 'test: add to an action';

register_worker({ phase => 'main', driver => 'snmp', title => 'NOT OK' }, sub {
  return Status->done('NOT OK: additional worker at SNMP level.');
});

register_worker({ phase => 'main', driver => 'snmp', title => 'OK' }, sub {
  return Status->done('OK: SNMP driver is successful.');
});

true;
