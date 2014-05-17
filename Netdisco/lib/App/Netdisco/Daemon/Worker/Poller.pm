package App::Netdisco::Daemon::Worker::Poller;

use Role::Tiny;
use namespace::clean;

# main worker body
with 'App::Netdisco::Daemon::Worker::Common';

# add dispatch methods for poller tasks
with 'App::Netdisco::Daemon::Worker::Poller::Device',
     'App::Netdisco::Daemon::Worker::Poller::Arpnip',
     'App::Netdisco::Daemon::Worker::Poller::Macsuck',
     'App::Netdisco::Daemon::Worker::Poller::Nbtstat',
     'App::Netdisco::Daemon::Worker::Poller::Expiry';

sub worker_tag  { 'pol' }
sub worker_type { 'Poller' }
sub munge_action { $_[1] }

1;
