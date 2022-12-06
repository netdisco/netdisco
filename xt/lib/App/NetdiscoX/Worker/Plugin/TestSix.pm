package App::NetdiscoX::Worker::Plugin::TestSix;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

# info 'test: driverless actions always run';

register_worker({ phase => 'main', title => 'first driverless action' }, sub {
  return Status->done('OK: first driverless action is successful.');
});

register_worker({ phase => 'main', driver => 'snmp', title => 'worker at SNMP' }, sub {
  return Status->error('NOT OK: additional worker at SNMP level.');
});

register_worker({ phase => 'main', title => 'second driverless action' }, sub {
  return Status->done('OK: second driverless action is successful.');
});

true;
