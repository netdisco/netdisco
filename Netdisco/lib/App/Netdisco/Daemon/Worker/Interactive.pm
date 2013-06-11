package App::Netdisco::Daemon::Worker::Interactive;

use Role::Tiny;
use namespace::clean;

# main worker body
with 'App::Netdisco::Daemon::Worker::Common';

# add dispatch methods for interactive actions
with 'App::Netdisco::Daemon::Worker::Interactive::DeviceActions',
     'App::Netdisco::Daemon::Worker::Interactive::PortActions';

sub worker_type { 'int' }
sub worker_name { 'Interactive' }
sub munge_action { 'set_' . $_[1] }

1;
