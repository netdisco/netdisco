#!/usr/bin/env perl

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

BEGIN {
    use_ok( 'App::Netdisco::Util::Web', 'sort_port' );
}

#  1 = first is greater
#  0 = same
# -1 = first is lesser

is(sort_port(1,1), 0, 'number - same values');
is(sort_port('1:2','1:10'), -1, 'colon number (Extreme) - first lesser');
is(sort_port('D1','D10'), -1, 'HP - simple letter and number [#152]');

# Juniper examples for [#128]
# https://www.juniper.net/documentation/en_US/junos14.2/topics/concept/interfaces-interface-naming-overview.html
is(sort_port('so-1/0/0.0','so-1/0/1.0'), -1, 'juniper - FPC in slot 1 with OC3 PIC - 1');
is(sort_port('so-1/1/0.0','so-1/1/1.0'), -1, 'juniper - FPC in slot 1 with OC3 PIC - 2');
is(sort_port('so-1/0/0.0','so-1/1/0.0'), -1, 'juniper - FPC in slot 1 with OC3 PIC - 3');

is(sort_port('so-1/0/0:0','so-1/0/1:0'), -1, 'juniper - FPC in slot 1 with OC3 PIC channelized - 1');
is(sort_port('so-1/1/0:0','so-1/1/1:0'), -1, 'juniper - FPC in slot 1 with OC3 PIC channelized - 2');
is(sort_port('so-1/0/0:0','so-1/1/0:0'), -1, 'juniper - FPC in slot 1 with OC3 PIC channelized - 3');

done_testing;
