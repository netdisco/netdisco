package App::Netdisco::Daemon::Worker::Interactive;

use Role::Tiny;
use namespace::clean;

# main worker body
with 'App::Netdisco::Daemon::Worker::Common';

# add dispatch methods for interactive actions
with 'App::Netdisco::Daemon::Worker::Interactive::DeviceActions',
     'App::Netdisco::Daemon::Worker::Interactive::PortActions';

sub worker_tag  { 'int' }
sub worker_type { 'Interactive' }
sub munge_action { 'set_' . $_[1] }

1;
