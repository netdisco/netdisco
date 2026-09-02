#!/usr/bin/env perl

# Task 4 defers a port's node markup out of the DOM once it has more nodes
# than settings.devport_nodes_collapse_threshold, so the DataTables filter
# needs something else to search: a shadow string, built by Postgres, that
# carries every node's mac, ip and dns text for that port whether or not the
# port's own markup is rendered this request.
#
# Same database SKIP pattern as xt/52-ports-node-stitch.t.

use strict;
use warnings;

use Test::More 0.88;

{
    package NetdiscoSchema;
    use App::Netdisco;
    use Dancer qw/:moose :script/;
    use Dancer::Plugin::DBIC 'schema';
    sub connected { my $s = schema('netdisco'); $s->storage->dbh_do(sub { $_[1]->do('SELECT 1') }); return $s }
}

my $schema = eval { NetdiscoSchema::connected() };
my $why = $@;

SKIP: {
    skip "no usable netdisco database: $why", 3 if not $schema;

    require App::Netdisco::Web::Plugin::Device::Ports;

    # A port over the collapse threshold (20, config.yml's default), with at
    # least one of its nodes carrying an IP, so both assertions below have
    # something real to match. Joined to node_ip rather than counting node
    # alone, or the IP assertion could be vacuous on a port whose nodes carry
    # no IPs at all.
    my ($switch, $port) = $schema->storage->dbh_do(sub {
      my (undef, $dbh) = @_;
      $dbh->selectrow_array(q{
          SELECT n.switch, n.port
            FROM node n
            JOIN node_ip i ON i.mac = n.mac AND i.active = n.active
           WHERE n.active
           GROUP BY n.switch, n.port
          HAVING count(*) > 20
           ORDER BY count(*) DESC
           LIMIT 1
      });
    });

    skip 'no port in this database has more than 20 active nodes with an IP', 3
      if not defined $switch;

    my ($a_mac, $an_ip) = $schema->storage->dbh_do(sub {
      my (undef, $dbh) = @_;
      $dbh->selectrow_array(q{
          SELECT n.mac::text, i.ip::text
            FROM node n
            JOIN node_ip i ON i.mac = n.mac AND i.active = n.active
           WHERE n.switch = ? AND n.port = ? AND n.active
           LIMIT 1
      }, undef, $switch, $port);
    });

    my $device = $schema->resultset('Device')->find($switch);
    my @results = $device->ports->with_properties->order_by_port_name->all;

    App::Netdisco::Web::Plugin::Device::Ports::_stitch_nodes(
      $schema, $device->ip, \@results, 'active_nodes', 'ips', [], []);

    App::Netdisco::Web::Plugin::Device::Ports::_attach_search_shadow(
      $schema, $device->ip, \@results,
      App::Netdisco::Web::Plugin::Device::Ports::_shadow_active_fragment('active_nodes'));

    my ($row) = grep { $_->port eq $port } @results;

    like $row->{nodes_search}, qr/\Q$a_mac\E/,
      'the shadow carries a MAC from the port';
    like $row->{nodes_search}, qr/\Q$an_ip\E/,
      'the shadow carries an IP from the port';
    is scalar(grep { !exists $_->{nodes_search} } @results), 0,
      'every port has a shadow, including ports with no nodes';
}

# Needs no database, so it stays outside the SKIP block, the same reasoning
# as xt/52's equivalent check: inside the block CI would skip it and still
# report PASS, and this is the one guard CI can actually run.
require App::Netdisco::DB::Result::DevicePort;
ok !App::Netdisco::DB::Result::DevicePort->can('nodes_search'),
  'nodes_search is not a method, so Template Toolkit reaches the hash key';

# _shadow_active_fragment picks the SQL fragment from $nodes_name alone, the
# same value that picks the result class in Ports.pm's %node_result_class,
# so it needs no database either.
require App::Netdisco::Web::Plugin::Device::Ports;

is App::Netdisco::Web::Plugin::Device::Ports::_shadow_active_fragment('active_nodes'),
  'AND n.active', 'active_nodes gets the active-only fragment';
is App::Netdisco::Web::Plugin::Device::Ports::_shadow_active_fragment('active_nodes_with_age'),
  'AND n.active', 'active_nodes_with_age gets the active-only fragment too';
is App::Netdisco::Web::Plugin::Device::Ports::_shadow_active_fragment('nodes'),
  '', 'nodes (the archived view) gets no fragment, the whole table';
is App::Netdisco::Web::Plugin::Device::Ports::_shadow_active_fragment('nodes_with_age'),
  '', 'nodes_with_age gets no fragment either';

# _augment_neighbor_search keeps a port's own neighbor identity findable once
# c_nodes is also on: the neighbors cell and the nodes cell are the same <td>
# in ports.tt, and data-search on a <td> replaces its whole search text. A
# fake row only needs the accessors the function reads; no database involved.
{
    package Fake::NeighborRow;
    sub new { my ($class, %args) = @_; return bless { %args }, $class }
    sub remote_ip   { return $_[0]->{remote_ip} }
    sub remote_port { return $_[0]->{remote_port} }
    sub remote_dns  { return $_[0]->{remote_dns} }
    sub get_column  { my ($self, $col) = @_; return $self->{$col} }
}

# 1. c_neighbors on, a discovered neighbor with an alias: both the
#    device_port columns and the neighbor_alias columns are appended.
my $aliased = Fake::NeighborRow->new(
    remote_ip => '10.0.0.9', remote_port => 'Gi0/1', remote_dns => 'switch-a',
    neighbor_ip => '10.0.0.9', neighbor_dns => 'switch-a.example.com',
    nodes_search => 'aa:bb:cc:dd:ee:ff',
);
App::Netdisco::Web::Plugin::Device::Ports::_augment_neighbor_search([$aliased], 1);
like $aliased->{nodes_search}, qr/switch-a\.example\.com/,
  'a discovered neighbor alias name is appended when c_neighbors is on';
like $aliased->{nodes_search}, qr/\Qaa:bb:cc:dd:ee:ff\E/,
  'the existing shadow text is kept, not replaced';

# 2. c_neighbors off: neighbor_ip/neighbor_dns are never read (the +select
#    that would supply them is not in the query), only the always-safe
#    device_port columns are appended.
my $unaliased = Fake::NeighborRow->new(
    remote_ip => '10.0.0.9', remote_port => 'Gi0/1', remote_dns => 'switch-a',
    nodes_search => '',
);
App::Netdisco::Web::Plugin::Device::Ports::_augment_neighbor_search([$unaliased], 0);
like $unaliased->{nodes_search}, qr/switch-a/,
  'remote_dns is appended even with c_neighbors off, it is a real column';
unlike $unaliased->{nodes_search}, qr/example\.com/,
  'neighbor_ip/neighbor_dns are never read when c_neighbors is off';

# 3. No neighbor data at all: the existing shadow text is left alone.
my $plain = Fake::NeighborRow->new(nodes_search => 'untouched');
App::Netdisco::Web::Plugin::Device::Ports::_augment_neighbor_search([$plain], 1);
is $plain->{nodes_search}, 'untouched',
  'a port with no neighbor data keeps its shadow text unchanged';

done_testing;
