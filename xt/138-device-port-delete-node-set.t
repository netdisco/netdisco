#!/usr/bin/env perl

# Deleting a device's ports selects its nodes by a list of switch addresses,
# not a subquery, so PostgreSQL uses the node switch index. These assert the
# generated SQL; no database needed.

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

sub node_set_of {
  my ($ports_rs, @switches) = @_;
  my $captured;
  no warnings 'redefine';
  local *DBIx::Class::ResultSetColumn::all = sub { @switches };
  local *App::Netdisco::DB::ResultSet::Node::delete = sub { $captured = ${ $_[0]->as_query }; 0 };
  local *DBIx::Class::ResultSet::delete = sub { 0 };
  $ports_rs->delete;
  my ($sql, @bind) = @$captured;
  return ($sql, [ map { ref $_ ? $_->[1] : $_ } @bind ]);
}

subtest 'device_port_delete__one_device__selects_nodes_by_switch_list' => sub {
  my ($sql, $bind) = node_set_of(
    $schema->resultset('DevicePort')->search_rs({ 'me.ip' => '192.0.2.1' }), '192.0.2.1');
  like($sql, qr/switch IN \( \? \)/, 'switch compared with a bound list');
  unlike($sql, qr/FROM device_port/, 'no device_port subquery');
  is_deeply($bind, ['192.0.2.1'], 'the switch address is bound');
};

subtest 'device_port_delete__device_subquery__still_selects_by_switch_list' => sub {
  my $devices = $schema->resultset('Device')->search_rs({ ip => '192.0.2.1' }, { columns => 'ip' });
  my ($sql, $bind) = node_set_of(
    $schema->resultset('DevicePort')->search_rs({ ip => { '-in' => $devices->as_query } }), '192.0.2.1');
  unlike($sql, qr/FROM device_port/, 'device delete path has no device_port subquery either');
  is_deeply($bind, ['192.0.2.1'], 'the switch address is bound');
};

subtest 'device_port_delete__no_ports__selects_no_nodes' => sub {
  my ($sql) = node_set_of($schema->resultset('DevicePort')->search_rs({ 'me.ip' => '192.0.2.9' }));
  like($sql, qr/0=1/, 'an empty switch list matches nothing');
};

done_testing;
