#!/usr/bin/env perl

# The Ports tab gives a port's nodes cell a search shadow: a string built by
# Postgres carrying every node's mac, ip, dns and vlan text for that port,
# plus ssid and netbios when asked for. It is what the DataTables filter
# matches when the cell's own node markup is not rendered.
#
# Same database SKIP pattern as xt/53-ports-node-stitch.t.

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::Snapshot 'render_template';

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

    # Joined to node_ip rather than counting node alone: on a port whose
    # nodes carry no IPs, the IP assertion below would pass vacuously.
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

# vlan has no n_* guard in the template, so it is always in the shadow.
SKIP: {
    skip "no usable netdisco database: $why", 1 if not $schema;

    # length(vlan) >= 3 avoids a false pass: a one- or two-digit vlan is a
    # substring of nearly any mac or IP text already in the shadow, so the
    # assertion would hold even if vlan were never selected. Matching it as
    # its own whitespace-delimited token is part of the same guard.
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

# SSID comes from node_wireless, keyed on mac alone, and its lateral is joined
# only when want_ssid is true, mirroring the template's n_ssid guard.
SKIP: {
    skip "no usable netdisco database: $why", 2 if not $schema;

    # single-token SSID only: the shadow joins fields with a bare space, so a
    # multi-word SSID cannot satisfy a whitespace-anchored match.
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

# NetBIOS comes from node_nbt, also keyed on mac alone, joined only when
# want_netbios is true, mirroring the template's n_netbios guard.
SKIP: {
    skip "no usable netdisco database: $why", 7 if not $schema;

    # All four fields render under the one n_netbios block, so the fixture
    # row must carry all four. Two exclusions avoid a false pass: nbuser
    # equal to nbname would hold even if nbuser were never added to the
    # shadow, and an nbt.ip already among the node's own IPs is covered by
    # the node_ip lateral regardless.
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

# Outside the SKIP block deliberately: inside it, CI would skip this and still
# report PASS.
require App::Netdisco::DB::Result::DevicePort;
ok !App::Netdisco::DB::Result::DevicePort->can('nodes_search'),
  'nodes_search is not a method, so Template Toolkit reaches the hash key';

# _shadow_active_fragment reads $nodes_name alone, so it needs no database.
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
# c_nodes is on, the two cells being one <td> whose search text data-search
# replaces wholesale. A fake row only needs the accessors it reads.
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

# With c_neighbors off the +select supplying neighbor_ip/neighbor_dns is not
# in the query, so they must not be read at all.
my $unaliased = Fake::NeighborRow->new(
    remote_ip => '10.0.0.9', remote_port => 'Gi0/1', remote_dns => 'switch-a',
    nodes_search => '',
);
App::Netdisco::Web::Plugin::Device::Ports::_augment_neighbor_search([$unaliased], 0, 0);
like $unaliased->{nodes_search}, qr/switch-a/,
  'remote_dns is appended even with c_neighbors off, it is a real column';
unlike $unaliased->{nodes_search}, qr/example\.com/,
  'neighbor_ip/neighbor_dns are never read when c_neighbors is off';

my $plain = Fake::NeighborRow->new(nodes_search => 'untouched');
App::Netdisco::Web::Plugin::Device::Ports::_augment_neighbor_search([$plain], 1, 0);
is $plain->{nodes_search}, 'untouched',
  'a port with no neighbor data keeps its shadow text unchanged';

# remote_id and remote_type are device_port columns, appended unconditionally:
# the template renders remote_type with no n_detailed_inventory guard.
my $identified = Fake::NeighborRow->new(
    remote_ip => '10.0.0.9', remote_id => 'chassis-42', remote_type => 'wap-model-x',
    nodes_search => '',
);
App::Netdisco::Web::Plugin::Device::Ports::_augment_neighbor_search([$identified], 0, 0);
like $identified->{nodes_search}, qr/chassis-42/,
  'remote_id is appended unconditionally';
like $identified->{nodes_search}, qr/wap-model-x/,
  'remote_type is appended unconditionally';

# remote_inventory is a method reading columns only with_remote_inventory
# selects, which the route applies only under n_inventory. The fake row dies
# if it is called, so this proves the guard prevents the call rather than
# merely skipping the append: an unlike assertion would also pass on an
# implementation that read the column and got undef.
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

# The shadow is only reachable if DataTables sources the column's filter text
# from data-search, and it decides that from tbody tr:first-child alone, for the
# whole column. Emitting the attribute on the collapsed rows only, which is what
# this cell used to do, left the column reading rendered text and every shadow
# ignored, while every Perl assertion above still passed. The fixture puts one
# row over the collapse threshold and one under it, so a condition creeping back
# onto the attribute fails here.
subtest 'ports_tt__every_connected_nodes_cell__carries_data_search' => sub {
    my ($html, $error) = render_template('ajax/device/ports.tt');
    is $error, undef, 'renders' or return;

    my (undef, @rows) = split m/<tr\b/, $html;
    my @node_cells = grep { m/nd_nodes-total|nd_div-closer|data-search/ } @rows;
    cmp_ok scalar @node_cells, '>', 1,
      'the fixture renders more than one row carrying a nodes cell';

    my $with_attr = grep { m/<td[^>]*\sdata-search="/ } @node_cells;
    is $with_attr, scalar @node_cells,
      'every row with a nodes cell carries data-search, not just the collapsed ones';
};

done_testing;
