package App::Netdisco::Backend::Worker::Poller::Arpnip;

use App::Netdisco::Core::Arpnip 'do_arpnip';
use App::Netdisco::Util::Device 'is_arpnipable_now';

use Role::Tiny;
use namespace::clean;

with 'App::Netdisco::Backend::Worker::Poller::Common';

sub arpnip_action { \&do_arpnip }
sub arpnip_filter { \&is_arpnipable_now }
sub arpnip_layer { 3 }

sub arpwalk { (shift)->_walk_body('arpnip', @_) }
sub arpnip  { (shift)->_single_body('arpnip', @_) }

1;
