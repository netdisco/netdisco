#!/usr/bin/env perl

# Pins where a search for a MAC address that matches device ports sends the
# user (#1429, #1789). The decision is _mac_search_target, kept free of param()
# and the schema, so this needs no session and no database; the one query it
# depends on is checked as generated SQL, as in xt/131.
#
# The cases that matter:
#
# - One port opens that device's Ports tab filtered to the port, with the Port
#   MAC column on, which is what #1429 asked for.
# - Several ports on one device (a shared base MAC) open the device details.
# - Ports on several devices fall back to Port search, which hides uplinks and
#   non-Ethernet ports by default, so the redirect has to switch those off
#   when a matched port would be hidden or the page comes up empty. An absent
#   checkbox means unticked, so ethernet is sent only when every port is
#   Ethernet.
# - Port rows left behind by a deleted device must not count, or one real
#   device plus orphans is mistaken for several devices. The join to device is
#   what drops them, so it is asserted on the SQL.

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use strict;
use warnings;

use Test::More 0.88;
use App::Netdisco;
use App::Netdisco::Web;
use App::Netdisco::DB;

package FakePort;
sub new { my ($c, %a) = @_; return bless {type => 'ethernetCsmacd', is_uplink => 0, %a}, $c }
sub ip { $_[0]{ip} } sub port { $_[0]{port} } sub type { $_[0]{type} } sub is_uplink { $_[0]{is_uplink} }

package main;

sub target { return App::Netdisco::Web::Search::_mac_search_target('the-mac', [ map { FakePort->new(%$_) } @_ ]) }

is(target(), undef, 'mac_target__no_ports__is_undef');

is_deeply(target({ip => '192.0.2.1', port => 'Gi1/0/1'}),
  { path => '/device', query => {
      tab => 'ports', q => '192.0.2.1', f => 'Gi1/0/1',
      c_mac => 'on', c_nodes => 'on', c_neighbors => 'on' } },
  'mac_target__one_port__opens_ports_tab_filtered_to_it_with_port_mac_on');

is_deeply(target({ip => '192.0.2.1', port => 'Gi1/0/1'}, {ip => '192.0.2.1', port => 'Gi1/0/2'}),
  { path => '/device', query => { tab => 'details', q => '192.0.2.1', f => '' } },
  'mac_target__several_ports_on_one_device__opens_device_details');

# even when some are uplinks or not Ethernet, since it never reaches Port search
is_deeply(target({ip => '192.0.2.1', port => 'a', is_uplink => 1}, {ip => '192.0.2.1', port => 'b', type => 'other'}),
  { path => '/device', query => { tab => 'details', q => '192.0.2.1', f => '' } },
  'mac_target__several_ports_on_one_device_with_uplink_and_other_type__still_opens_device_details');

subtest 'mac_target__several_devices__port_search_options_follow_the_ports' => sub {
  my @two = ({ip => '192.0.2.1', port => 'a'}, {ip => '192.0.2.2', port => 'a'});
  my $q = sub { my $t = target(@_); is($t->{path}, '/search', 'goes to search'); return $t->{query} };

  is_deeply($q->(@two), { tab => 'port', q => 'the-mac', partial => 'on', ethernet => 'on' },
    'all ethernet and none uplink: ethernet kept, uplink not asked for');

  is_deeply($q->(@two, {ip => '192.0.2.2', port => 'b', is_uplink => 1}),
    { tab => 'port', q => 'the-mac', partial => 'on', ethernet => 'on', uplink => 'on' },
    'an uplink port: uplinks included');

  is_deeply($q->(@two, {ip => '192.0.2.2', port => 'b', type => 'propVirtual'}),
    { tab => 'port', q => 'the-mac', partial => 'on' },
    'a non-ethernet port: ethernet dropped');

  is_deeply($q->(@two, {ip => '192.0.2.2', port => 'b', type => undef}),
    { tab => 'port', q => 'the-mac', partial => 'on' },
    'a port with no type counts as non-ethernet, as in Port search');

  is_deeply($q->({ip => '192.0.2.1', port => 'a', is_uplink => 1, type => 'propVirtual'}, {ip => '192.0.2.2', port => 'a'}),
    { tab => 'port', q => 'the-mac', partial => 'on', uplink => 'on' },
    'uplink and non-ethernet together');
};

subtest 'mac_port_rs__joins_device_so_orphaned_port_rows_do_not_count' => sub {
  my $schema = do {
    local $SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /unversioned/ };
    my $s = App::Netdisco::DB->clone;
    $s->storage_type('::DBI::Pg');
    $s->connection('dbi:Pg:dbname=netdisco_xt_offline;host=127.0.0.1;port=1');
    $s;
  };
  my ($sql, @bind) = @{ ${ App::Netdisco::Web::Search::_mac_port_rs($schema, '04:bd:88:cd:93:7c')->as_query } };
  like($sql, qr/FROM device_port me\s+JOIN device device ON device\.ip = me\.ip/,
    'an inner join to device');
  like($sql, qr/me\.mac = \?/, 'compared with equality');
  like($sql, qr/SELECT me\.ip, me\.port, me\.type, me\.is_uplink FROM/,
    'only the columns the decision reads');
  is_deeply([ map { ref $_ ? $_->[1] : $_ } @bind ], ['04:bd:88:cd:93:7c'], 'the IEEE form is bound');
};

done_testing;
