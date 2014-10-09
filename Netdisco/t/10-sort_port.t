#!/usr/bin/perl

use strict; use warnings FATAL => 'all';
use Test::More 0.88;

BEGIN {
    use_ok( 'App::Netdisco::Util::Web', 'sort_port' );
}

#  1 = first is greater
#  0 = same
# -1 = first is lesser

is(sort_port(1,1), 0, 'number - same values');
is(sort_port('1:2','1:10'), -1, 'colon number (Extreme) - first lesser');
is(sort_port('D1','D10'), -1, 'HP - simple letter and number [#152]');

done_testing;
