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

# ACL Manager host ACLs are named groups, so groups can now refer to each
# other: a -> b -> a, or a group to itself, made this recurse without end.
# A group already being checked further up matches nothing where it recurs.
{
  config->{'host_groups'} ||= {};
  setting('host_groups')->{'cycle_self'} = ['group:cycle_self'];
  setting('host_groups')->{'cycle_a'}    = ['group:cycle_b'];
  setting('host_groups')->{'cycle_b'}    = ['group:cycle_a', '192.0.2.1'];
  local $SIG{ALRM} = sub { die "did not return\n" };
  alarm 5;
  my @got = eval { (
    (App::Netdisco::Util::DNS::check_acl_no_ipaddr_only('192.0.2.1', ['group:cycle_self']) ? 1 : 0),
    (App::Netdisco::Util::DNS::check_acl_no_ipaddr_only('192.0.2.1', ['group:cycle_a'])    ? 1 : 0),
    (App::Netdisco::Util::DNS::check_acl_no_ipaddr_only('192.0.2.9', ['group:cycle_a'])    ? 1 : 0),
  ) };
  alarm 0;
  is($@, '', 'a group cycle returns');
  is_deeply(\@got, [0, 1, 0], 'a group cycle matches only its own rules');
}

done_testing;
