package App::Netdisco::Backend::Worker::Poller;

use Role::Tiny;
use namespace::clean;

# main worker body
with 'App::Netdisco::Backend::Worker::Common';

# add dispatch methods for poller tasks
with 'App::Netdisco::Backend::Worker::Poller::Device',
     'App::Netdisco::Backend::Worker::Poller::Arpnip',
     'App::Netdisco::Backend::Worker::Poller::Macsuck',
     'App::Netdisco::Backend::Worker::Poller::Nbtstat',
     'App::Netdisco::Backend::Worker::Poller::Expiry',
     'App::Netdisco::Backend::Worker::Interactive::DeviceActions',
     'App::Netdisco::Backend::Worker::Interactive::PortActions';

1;
