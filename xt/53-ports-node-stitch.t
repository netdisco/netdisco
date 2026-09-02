#!/usr/bin/env perl

# Task 2 of the Ports tab speedup replaces a three-way prefetch (ports to
# nodes to IPs) with two queries, joined by port name in Perl. This is the
# equivalence check between the two: the stitch must return the same ports,
# in the same order, carrying the same nodes, as the prefetch it replaces.
#
# Note there is no DANCER_ENVDIR=/dev/null here, unlike its neighbours. That
# setting empties the DSN, and this file needs a real one.

use strict;
use warnings;

use Test::More 0.88;

# Dancer's DSL is imported into its own package rather than into main, because
# it exports a `pass` that collides with Test::More's and Perl warns about the
# prototype mismatch.
{
    package NetdiscoSchema;
    use App::Netdisco;
    use Dancer qw/:moose :script/;
    use Dancer::Plugin::DBIC 'schema';
    sub connected { my $s = schema('netdisco'); $s->storage->dbh_do(sub { $_[1]->do('SELECT 1') }); return $s }
}

my $schema = eval { NetdiscoSchema::connected() };
my $why = $@;

# From here on a database is needed. Skipping is reported with the reason
# printed, never silently: a skip that hides a broken connection would leave
# this file green while proving nothing.
SKIP: {
    skip "no usable netdisco database: $why", 4 if not $schema;

    require App::Netdisco::Web::Plugin::Device::Ports;

    my ($device_ip) = $schema->resultset('Virtual::ActiveNode')
      ->search({}, { rows => 1 })->get_column('switch')->all;

    skip 'no device in this database has any active nodes', 4
      if not $device_ip;

    my $device = $schema->resultset('Device')->find($device_ip);
    my $base = $device->ports->with_properties->order_by_port_name;

    my @prefetched = $base->search({}, {
      prefetch => [ { active_nodes => 'ips' } ],
    })->all;

    my @stitched = $base->all;
    App::Netdisco::Web::Plugin::Device::Ports::_stitch_nodes(
      $schema, $device->ip, \@stitched, 'active_nodes', 'ips', [], []);

    # 1. The stitch returns the same ports, in the same order, as the prefetch.
    is_deeply [ map { $_->port } @stitched ], [ map { $_->port } @prefetched ],
      'stitch preserves the port set and the port order';

    # 2. Node sets per port match, compared as sorted MAC lists.
    my %stitched_macs_by_port = map {
        $_->port => [ sort map { $_->{mac} } @{ $_->{stitched_nodes} } ]
    } @stitched;
    my %prefetched_macs_by_port = map {
        $_->port => [ sort map { $_->mac } $_->active_nodes ]
    } @prefetched;
    is_deeply \%stitched_macs_by_port, \%prefetched_macs_by_port,
      'stitch attaches the same nodes to the same ports';

    # 3. The accessor trap: nothing may be attached under a relationship name.
    ok !exists $stitched[0]->{active_nodes},
      'stitched rows are not attached under the has_many accessor name';

    # 4. A port filter restricts the fetch to the ports named. The default
    #    Ports view has c_neighbors checked and c_nodes not, and reads node
    #    data only for a port carrying a remote_ip, so the route passes that
    #    short list instead of fetching every node on the device.
    my ($one_port) = grep { scalar @{ $stitched_macs_by_port{$_} } }
                     sort keys %stitched_macs_by_port;

    my @filtered = $base->all;
    App::Netdisco::Web::Plugin::Device::Ports::_stitch_nodes(
      $schema, $device->ip, \@filtered, 'active_nodes', 'ips', [], [], [$one_port]);

    is_deeply [ map  { $_->port }
                grep { scalar @{ $_->{stitched_nodes} } } @filtered ],
      [ $one_port ],
      'a port filter fetches nodes only for the ports named';
}

# Needs no database, so it stays outside the SKIP block: this is the load
# bearing check of the whole task, and inside the block CI would skip it and
# still report PASS.
require App::Netdisco::DB::Result::DevicePort;
ok !App::Netdisco::DB::Result::DevicePort->can('stitched_nodes'),
  'stitched_nodes is not a method, so Template Toolkit reaches the hash key';

# _node_fetch_scope is the route's decision of whether and how widely to
# fetch nodes, pulled out so it can be pinned without a session (the route
# is require_login and nothing in xt drives it). Required again here,
# unconditionally: the SKIP block above only requires this module when the
# database connects, and this check must run without one.
require App::Netdisco::Web::Plugin::Device::Ports;

# A fake row only needs port/remote_ip accessors; no database involved.
{
    package Fake::PortRow;
    sub new { my ($class, %args) = @_; return bless { %args }, $class }
    sub port { return $_[0]->{port} }
    sub remote_ip { return $_[0]->{remote_ip} }
}

my @rows_no_neighbors = (
    Fake::PortRow->new(port => 'Gi1/1'),
    Fake::PortRow->new(port => 'Gi1/2'),
);
my @rows_some_neighbors = (
    Fake::PortRow->new(port => 'Gi1/1', remote_ip => '10.0.0.1'),
    Fake::PortRow->new(port => 'Gi1/2'),
    Fake::PortRow->new(port => 'Gi1/3', remote_ip => '10.0.0.3'),
);

# 1. c_nodes on: fetch the whole device, whatever the rows look like. Both
#    flags on is the case with real user impact here: the c_nodes template
#    block reads every port's nodes, so a scoped fetch would blank some.
is_deeply App::Netdisco::Web::Plugin::Device::Ports::_node_fetch_scope(
  1, 0, \@rows_no_neighbors), [],
  'c_nodes on, c_neighbors off fetches the whole device';
is_deeply App::Netdisco::Web::Plugin::Device::Ports::_node_fetch_scope(
  1, 1, \@rows_some_neighbors), [],
  'c_nodes on, c_neighbors on also fetches the whole device';

# 2. c_nodes off, c_neighbors on, no row carries a remote_ip: fetch nothing
#    at all. This is the exact regression the route-level fix closes; see
#    _node_fetch_scope's comment in Ports.pm for the measurement.
is App::Netdisco::Web::Plugin::Device::Ports::_node_fetch_scope(
  0, 1, \@rows_no_neighbors), undef,
  'c_nodes off, c_neighbors on, no remote_ip anywhere fetches nothing';

# 3. c_nodes off, c_neighbors on, some rows carry a remote_ip: fetch exactly
#    those ports.
is_deeply App::Netdisco::Web::Plugin::Device::Ports::_node_fetch_scope(
  0, 1, \@rows_some_neighbors), ['Gi1/1', 'Gi1/3'],
  'c_nodes off, c_neighbors on, some remote_ip fetches only those ports';

# 4. Both off: fetch nothing.
is App::Netdisco::Web::Plugin::Device::Ports::_node_fetch_scope(
  0, 0, \@rows_some_neighbors), undef,
  'c_nodes and c_neighbors both off fetches nothing';

done_testing;
