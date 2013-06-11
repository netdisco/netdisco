package App::Netdisco::Daemon::Worker::Poller;

use Role::Tiny;
use namespace::clean;

# main worker body
with 'App::Netdisco::Daemon::Worker::Common';

# add dispatch methods for poller tasks
with 'App::Netdisco::Daemon::Worker::Poller::Device',
     'App::Netdisco::Daemon::Worker::Poller::Arpnip',
     'App::Netdisco::Daemon::Worker::Poller::Macsuck';

sub worker_type { 'pol' }
sub worker_name { 'Poller' }
sub munge_action { $_[1] }

1;
