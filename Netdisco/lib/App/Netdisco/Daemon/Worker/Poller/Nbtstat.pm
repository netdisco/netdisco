package App::Netdisco::Daemon::Worker::Poller::Nbtstat;

use App::Netdisco::Core::Nbtstat 'do_nbtstat';
use App::Netdisco::Util::Node 'is_nbtstatable';

use Role::Tiny;
use namespace::clean;

with 'App::Netdisco::Daemon::Worker::Poller::Common';

sub nbtstat_action { \&do_nbtstat }
sub nbtstat_filter { \&is_nbtstatable }
sub nbtstat_ip_version { 4 }

sub nbtwalk { (shift)->_walk_nodes_body('nbtstat', @_) }
sub nbtstat  { (shift)->_single_node_body('nbtstat', @_) }

1;
