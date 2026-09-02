#!/usr/bin/env perl

# Task 4 defers a port's node markup out of the DOM once it has more nodes
# than settings.devport_nodes_collapse_threshold, so the DataTables filter
# needs something else to search: a shadow string, built by Postgres, that
# carries every node's mac, ip, dns and vlan text for that port, plus ssid
# and netbios when asked for, whether or not the port's own markup is
# rendered this request.
#
# Same database SKIP pattern as xt/53-ports-node-stitch.t.

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

# node.vlan has no n_* guard in ports.tt (it is always shown), so it is
# always in the shadow. No want_ssid/want_netbios needed to see it.
SKIP: {
    skip "no usable netdisco database: $why", 1 if not $schema;

    # length(vlan) >= 3 avoids a false pass: a one- or two-digit vlan like
    # "1" is a substring of nearly any mac or IP text already in the shadow,
    # so an early version of this assertion passed against the unmodified
    # pre-fix _attach_search_shadow, which never selected vlan at all.
    # Caught by running it against that code and seeing it pass when it
    # should not have; narrowing to a 3+ digit vlan and requiring it match
    # as its own whitespace-delimited token made it fail there as expected.
    my ($vlan_switch, $vlan_port, $a_vlan) = $schema->storage->dbh_do(sub {
      my (undef, $dbh) = @_;
      $dbh->selectrow_array(q{
          SELECT switch, port, vlan
            FROM node
           WHERE active AND vlan IS NOT NULL AND length(vlan) >= 3
           LIMIT 1
      });
    });

    skip 'no active node in this database carries a 3+ digit vlan', 1
      if not defined $vlan_switch;

    my $vlan_device = $schema->resultset('Device')->find($vlan_switch);
    my ($vlan_row) = grep { $_->port eq $vlan_port }
      $vlan_device->ports->with_properties->order_by_port_name->all;

    skip 'port lookup for the vlan fixture came back empty', 1
      if not $vlan_row;

    App::Netdisco::Web::Plugin::Device::Ports::_attach_search_shadow(
      $schema, $vlan_device->ip, [$vlan_row],
      App::Netdisco::Web::Plugin::Device::Ports::_shadow_active_fragment('active_nodes'),
      0, 0);

    like $vlan_row->{nodes_search}, qr/(?:^|\s)\Q$a_vlan\E(?:\s|$)/,
      'the shadow carries a node VLAN as its own token, which has no n_* guard';
}

# SSID comes from node_wireless, keyed on mac alone (Node's wireless
# relation carries no active condition), and its lateral join in
# _attach_search_shadow is only added when want_ssid is true, mirroring
# ports.tt's own n_ssid guard.
SKIP: {
    skip "no usable netdisco database: $why", 2 if not $schema;

    # ssid !~ '\s' keeps the fixture to a single-token SSID: the shadow
    # joins fields with a bare space, so a multi-word SSID like "Guest Wifi"
    # would never satisfy a whitespace-anchored match on its own.
    my ($ssid_switch, $ssid_port, $an_ssid) = $schema->storage->dbh_do(sub {
      my (undef, $dbh) = @_;
      $dbh->selectrow_array(q{
          SELECT n.switch, n.port, w.ssid
            FROM node n
            JOIN node_wireless w ON w.mac = n.mac
           WHERE n.active AND length(w.ssid) > 0 AND w.ssid !~ '\s'
           LIMIT 1
      });
    });

    skip 'no active node in this database carries a single-token SSID', 2
      if not defined $ssid_switch;

    my $ssid_device = $schema->resultset('Device')->find($ssid_switch);
    my ($ssid_row) = grep { $_->port eq $ssid_port }
      $ssid_device->ports->with_properties->order_by_port_name->all;

    skip 'port lookup for the ssid fixture came back empty', 2
      if not $ssid_row;

    App::Netdisco::Web::Plugin::Device::Ports::_attach_search_shadow(
      $schema, $ssid_device->ip, [$ssid_row],
      App::Netdisco::Web::Plugin::Device::Ports::_shadow_active_fragment('active_nodes'),
      1, 0);
    like $ssid_row->{nodes_search}, qr/(?:^|\s)\Q$an_ssid\E(?:\s|$)/,
      'the shadow carries an SSID when n_ssid is on';

    App::Netdisco::Web::Plugin::Device::Ports::_attach_search_shadow(
      $schema, $ssid_device->ip, [$ssid_row],
      App::Netdisco::Web::Plugin::Device::Ports::_shadow_active_fragment('active_nodes'),
      0, 0);
    unlike $ssid_row->{nodes_search}, qr/(?:^|\s)\Q$an_ssid\E(?:\s|$)/,
      'the shadow does not carry the SSID when n_ssid is off, the conditional join is worth having';
}

