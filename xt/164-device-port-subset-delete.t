#!/usr/bin/env perl

# Deleting some of a device's ports must remove per-port rows and nodes only
# for those ports; reducing the set to its device address wiped the rest of
# the device. These assert the generated SQL; no database needed.

use strict;
use warnings;

use Test::More 0.88;
use App::Netdisco::DB;

my $schema = do {
  local $SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /unversioned/ };
  my $s = App::Netdisco::DB->clone;
  $s->storage_type('::DBI::Pg');
  $s->connection('dbi:Pg:dbname=netdisco_xt_offline;host=127.0.0.1;port=1');
  $s;
};

my @PER_PORT_TABLES = qw/
  device_port_power device_port_properties device_port_ssid
  device_port_vlan device_port_wireless
/;

sub binds_of { map { ref $_ ? $_->[1] : $_ } @_ }

sub deletes_of {
  my ($ports_rs, $device_ports_total, $ports_total, @port_rows) = @_;
  my (%per_port, $node);
  our $device_count_query;
  $device_count_query = undef;
  no warnings 'redefine';
  local *DBIx::Class::ResultSetColumn::all = sub { ('192.0.2.1') };
  local *DBIx::Class::ResultSet::count = sub {
    $device_count_query = ${ $_[0]->as_query }
      if $_[0]->result_source->name eq 'device_port' && !$_[0]->{attrs}{columns};
    $_[0]->result_source->name eq 'device_port' && !$_[0]->{attrs}{columns}
      ? $device_ports_total : $ports_total };
  local *DBIx::Class::ResultSet::all = sub { @port_rows };
  local *App::Netdisco::DB::ResultSet::Node::delete = sub { $node = ${ $_[0]->as_query }; 0 };
  local *DBIx::Class::ResultSet::delete = sub {
    $per_port{ $_[0]->result_source->name } = ${ $_[0]->as_query }; 0 };
  $ports_rs->delete;
  return (\%per_port, $node, $device_count_query);
}

sub one_port_rs {
  $schema->resultset('DevicePort')->search_rs({ 'me.ip' => '192.0.2.1', 'me.port' => 'Gi1/1' });
}

subtest 'device_port_delete__subset__per_port_rows_by_ip_and_port' => sub {
  my ($per_port) = deletes_of(one_port_rs(), 48, 1, { ip => '192.0.2.1', port => 'Gi1/1' });
  foreach my $table (@PER_PORT_TABLES) {
    my ($sql, @bind) = @{ $per_port->{$table} };
    like($sql, qr/\(ip, port\) IN \(SELECT me\.ip, me\.port FROM device_port me/, "$table by ip and port");
    ok((grep { $_ eq 'Gi1/1' } binds_of(@bind)), "$table binds the port name");
  }
};

subtest 'device_port_delete__subset__nodes_by_switch_and_port' => sub {
  my (undef, $node) = deletes_of(one_port_rs(), 48, 1, { ip => '192.0.2.1', port => 'Gi1/1' });
  my ($sql, @bind) = @$node;
  like($sql, qr/switch = \?/, 'switch compared');
  like($sql, qr/port IN \( \? \)/, 'port compared with a bound list');
  is_deeply([ sort(binds_of(@bind)) ], [ sort('192.0.2.1', 'Gi1/1') ], 'switch and port bound');
};

subtest 'device_port_delete__subset_without_rows__deletes_no_nodes' => sub {
  my (undef, $node) = deletes_of(one_port_rs(), 48, 1);
  my ($sql, @bind) = @$node;
  like($sql, qr/0=1/, 'node delete matches nothing');
  is_deeply([ binds_of(@bind) ], [], 'nothing bound');
};

subtest 'device_port_delete__subset__device_wide_count_restricted_to_switch' => sub {
  my (undef, undef, $count_query) = deletes_of(one_port_rs(), 48, 1, { ip => '192.0.2.1', port => 'Gi1/1' });
  my ($sql, @bind) = @$count_query;
  like($sql, qr/ip IN \( \? \)/, 'count restricted to the switch list');
  is_deeply([ binds_of(@bind) ], ['192.0.2.1'], 'the switch address is bound');
};

subtest 'device_port_delete__whole_device__nodes_by_switch_list_only' => sub {
  my ($per_port, $node) = deletes_of(
    $schema->resultset('DevicePort')->search_rs({ 'me.ip' => '192.0.2.1' }), 48, 48);
  my ($sql, @bind) = @$node;
  like($sql, qr/switch IN \( \? \)/, 'switch compared with a bound list');
  unlike($sql, qr/WHERE.*port/, 'no port condition');
  is_deeply([ binds_of(@bind) ], ['192.0.2.1'], 'only the switch address is bound');
  unlike($per_port->{device_port_vlan}[0], qr/\(ip, port\)/, "per-port rows still removed by ip");
};

done_testing;
