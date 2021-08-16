#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 1.302083;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

BEGIN {
  use_ok( 'App::Netdisco::Util::DNS', 'hostname_from_ip' );
}

use Dancer qw/:script !pass/;

# this is needed so that test works in github action container
# and actually ends up cutting out live DNS anyway 👍
config->{'dns'} = { 'ETCHOSTS' => { localhost => [ [ '127.0.0.1' ] ] } };

config->{'dns'}->{'no'} = ['::1','fe80::/10','127.0.0.0/8','169.254.0.0/16'];
is(hostname_from_ip('127.0.0.1'), undef, '127.0.0.1 blocked');

config->{'dns'}->{'no'} = ['::1','fe80::/10','169.254.0.0/16'];
is(hostname_from_ip('127.0.0.1'), 'localhost', '127.0.0.1 allowed');

done_testing;
