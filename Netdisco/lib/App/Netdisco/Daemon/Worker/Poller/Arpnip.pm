package App::Netdisco::Daemon::Worker::Poller::Arpnip;

use App::Netdisco::Core::Arpnip 'do_arpnip';
use App::Netdisco::Util::Device 'is_arpnipable';

use Role::Tiny;
use namespace::clean;

with 'App::Netdisco::Daemon::Worker::Poller::Common';

sub arpnip_action { \&do_arpnip }
sub arpnip_filter { \&is_arpnipable }
sub arpnip_layer { 3 }

sub arpwalk { (shift)->_walk_body('arpnip', @_) }
sub arpnip  { (shift)->_single_body('arpnip', @_) }

1;
