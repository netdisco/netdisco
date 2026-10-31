#!/usr/bin/env perl

# Pins the order /search tries things in when it picks a tab for a first search
# (#1429, #1789). The route needs a login and a schema, so both are faked as in
# xt/144: what is under test is the order of the checks and what each sends the
# user to, not the SQL, which xt/131 and xt/132 cover.
#
# THE TRAP, and the reason this file exists: #1429 moved the port check ahead of
# the device check for every search term. Port search also matches a neighbour's
# DNS name (remote_dns), so a device's own name that another switch sees over
# CDP or LLDP opened Port search instead of the device details page (#1789).
# The port check has to stay after the device check for names and addresses, and
# only a valid MAC address, which is not the device's own, is tried against
# ports first.
#
# The fake schema answers whatever is asked of it from the variables below, so
# it encodes how the route calls the schema: a DevicePort `all` is the MAC
# lookup (_mac_port_rs) and a DevicePort `count` is the name or port check. If
# the route changes how it asks, change the fake with it.

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use strict;
use warnings;
no warnings 'once'; # the glob overrides below are single-use by design

use Test::More 0.88;
use URI;
use App::Netdisco;
use App::Netdisco::Web;
use Dancer ':tests';
use Dancer::Test;

config->{logger} = 'null';

our ($devices, $mac_ports, $port_count, $mac_lookups);

package FakeRS;
sub new           { my ($c, $src) = @_; return bless {src => $src}, $c }
sub resultset     { return FakeRS->new($_[1]) }
sub with_properties { return $_[0] }
sub search        { return $_[0] }
sub get_distinct_col { return () }
sub search_fuzzy  { return FakeRS->new('DeviceMatch') }
sub first         { return $_[0] }
sub ip            { return $main::devices->[0] }
sub count {
  my $self = shift;
  return scalar @{ $main::devices } if $self->{src} eq 'DeviceMatch';
  return $main::port_count;
}
sub all { $main::mac_lookups++; return @{ $main::mac_ports } }

package FakePort;
sub new { my ($c, %a) = @_; return bless {type => 'ethernetCsmacd', is_uplink => 0, %a}, $c }
sub ip { $_[0]{ip} } sub port { $_[0]{port} } sub type { $_[0]{type} } sub is_uplink { $_[0]{is_uplink} }

package main;

no warnings 'redefine';
*Dancer::Plugin::Auth::Extensible::logged_in_user = sub { return { username => 'someone' } };
*Dancer::Plugin::Auth::Extensible::user_roles     = sub { return wantarray ? ('admin') : ['admin'] };
*App::Netdisco::Web::Search::schema               = sub { return FakeRS->new('Schema') };

set trust_x_remote_user => 1;

# Dancer::Handler resets the cookie jar at the start of every request and
# Dancer::Test does not, so without this one request's session would
# authenticate the next.
sub search_for {
  my ($q, %world) = @_;
  ($devices, $mac_ports, $port_count) = ($world{devices} || [], $world{mac_ports} || [], $world{ports} || 0);
  $mac_lookups = 0;
  Dancer::Cookies->init;
  return dancer_response(GET => '/search', {
    headers => [ 'X-REMOTE_USER' => 'someone' ],
    params  => { q => $q },
  });
}

# where a response sent the user: [path, {query}], or [undef, {tab => ...}] for
# a page that rendered in place on a tab
sub outcome {
  my $res = shift;
  if ($res->status =~ /^30\d$/) {
    my $u = URI->new($res->header('Location'));
    return [ $u->path, { $u->query_form } ];
  }
  my ($tab) = ($res->content || '') =~ /data-nd-active-tab="(\w+)"/;
  return [ undef, { tab => $tab } ];
}

my $mac = '04:bd:88:cd:93:7c';

# --- #1789: a name or address is matched against devices first -------------

is_deeply(outcome(search_for('sw.example.com', devices => ['192.0.2.1'], ports => 1)),
  ['/device', { tab => 'details', q => '192.0.2.1', f => '' }],
  'search_name__matches_one_device_and_a_neighbor_remote_dns__opens_the_device_details');
is($mac_lookups, 0, 'search_name__does_not_look_for_a_port_by_mac');

is_deeply(outcome(search_for('sw', devices => ['192.0.2.1', '192.0.2.2'], ports => 5)),
  [undef, { tab => 'device' }],
  'search_name__matches_several_devices__opens_device_search');

is_deeply(outcome(search_for('uplink-to-core', ports => 3)),
  [undef, { tab => 'port' }],
  'search_name__matches_no_device_but_a_port__opens_port_search');

is_deeply(outcome(search_for('nothing-here')),
  [undef, { tab => 'node' }],
  'search_name__matches_nothing__falls_back_to_node_search');

# a partial MAC is not a valid MAC, so it is a plain term and devices win
is_deeply(outcome(search_for('04:bd', devices => ['192.0.2.1'], ports => 2)),
  ['/device', { tab => 'details', q => '192.0.2.1', f => '' }],
  'search_partial_mac__matches_a_device_and_ports__opens_the_device_details');
is($mac_lookups, 0, 'search_partial_mac__does_not_look_for_a_port_by_mac');

# --- #1429: a valid MAC is matched against ports first ---------------------

is_deeply(outcome(search_for($mac,
    devices => ['192.0.2.1'],
    mac_ports => [ FakePort->new(ip => '192.0.2.1', port => 'Gi1/0/1') ])),
  ['/device', { tab => 'ports', q => '192.0.2.1', f => 'Gi1/0/1',
                c_mac => 'on', c_nodes => 'on', c_neighbors => 'on' }],
  'search_mac__matches_one_port__opens_ports_tab_filtered_to_it_even_though_a_device_matches_too');
is($mac_lookups, 1, 'search_mac__looks_for_ports_by_mac_once');

is_deeply(outcome(search_for($mac,
    devices => ['192.0.2.1', '192.0.2.2'],
    mac_ports => [ FakePort->new(ip => '192.0.2.1', port => 'a'),
                   FakePort->new(ip => '192.0.2.2', port => 'a', is_uplink => 1) ])),
  ['/search', { tab => 'port', q => $mac, partial => 'on', ethernet => 'on', uplink => 'on' }],
  'search_mac__matches_ports_on_several_devices__goes_to_port_search_with_uplinks_included');

is_deeply(outcome(search_for($mac, devices => ['192.0.2.1'])),
  ['/device', { tab => 'details', q => '192.0.2.1', f => '' }],
  'search_mac__matches_no_port_but_a_device__opens_the_device_details');

is_deeply(outcome(search_for($mac)),
  [undef, { tab => 'node' }],
  'search_mac__matches_no_port_or_device__falls_back_to_node_search');

# the null MAC is not a valid MAC, so it is never looked up
search_for('00:00:00:00:00:00', devices => ['192.0.2.1']);
is($mac_lookups, 0, 'search_null_mac__does_not_look_for_a_port_by_mac');

done_testing;