# NetBIOS comes from node_nbt, also keyed on mac alone (Node's netbios
# relation carries no active condition), joined only when want_netbios is
# true, mirroring ports.tt's n_netbios guard.
SKIP: {
    skip "no usable netdisco database: $why", 7 if not $schema;

    # nbuser and ip render at ports.tt under the same n_netbios block as
    # nbname/domain (nbt.nbuser@nbt.ip), so all four need a fixture row that
    # carries all of them, or the nbuser/ip assertions below would be
    # vacuous. Two more filters guard against a false pass: nbuser often
    # equals nbname exactly (a machine logged in as itself), which would
    # pass the nbuser assertion even if nbuser were never added to the
    # shadow, and nbt.ip is frequently one of the node's own IPs, already
    # covered by the existing node_ip lateral, which would do the same to
    # the ip assertion. Both were caught this way against real data before
    # the fixture query below was narrowed.
    my ($nbt_switch, $nbt_port, $an_nbname, $a_domain, $a_nbuser, $an_ip) =
      $schema->storage->dbh_do(sub {
        my (undef, $dbh) = @_;
        $dbh->selectrow_array(q{
            SELECT n.switch, n.port, b.nbname, b.domain, b.nbuser, b.ip::text
              FROM node n
              JOIN node_nbt b ON b.mac = n.mac
             WHERE n.active AND length(b.nbname) > 0 AND length(b.domain) > 0
               AND length(b.nbuser) > 0 AND b.ip IS NOT NULL
               AND b.nbuser <> b.nbname
               AND NOT EXISTS (
                 SELECT 1 FROM node_ip i
                  WHERE i.mac = n.mac AND i.active = n.active AND i.ip = b.ip)
             LIMIT 1
        });
    });

    skip 'no active node in this database carries a NetBIOS name, domain, user and IP', 7
      if not defined $nbt_switch;

    my $nbt_device = $schema->resultset('Device')->find($nbt_switch);
    my ($nbt_row) = grep { $_->port eq $nbt_port }
      $nbt_device->ports->with_properties->order_by_port_name->all;

    skip 'port lookup for the netbios fixture came back empty', 7
      if not $nbt_row;

    App::Netdisco::Web::Plugin::Device::Ports::_attach_search_shadow(
      $schema, $nbt_device->ip, [$nbt_row],
      App::Netdisco::Web::Plugin::Device::Ports::_shadow_active_fragment('active_nodes'),
      0, 1);
    like $nbt_row->{nodes_search}, qr/(?:^|\s)\Q$an_nbname\E(?:\s|$)/,
      'the shadow carries a NetBIOS name when n_netbios is on';
    like $nbt_row->{nodes_search}, qr/(?:^|\s)\Q$a_domain\E(?:\s|$)/,
      'the shadow carries a NetBIOS domain when n_netbios is on';
    like $nbt_row->{nodes_search}, qr/(?:^|\s)\Q$a_nbuser\E(?:\s|$)/,
      'the shadow carries a NetBIOS user when n_netbios is on';
    like $nbt_row->{nodes_search}, qr/(?:^|\s)\Q$an_ip\E(?:\s|$)/,
      'the shadow carries a NetBIOS-reported IP when n_netbios is on';

    App::Netdisco::Web::Plugin::Device::Ports::_attach_search_shadow(
      $schema, $nbt_device->ip, [$nbt_row],
      App::Netdisco::Web::Plugin::Device::Ports::_shadow_active_fragment('active_nodes'),
      0, 0);
    unlike $nbt_row->{nodes_search}, qr/(?:^|\s)\Q$an_nbname\E(?:\s|$)/,
      'the shadow does not carry the NetBIOS name when n_netbios is off, the conditional join is worth having';
    unlike $nbt_row->{nodes_search}, qr/(?:^|\s)\Q$a_nbuser\E(?:\s|$)/,
      'the shadow does not carry the NetBIOS user when n_netbios is off';
    unlike $nbt_row->{nodes_search}, qr/(?:^|\s)\Q$an_ip\E(?:\s|$)/,
      'the shadow does not carry the NetBIOS-reported IP when n_netbios is off';
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
    sub remote_ip        { return $_[0]->{remote_ip} }
    sub remote_port      { return $_[0]->{remote_port} }
    sub remote_dns       { return $_[0]->{remote_dns} }
    sub remote_id        { return $_[0]->{remote_id} }
    sub remote_type      { return $_[0]->{remote_type} }
    sub remote_inventory { return $_[0]->{remote_inventory} }
    sub get_column       { my ($self, $col) = @_; return $self->{$col} }
}

