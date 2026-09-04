#!/usr/bin/env perl

# The Ports tab fetches nodes in a second query and joins them by port name
# rather than prefetching ports to nodes to IPs. This is the equivalence check
# between the two: the stitch must return the same ports, in the same order,
# carrying the same nodes, as the prefetch.
#
# No DANCER_ENVDIR=/dev/null here, unlike its neighbours: that empties the
# DSN, and this file needs a real one.

use strict;
use warnings;

use Test::More 0.88;

# Dancer's DSL goes in its own package: it exports a `pass` that collides with
# Test::More's, and Perl warns about the prototype mismatch.
{
    package NetdiscoSchema;
    use App::Netdisco;
    use Dancer qw/:moose :script/;
    use Dancer::Plugin::DBIC 'schema';
    sub connected { my $s = schema('netdisco'); $s->storage->dbh_do(sub { $_[1]->do('SELECT 1') }); return $s }
}

my $schema = eval { NetdiscoSchema::connected() };
my $why = $@;

# From here on a database is needed. The skip reason is always printed: a
# silent skip would leave this file green while proving nothing.
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

    is_deeply [ map { $_->port } @stitched ], [ map { $_->port } @prefetched ],
      'stitch preserves the port set and the port order';

    my %stitched_macs_by_port = map {
        $_->port => [ sort map { $_->{mac} } @{ $_->{stitched_nodes} } ]
    } @stitched;
    my %prefetched_macs_by_port = map {
        $_->port => [ sort map { $_->mac } $_->active_nodes ]
    } @prefetched;
    is_deeply \%stitched_macs_by_port, \%prefetched_macs_by_port,
      'stitch attaches the same nodes to the same ports';

    # nothing may be attached under a relationship name, or the accessor
    # would shadow the hash key the template reads
    ok !exists $stitched[0]->{active_nodes},
      'stitched rows are not attached under the has_many accessor name';

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

# Outside the SKIP block deliberately: inside it, CI would skip this and still
# report PASS.
require App::Netdisco::DB::Result::DevicePort;
ok !App::Netdisco::DB::Result::DevicePort->can('stitched_nodes'),
  'stitched_nodes is not a method, so Template Toolkit reaches the hash key';

# Required again here, unconditionally: the SKIP block above loads the module
# only when the database connects, and these checks must run without one.
require App::Netdisco::Web::Plugin::Device::Ports;

# A fake row only needs port/remote_ip accessors.
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

# c_nodes on returns [], meaning no restriction from this function: the route
# narrows that further itself (by node count, in _threshold_scope), which
# _node_fetch_scope has no part in and this file does not need to see.
is_deeply App::Netdisco::Web::Plugin::Device::Ports::_node_fetch_scope(
  1, 0, \@rows_no_neighbors), [],
  'c_nodes on, c_neighbors off fetches the whole device';
is_deeply App::Netdisco::Web::Plugin::Device::Ports::_node_fetch_scope(
  1, 1, \@rows_some_neighbors), [],
  'c_nodes on, c_neighbors on also fetches the whole device';

is App::Netdisco::Web::Plugin::Device::Ports::_node_fetch_scope(
  0, 1, \@rows_no_neighbors), undef,
  'c_nodes off, c_neighbors on, no remote_ip anywhere fetches nothing';

is_deeply App::Netdisco::Web::Plugin::Device::Ports::_node_fetch_scope(
  0, 1, \@rows_some_neighbors), ['Gi1/1', 'Gi1/3'],
  'c_nodes off, c_neighbors on, some remote_ip fetches only those ports';

is App::Netdisco::Web::Plugin::Device::Ports::_node_fetch_scope(
  0, 0, \@rows_some_neighbors), undef,
  'c_nodes and c_neighbors both off fetches nothing';

done_testing;
