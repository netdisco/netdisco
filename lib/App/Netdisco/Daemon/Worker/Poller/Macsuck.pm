package App::Netdisco::Daemon::Worker::Poller::Macsuck;

use App::Netdisco::Core::Macsuck 'do_macsuck';
use App::Netdisco::Util::Device 'is_macsuckable';

use Role::Tiny;
use namespace::clean;

with 'App::Netdisco::Daemon::Worker::Poller::Common';

sub macsuck_action { \&do_macsuck }
sub macsuck_filter { \&is_macsuckable }
sub macsuck_layer { 2 }

sub macwalk { (shift)->_walk_body('macsuck', @_) }
sub macsuck { (shift)->_single_body('macsuck', @_) }

1;