# 1. c_neighbors on, a discovered neighbor with an alias: both the
#    device_port columns and the neighbor_alias columns are appended.
my $aliased = Fake::NeighborRow->new(
    remote_ip => '10.0.0.9', remote_port => 'Gi0/1', remote_dns => 'switch-a',
    neighbor_ip => '10.0.0.9', neighbor_dns => 'switch-a.example.com',
    nodes_search => 'aa:bb:cc:dd:ee:ff',
);
App::Netdisco::Web::Plugin::Device::Ports::_augment_neighbor_search([$aliased], 1, 0);
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
App::Netdisco::Web::Plugin::Device::Ports::_augment_neighbor_search([$unaliased], 0, 0);
like $unaliased->{nodes_search}, qr/switch-a/,
  'remote_dns is appended even with c_neighbors off, it is a real column';
unlike $unaliased->{nodes_search}, qr/example\.com/,
  'neighbor_ip/neighbor_dns are never read when c_neighbors is off';

# 3. No neighbor data at all: the existing shadow text is left alone.
my $plain = Fake::NeighborRow->new(nodes_search => 'untouched');
App::Netdisco::Web::Plugin::Device::Ports::_augment_neighbor_search([$plain], 1, 0);
is $plain->{nodes_search}, 'untouched',
  'a port with no neighbor data keeps its shadow text unchanged';

# 4. remote_id and remote_type are real device_port columns, so they are
#    appended unconditionally (ports.tt:438 renders remote_type for a
#    WAP/phone with no n_detailed_inventory guard at all).
my $identified = Fake::NeighborRow->new(
    remote_ip => '10.0.0.9', remote_id => 'chassis-42', remote_type => 'wap-model-x',
    nodes_search => '',
);
App::Netdisco::Web::Plugin::Device::Ports::_augment_neighbor_search([$identified], 0, 0);
like $identified->{nodes_search}, qr/chassis-42/,
  'remote_id is appended unconditionally';
like $identified->{nodes_search}, qr/wap-model-x/,
  'remote_type is appended unconditionally';

# 5. remote_inventory is a method, not a column: DevicePort.pm synthesizes
#    it from remote_os_ver/remote_serial/remote_vendor/remote_model, columns
#    selected only by with_remote_inventory, which the route applies only
#    under n_inventory. A row whose remote_inventory dies if called proves
#    the guard actually prevents the call, not merely skips the append; a
#    plain unlike/skip assertion here would pass just as well on a broken
#    implementation that reads the column and gets undef.
{
    package Fake::NeighborRowInventoryDies;
    sub new { my ($class, %args) = @_; return bless { %args }, $class }
    sub remote_ip   { return $_[0]->{remote_ip} }
    sub remote_port { return $_[0]->{remote_port} }
    sub remote_dns  { return $_[0]->{remote_dns} }
    sub remote_id   { return $_[0]->{remote_id} }
    sub remote_type { return $_[0]->{remote_type} }
    sub get_column  { my ($self, $col) = @_; return $self->{$col} }
    sub remote_inventory {
        die "remote_inventory called with n_inventory off, simulating a column that was never selected\n";
    }
}

my $uninventoried = Fake::NeighborRowInventoryDies->new(
    remote_ip => '10.0.0.9', nodes_search => '',
);
eval {
    App::Netdisco::Web::Plugin::Device::Ports::_augment_neighbor_search(
      [$uninventoried], 0, 0);
};
is $@, '', 'remote_inventory is never called when n_inventory is off, so it cannot 500 the route';

my $inventoried = Fake::NeighborRow->new(
    remote_ip => '10.0.0.9',
    remote_inventory => 'Cisco WS-C3560 running 15.2(4)E (SN123456)',
    nodes_search => '',
);
App::Netdisco::Web::Plugin::Device::Ports::_augment_neighbor_search([$inventoried], 0, 1);
like $inventoried->{nodes_search}, qr/WS-C3560/,
  'the inventory string is appended when n_inventory is on';

done_testing;
